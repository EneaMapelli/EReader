import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {

  test('metadata language defaults normalize common language and region', () {
    expect(speechLocaleForBookMetadata('en'), 'en-US');
    expect(speechLocaleForBookMetadata(' IT '), 'it-IT');
    expect(speechLocaleForBookMetadata('fr_fr'), 'fr-FR');
    expect(speechLocaleForBookMetadata('pt-BR'), 'pt-BR');
    expect(speechLocaleForBookMetadata('zh-TW'), 'zh-TW');
    expect(speechLocaleForBookMetadata('en-001'), 'en-001');
  });

  test('malformed or unsupported book languages do not override TTS', () {
    for (final tag in <String?>[
      null, '', '  ', 'xx', 'english', 'en-US-extra',
      '../en', 'en_US_other', 'e', '123', 'en-1234',
    ]) {
      expect(speechLocaleForBookMetadata(tag), isNull,
          reason: 'Book locale: $tag');
    }
    expect(const SpeechPreferences().language, 'it-IT');
  });
  test('round-trip persistent voice settings', () {
    const original = SpeechPreferences(
      providerId: 'system',
      language: 'en-US',
      rate: 0.7,
      pitch: 1.2,
      voiceName: 'Desktop Voice',
      voiceLocale: 'en-US',
    );
    final restored = SpeechPreferences.fromJson(original.toJson());
    expect(restored.providerId, 'system');
    expect(restored.voiceName, 'Desktop Voice');
    expect(restored.rate, 0.7);
    expect(restored.pitch, 1.2);
  });

  test('model selection persists while older settings receive a default',
      () {
    const prefs = SpeechPreferences(
      providerId: 'openai-speech',
      modelId: 'gpt-4o-mini-tts-2025-12-15',
      voiceName: 'marin',
      voiceLocale: 'multi',
    );
    expect(SpeechPreferences.fromJson(prefs.toJson()).modelId,
        'gpt-4o-mini-tts-2025-12-15');
    final old = Map<String, dynamic>.from(prefs.toJson())
      ..remove('modelId');
    expect(SpeechPreferences.fromJson(old).modelId, 'gpt-4o-mini-tts');
  });

  test('dialogue pause round-trips with provider and global voice settings',
      () {
    const prefs = SpeechPreferences(
      providerId: 'system-native',
      language: 'it-IT',
      dialogueTurnPauseMs: 350,
    );
    final restored = SpeechPreferences.fromJson(prefs.toJson());
    expect(restored.dialogueTurnPauseMs, 350);
    expect(restored.providerId, 'system-native');
    expect(restored.copyWith(rate: 0.7).dialogueTurnPauseMs, 350);
    expect(restored.copyWith(dialogueTurnPauseMs: 0).dialogueTurnPauseMs, 0);
    expect(restored.copyWith(providerId: 'openai-speech')
        .dialogueTurnPauseMs, 350,
        reason: 'Free-voice preference survives switching cloud providers');
  });

  test('older stored JSON defaults to the previously fixed 110ms pause',
      () {
    final legacy = Map<String, dynamic>.from(
        const SpeechPreferences().toJson())
      ..remove('dialogueTurnPauseMs');
    expect(SpeechPreferences.fromJson(legacy).dialogueTurnPauseMs, 110);
    expect(const SpeechPreferences().dialogueTurnPauseMs, 110);
  });

  test('rejects malformed or excessive dialogue pause durations', () {
    for (final duration in [-1, 2001]) {
      expect(() => SpeechPreferences(
        dialogueTurnPauseMs: duration,
      ).validate(), throwsFormatException);
    }
    for (final value in ['110', 110.0, true, []]) {
      expect(() => SpeechPreferences.fromJson({
        ...const SpeechPreferences().toJson(),
        'dialogueTurnPauseMs': value,
      }), throwsFormatException);
    }
  });

  test('rejects invalid or non-finite settings', () {
    expect(
      () => const SpeechPreferences(rate: 5).validate(),
      throwsFormatException,
    );
    expect(
      () => const SpeechPreferences(pitch: double.nan).validate(),
      throwsFormatException,
    );
    expect(
      () => SpeechPreferences.fromJson({
        ...const SpeechPreferences().toJson(), 'version': 2,
      }),
      throwsFormatException,
    );
  });
}
