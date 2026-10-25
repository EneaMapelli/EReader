import 'package:ereader/domain/book_search.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const segments = [
    SpeechSegment(0, 12, 'Prima frase.'),
    SpeechSegment(13, 25, 'Another line'),
    SpeechSegment(26, 40, 'Prima ancora.'),
  ];

  test('search ignores case and returns stable segment indices', () {
    expect(findMatchingSegments(segments, 'PRIMA'), [0, 2]);
    expect(findMatchingSegments(segments, 'line'), [1]);
    expect(findMatchingSegments(segments, 'absent'), isEmpty);
  });

  test('source search finds unspoken caption and keeps exact UTF-16 offset',
      () {
    const source = 'Narrated.\\n\\nA silent 📖 caption.\\n\\nNarrated again.';
    final matches = findSourceTextMatches(source, 'CAPTION');
    expect(matches.length, 1);
    expect(matches.single.start, source.indexOf('caption'));
    expect(source.substring(matches.single.start, matches.single.end),
        'caption');
    expect(matches.single.excerpt, contains('📖 caption'));
    expect(matches.single.excerpt, contains('Narrated'));
  });

  test('literal source queries safely match regex punctuation and quote text',
      () {
    const source = 'a.b? (alpha) a.b? [note]';
    final literal = findSourceTextMatches(source, 'a.b?');
    expect(literal.map((hit) => hit.start).toList(), [0, 15]);
    expect(findSourceTextMatches(source, '[note]').single.start, 20);
    expect(findSourceTextMatches(source, 'missing'), isEmpty);
  });

  test('source match offsets survive emoji and excerpt boundaries', () {
    const source = '📚before needle📖 after📚';
    final matches = findSourceTextMatches(source, 'NEEDLE', contextChars: 3);
    expect(matches, hasLength(1));
    final match = matches.single;
    expect(source.substring(match.start, match.end), 'needle');
    expect(match.start, source.indexOf('needle'));
    expect(match.excerpt, 're needle📖 a');
    final aroundEmoji = findSourceTextMatches(source, 'after', contextChars: 1);
    expect(aroundEmoji.single.excerpt, '📖 after📚');
  });

  test('source search is bounded and never indexes a hidden network service',
      () {
    final source = List.filled(12000, 'echo ').join();
    final hits = findSourceTextMatches(source, 'ECHO', maxResults: 7);
    expect(hits, hasLength(7));
    expect(hits.map((hit) => hit.start).toList(),
        [0, 5, 10, 15, 20, 25, 30]);
    expect(findSourceTextMatches(source, '   '), isEmpty);
    expect(findSourceTextMatches(source, 'a' * 121), isEmpty);
    expect(() => findSourceTextMatches(source, 'echo', maxResults: 0),
        throwsArgumentError);
    expect(() => findSourceTextMatches(source, 'echo', contextChars: 513),
        throwsArgumentError);
  });

  test('search bounds number of results and ignores empty queries', () {
    expect(findMatchingSegments(segments, 'prima', maxResults: 1), [0]);
    expect(findMatchingSegments(segments, '   '), isEmpty);
    expect(() => findMatchingSegments(segments, 'a', maxResults: 0),
        throwsArgumentError);
  });
}
