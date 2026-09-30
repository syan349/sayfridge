import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/services/voice_input_service.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  test(
    'accepts browser start before the asynchronous listening event',
    () async {
      final speech = _Speech();
      final service = DeviceVoiceInputService(speech);
      final words = <String>[];
      final errors = <String>[];
      expect(
        await service.start(
          onWords: words.add,
          onError: errors.add,
          shouldContinue: () => true,
        ),
        isTrue,
      );
      expect(speech.isListening, isFalse);
      expect(speech.options?.localeId, 'en-US');
      expect(speech.options?.partialResults, isTrue);
      speech.statusListener?.call('listening');
      speech.result('two bottles', finalResult: false);
      expect(words, ['two bottles']);
      expect(errors, isEmpty);
      await service.cancel();
    },
  );

  test('release waits for text delivered after the microphone stops', () async {
    final speech = _Speech();
    final service = DeviceVoiceInputService(speech);
    final words = <String>[];
    await service.start(
      onWords: words.add,
      onError: fail,
      shouldContinue: () => true,
    );
    var finished = false;
    final stopping = service.stop().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(speech.stops, 1);
    expect(finished, isFalse);
    speech.result('I bought two bottles of milk', finalResult: true);
    await stopping;
    expect(words, ['I bought two bottles of milk']);
    expect(finished, isTrue);
  });

  test(
    'late browser permission after release aborts the listening session',
    () async {
      final speech = _Speech();
      final service = DeviceVoiceInputService(speech);
      await service.start(
        onWords: (_) {},
        onError: fail,
        shouldContinue: () => true,
      );
      final stopping = service.stop();
      await Future<void>.delayed(Duration.zero);
      speech.statusListener?.call('listening');
      await stopping;
      expect(speech.cancels, 1);
    },
  );

  test(
    'cancel ignores late results and a late browser listening event',
    () async {
      final speech = _Speech();
      final service = DeviceVoiceInputService(speech);
      final words = <String>[];
      await service.start(
        onWords: words.add,
        onError: fail,
        shouldContinue: () => true,
      );
      await service.cancel();
      speech.result('discard this', finalResult: true);
      speech.statusListener?.call('listening');
      expect(words, isEmpty);
      expect(speech.cancels, 2);
    },
  );

  test(
    'restart waits for asynchronous abort/end and ignores old errors',
    () async {
      final speech = _Speech()..delayCancelEnd = true;
      final service = DeviceVoiceInputService(speech);
      final firstWords = <String>[];
      final words = <String>[];
      final errors = <String>[];
      await service.start(
        onWords: firstWords.add,
        onError: errors.add,
        shouldContinue: () => true,
      );
      var cancelled = false;
      final cancelling = service.cancel().then((_) => cancelled = true);
      final restarting = service.start(
        onWords: words.add,
        onError: errors.add,
        shouldContinue: () => true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isFalse);
      expect(speech.listens, 1);
      speech.errorListener?.call(SpeechRecognitionError('aborted', false));
      speech.result('discard this', finalResult: true);
      speech.statusListener?.call(SpeechToText.doneStatus);
      await Future<void>.delayed(Duration.zero);
      // The web plugin sends done on error, before the recognizer is idle.
      expect(speech.listens, 1);
      speech.statusListener?.call(SpeechToText.notListeningStatus);
      await cancelling;
      expect(await restarting, isTrue);
      speech.statusListener?.call(SpeechToText.listeningStatus);
      speech.result('two tomatoes', finalResult: false);
      expect(firstWords, isEmpty);
      expect(words, ['two tomatoes']);
      expect(errors, isEmpty);
      speech.delayCancelEnd = false;
      await service.cancel();
    },
  );

  test(
    'release during abort cleanup does not start the next microphone',
    () async {
      final speech = _Speech()..delayCancelEnd = true;
      final service = DeviceVoiceInputService(speech);
      var holding = true;
      await service.start(
        onWords: (_) {},
        onError: fail,
        shouldContinue: () => holding,
      );
      final cancelling = service.cancel();
      final restarting = service.start(
        onWords: (_) => fail('Unexpected transcript'),
        onError: fail,
        shouldContinue: () => holding,
      );
      holding = false;
      await service.stop();
      speech.statusListener?.call(SpeechToText.notListeningStatus);
      await cancelling;
      expect(await restarting, isFalse);
      expect(speech.listens, 1);
    },
  );

  test(
    'releasing while permissions are pending never starts the microphone',
    () async {
      final speech = _Speech()..permission = Completer<bool>();
      final service = DeviceVoiceInputService(speech);
      var holding = true;
      final starting = service.start(
        onWords: (_) => fail('Unexpected transcript'),
        onError: fail,
        shouldContinue: () => holding,
      );
      holding = false;
      await service.stop();
      speech.permission!.complete(true);
      expect(await starting, isFalse);
      expect(speech.listens, 0);
    },
  );

  test(
    'reopened page receives errors from the shared speech instance',
    () async {
      final speech = _Speech();
      final first = DeviceVoiceInputService(speech);
      final oldErrors = <String>[];
      await first.start(
        onWords: (_) {},
        onError: oldErrors.add,
        shouldContinue: () => true,
      );
      await first.cancel();
      final next = DeviceVoiceInputService(speech);
      final errors = <String>[];
      await next.start(
        onWords: (_) {},
        onError: errors.add,
        shouldContinue: () => true,
      );
      speech.errorListener?.call(SpeechRecognitionError('network', false));
      expect(oldErrors, isEmpty);
      expect(errors.single, contains('network'));
    },
  );
}

class _Speech extends SpeechToText {
  _Speech() : super.withMethodChannel();

  Completer<bool>? permission;
  bool initialized = false;
  bool delayCancelEnd = false;
  int listens = 0, stops = 0, cancels = 0;
  SpeechResultListener? resultListener;
  SpeechListenOptions? options;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    dynamic debugLogging = false,
    Duration finalTimeout = const Duration(seconds: 2),
    List<SpeechConfigOption>? options,
  }) async {
    if (initialized) return true;
    errorListener = onError;
    statusListener = onStatus;
    final available = permission == null ? true : await permission!.future;
    initialized = available;
    return available;
  }

  @override
  Future<void> listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    dynamic cancelOnError = false,
    dynamic partialResults = true,
    dynamic onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    dynamic sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    listens++;
    resultListener = onResult;
    options = listenOptions;
  }

  void result(String words, {required bool finalResult}) {
    resultListener?.call(
      SpeechRecognitionResult.init([
        SpeechRecognitionWords(words, null, 1),
      ], finalResult ? ResultType.finalResult : ResultType.partial),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    statusListener?.call(SpeechToText.notListeningStatus);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (!delayCancelEnd) statusListener?.call(SpeechToText.notListeningStatus);
  }
}
