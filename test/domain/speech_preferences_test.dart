import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
