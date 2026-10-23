import 'package:flutter_tts/flutter_tts.dart';

class SpeechVoice {
  const SpeechVoice({required this.name, required this.locale});
  final String name;
  final String locale;
  String get key => '$name@@$locale';
  @override
  String toString() => '$name ($locale)';
}

/// Minimal speech abstraction; cloud providers in M3 expose dynamic capabilities.
abstract interface class SpeechEngine {
  Future<List<SpeechVoice>> listVoices();
  Future<void> chooseVoice(SpeechVoice voice);
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  });
  Future<void> stop();
  Future<void> dispose();
}

/// Optional ability to synthesize ONE future cloud chunk without playing it.
/// This is never called for a native OS voice. Preparing a cache miss may
/// transmit book text and debit the user's existing cloud-character budget.
/// The caller must obtain a separate, explicit session opt-in first.
abstract interface class AheadOfTimeSpeechEngine {
  Future<void> prepareSpeech(
    String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  });
}

class SystemSpeechEngine implements SpeechEngine {
  SystemSpeechEngine();

  final FlutterTts _tts = FlutterTts();
  SpeechVoice? _selectedVoice;
  bool _completionConfigured = false;

  Future<void> _prepare() async {
    if (!_completionConfigured) {
      await _tts.awaitSpeakCompletion(true);
      _completionConfigured = true;
    }
  }

  @override
  Future<List<SpeechVoice>> listVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    final result = <SpeechVoice>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString();
      final locale = item['locale']?.toString();
      if (name == null || name.isEmpty || locale == null || locale.isEmpty) {
        continue;
      }
      result.add(SpeechVoice(name: name, locale: locale));
    }
    result.sort((a, b) => a.toString().compareTo(b.toString()));
    return result;
  }

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    _selectedVoice = voice;
    await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    await _prepare();
    await _tts.setLanguage(language);
    if (_selectedVoice != null) {
      await _tts.setVoice({
        'name': _selectedVoice!.name,
        'locale': _selectedVoice!.locale,
      });
    }
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> dispose() => stop();
}
