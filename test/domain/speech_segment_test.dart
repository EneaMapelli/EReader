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

  test('rejects too-small chunk sizes', () {
    expect(() => segmentSpeech('hello', maxChars: 2), throwsArgumentError);
  });
}
