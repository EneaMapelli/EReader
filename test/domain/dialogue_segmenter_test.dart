import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('separates quoted speech from the surrounding narration', () {
    const source = 'Anna disse: «Ciao!» e sorrise.';
    final chunks = splitQuotedSegments([
      SpeechSegment(0, source.length, source),
    ]);
    expect(chunks.map((s) => s.text).toList(),
        ['Anna disse:', '«Ciao!»', 'e sorrise.']);
    for (final item in chunks) {
      expect(source.substring(item.start, item.end), item.text);
    }
  });

  test('handles speech across chunks without losing source anchors', () {
    const source = 'Disse “Hello world” e uscì.';
    final base = segmentSpeech(source, maxChars: 18);
    final result = splitQuotedSegments(base);
    expect(result.any((s) => s.text.startsWith('“')), isTrue);
    expect(result.any((s) => s.text.endsWith('”')), isTrue);
    for (final segment in result) {
      expect(source.substring(segment.start, segment.end), segment.text);
    }
  });

  test('sentence-aware quoted chunks retain speaker turn boundaries', () {
    const source = 'Anna: «Ciao!» Poi rispose: “Va bene?” Fine.';
    final segmented = segmentSpeech(source, maxChars: 100);
    expect(segmented.map((s) => s.text).toList(), [
      'Anna: «Ciao!»', 'Poi rispose: “Va bene?”', 'Fine.',
    ]);
    final quotes = splitQuotedSegmentsWithRegions(segmented);
    final dialogue = quotes.where((s) => s.quoteGroup != null).toList();
    expect(dialogue.map((s) => s.segment.text), [
      '«Ciao!»', '“Va bene?”',
    ]);
    expect(dialogue.map((s) => s.quoteGroup), [0, 1]);
    expect(quotes.where((s) => s.quoteGroup == null)
        .map((s) => s.segment.text), ['Anna:', 'Poi rispose:', 'Fine.']);
    for (final part in quotes) {
      expect(source.substring(part.segment.start, part.segment.end),
          part.segment.text);
    }
  });

  test('supports ASCII double quotes without rewriting Unicode text', () {
    const source = 'A: "Hello 😀" then "bye".';
    final pieces = splitQuotedSegments([
      SpeechSegment(0, source.length, source),
    ]);
    expect(pieces.map((s) => s.text).toList(),
        ['A:', '"Hello 😀"', 'then', '"bye"', '.']);
  });

  test('unmatched open quote retains exact source instead of guessing',
      () {
    const source = 'He said “Hello';
    final pieces = splitQuotedSegments([
      SpeechSegment(0, source.length, source),
    ]);
    expect(pieces.map((s) => s.text).toList(),
        ['He said', '“Hello']);
    expect(source.substring(pieces.last.start, pieces.last.end),
        pieces.last.text);
  });
}
