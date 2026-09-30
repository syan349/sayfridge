import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

String voiceInputErrorMessage(String error) {
  final code = error.toLowerCase();
  return code.contains('not-allowed') || code.contains('permission')
      ? 'Allow microphone and speech recognition access in your browser or device settings.'
      : code.contains('network')
      ? 'Voice recognition could not connect. Check your network and try again.'
      : code.contains('not_supported') || code.contains('not supported')
      ? 'Speech recognition is unavailable in this browser. Please use keyboard input.'
      : code.contains('no-speech') || code.contains('no_match')
      ? 'No speech was recognized. Hold the voice bar while speaking, then release.'
      : 'Voice recognition stopped. Please try again.';
}

abstract class VoiceInputService {
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  });

  Future<void> stop();
  Future<void> cancel();
}

class DeviceVoiceInputService implements VoiceInputService {
  DeviceVoiceInputService([SpeechToText? speech])
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  int _generation = 0;
  bool _active = false;
  bool _listenRequested = false;
  bool _stopping = false;
  Completer<void>? _finished;
  Completer<void>? _engineEnded;
  Future<void>? _cancelling;
  void Function(String message)? _onError;

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  }) async {
    final generation = ++_generation;
    // abort() returns before the browser emits error/end. Do not rebind the
    // shared recognizer's callbacks or restart it until that session ends.
    await _cancelling;
    if (generation != _generation || !shouldContinue()) return false;
    _active = true;
    _listenRequested = false;
    _stopping = false;
    _finished = Completer<void>();
    _onError = onError;
    try {
      final available = await _speech.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
      if (generation != _generation || !shouldContinue()) return false;
      // SpeechToText is shared and initialize only installs listeners once.
      // Bind callbacks to the current screen/session when it is reopened.
      _speech.errorListener = _handleError;
      _speech.statusListener = _handleStatus;
      if (!available) {
        _active = false;
        return false;
      }
      _listenRequested = true;
      _engineEnded = Completer<void>();
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (!_active || generation != _generation) return;
          onWords(result.recognizedWords);
          if (_stopping && result.finalResult) _complete();
        },
        listenOptions: SpeechListenOptions(
          localeId: 'en-US',
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      // Browser onstart arrives asynchronously, after listen() returns.
      // isListening is still false here even when start was accepted.
      return generation == _generation && _active;
    } catch (_) {
      if (generation == _generation && _active) {
        _fail(
          'Unable to start voice recognition. Check microphone permission and try again.',
        );
      }
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    if (!_listenRequested) {
      // Release during a permission prompt must invalidate the pending start.
      ++_generation;
      _active = false;
      _complete();
      return;
    }
    final generation = _generation;
    final finished = _finished!;
    final ended = _engineEnded;
    _stopping = true;
    try {
      await _speech.stop();
      // stop() stops the microphone; its Future does not contain the final
      // transcription. Keep accepting callbacks until completion (bounded).
      await finished.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () async {
          if (generation == _generation) await _cancelRecognizer();
        },
      );
      // A final transcript can precede the browser's end event too.
      await _waitForEngineEnd(ended);
    } catch (_) {
      if (generation == _generation && _active) {
        _fail('Unable to finish voice recognition. Please try again.');
      }
    } finally {
      if (generation == _generation) {
        _active = false;
        _stopping = false;
      }
    }
  }

  @override
  Future<void> cancel() async {
    ++_generation;
    _active = false;
    _stopping = false;
    _complete();
    await _cancelRecognizer();
  }

  Future<void> _cancelRecognizer() {
    return _cancelling ??= _cancelAndWait().whenComplete(() {
      _cancelling = null;
    });
  }

  Future<void> _cancelAndWait() async {
    final ended = _engineEnded;
    await _speech.cancel();
    await _waitForEngineEnd(ended);
  }

  Future<void> _waitForEngineEnd(Completer<void>? ended) async {
    if (ended == null) return;
    await ended.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  void _complete() {
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
  }

  void _handleStatus(String status) {
    if (status == SpeechToText.notListeningStatus) {
      final ended = _engineEnded;
      if (ended != null && !ended.isCompleted) ended.complete();
    }
    if ((!_active || _stopping) && status == SpeechToText.listeningStatus) {
      // Some browsers can grant permission after the finger was released.
      unawaited(_cancelRecognizer());
      _complete();
    }
    if (status == SpeechToText.doneStatus) _complete();
  }

  void _handleError(SpeechRecognitionError error) {
    _fail(voiceInputErrorMessage(error.errorMsg));
  }

  void _fail(String message) {
    if (!_active) return;
    _active = false;
    _complete();
    unawaited(_cancelRecognizer());
    _onError?.call(message);
  }
}
