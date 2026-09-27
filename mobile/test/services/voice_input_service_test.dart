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
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}
