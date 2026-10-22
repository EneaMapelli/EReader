import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/domain/speech_segment.dart';

void main() {
  test('splits sentences without changing spoken tokens', () {
    const input = ' Ciao mondo!  Come stai?\nBenissimo.';
    final chunks = segmentSpeech(input, maxChars: 24);
    expect(chunks.map((s) => s.text).toList(),
        ['Ciao mondo!', 'Come stai?', 'Benissimo.']);
    for (final chunk in chunks) {
      expect(input.substring(chunk.start, chunk.end), chunk.text);
    }
  });

  test('does not split utf16 surrogate pairs at a hard limit', () {
    final input = 'a' * 18 + '😀' + 'b' * 20;
    final chunks = segmentSpeech(input, maxChars: 19);
    expect(chunks.first.text, 'a' * 18);
    expect(chunks.skip(1).map((s) => s.text).join(), '😀' + 'b' * 20);
  });

  test('handles empty and whitespace-only books', () {
    expect(segmentSpeech(''), isEmpty);
    expect(segmentSpeech('   \n\t  '), isEmpty);
  });

  test('keeps decimal numbers in one utterance', () {
    const text = 'La cifra è 3.14 e non 3.15. Seconda frase.';
    final chunks = segmentSpeech(text, maxChars: 100);
    expect(chunks.map((s) => s.text).toList(),
        ['La cifra è 3.14 e non 3.15.', 'Seconda frase.']);
  });

  test('splits paragraphs at newlines even below the limit', () {
    final chunks = segmentSpeech('Paragrafo uno.\nParagrafo due.',
        maxChars: 120);
    expect(chunks.map((s) => s.text).toList(),
        ['Paragrafo uno.', 'Paragrafo due.']);
  });

  test('all spoken spans point to exact source substrings', () {
    const text = 'A  😀  parola lunga senza punteggiatura  Fine.';
    final chunks = segmentSpeech(text, maxChars: 18);
    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      expect(chunk.start, greaterThanOrEqualTo(0));
      expect(chunk.end, lessThanOrEqualTo(text.length));
      expect(chunk.start, lessThan(chunk.end));
      expect(text.substring(chunk.start, chunk.end), chunk.text);
    }
  });

  test('rejects too-small chunk sizes', () {
    expect(() => segmentSpeech('hello', maxChars: 2), throwsArgumentError);
  });
}
