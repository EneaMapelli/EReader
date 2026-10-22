import 'package:flutter_tts/flutter_tts.dart';

/// Minimal contract; M3 will add provider capabilities and cloud output types.
abstract interface class SpeechEngine {
  Future<void> speak(String text, {required String language, required double rate});
  Future<void> stop();
  Future<void> dispose();
}

class SystemSpeechEngine implements SpeechEngine {
  SystemSpeechEngine() {
    // Return from speak() only after the utterance completes.
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
  }) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async { await _tts.stop(); }

  @override
  Future<void> dispose() => stop();
}
