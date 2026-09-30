import 'dart:js_interop';

import 'voice_input_service.dart';

@JS('window.sayFridgeVoiceInput.start')
external JSBoolean _start(
  JSFunction onWords,
  JSFunction onError,
  JSFunction shouldContinue,
);

@JS('window.sayFridgeVoiceInput.stop')
external JSPromise<JSAny?> _stop();

@JS('window.sayFridgeVoiceInput.cancel')
external JSPromise<JSAny?> _cancel();

/// Start inside the pointer-down gesture and use a new browser recognizer for
/// every hold. WebKit can stop producing results when an instance is reused.
class BrowserVoiceInputService implements VoiceInputService {
  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  }) async {
    try {
      return _start(
        ((JSString words) => onWords(words.toDart)).toJS,
        ((JSString error) => onError(
          voiceInputErrorMessage(error.toDart),
        )).toJS,
        (() => shouldContinue().toJS).toJS,
      ).toDart;
    } catch (_) {
      onError('Unable to start voice recognition. Please try again.');
      return false;
    }
  }

  @override
  Future<void> stop() async => await _stop().toDart;

  @override
  Future<void> cancel() async => await _cancel().toDart;
}
