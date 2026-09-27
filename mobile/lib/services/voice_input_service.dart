import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(String message) onError,
    required bool Function() shouldContinue,
  }) async {
    final available = await _speech.initialize(
      onError: (SpeechRecognitionError error) => onError(
        error.permanent
            ? 'Microphone or speech recognition permission was denied.'
            : 'Voice recognition stopped. Please try again.',
      ),
    );
    if (!available || !shouldContinue()) return false;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onWords(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
    return _speech.isListening;
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
