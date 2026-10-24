import 'package:ereader/domain/cloud_speech_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled cloud consent is valid but grants no usage', () {
    const consent = CloudSpeechConsent(
      bookId: 'book', providerId: 'openai-speech',
      allowed: false, maxCharacters: 0, usedCharacters: 0,
    );
    expect(consent.remainingCharacters, 0);
    expect(() => consent.validate(), returnsNormally);
  });

  test('remaining budget never becomes negative', () {
    const consent = CloudSpeechConsent(
      bookId: 'book', providerId: 'openai-speech',
      allowed: true, maxCharacters: 100, usedCharacters: 87,
    );
    expect(consent.remainingCharacters, 13);
  });

  test('invalid totals are rejected', () {
    const consent = CloudSpeechConsent(
      bookId: 'book', providerId: 'openai-speech',
      allowed: true, maxCharacters: 100, usedCharacters: 101,
    );
    expect(() => consent.validate(), throwsFormatException);
  });
}
