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
    const source = 'Narrated.\n\nA silent 📖 caption.\n\nNarrated again.';
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
    expect(literal.map((hit) => hit.start).toList(), [0, 13]);
    expect(findSourceTextMatches(source, '[note]').single.start, 18);
    expect(findSourceTextMatches(source, 'missing'), isEmpty);
  });

  test('source match offsets survive emoji and excerpt boundaries', () {
    const source = '📚before needle📖 after📚';
    final matches = findSourceTextMatches(source, 'NEEDLE', contextChars: 3);
    expect(matches, hasLength(1));
    final match = matches.single;
    expect(source.substring(match.start, match.end), 'needle');
    expect(match.start, source.indexOf('needle'));
    expect(match.excerpt, 're needle📖');
    final aroundEmoji = findSourceTextMatches(source, 'after', contextChars: 1);
    expect(aroundEmoji.single.excerpt, 'after📚');
  });

  test('excerpt normalizes newlines but keeps source match location', () {
    const source = 'Alpha.\n\nBeta is here.';
    final hits = findSourceTextMatches(source, 'Beta');
    expect(hits.single.start, source.indexOf('Beta'));
    expect(hits.single.excerpt, 'Alpha. Beta is here.');
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

  test('full-source results start near current position and wrap once', () {
    const source = 'echo A.\n\necho 📖 B.\n\necho C.';
    final later = source.lastIndexOf('echo');
    final hits = findSourceTextMatches(source, 'ECHO',
        startOffset: later, maxResults: 2);
    expect(hits.map((hit) => hit.start).toList(), [later, 0]);
    expect(source.substring(hits.first.start, hits.first.end), 'echo');

    final all = findSourceTextMatches(source, 'echo',
        startOffset: source.length);
    expect(all.map((hit) => hit.start).toList(),
        [0, source.indexOf('echo', 1), later]);
    expect(findSourceTextMatches(source, 'echo', startOffset: 0)
        .map((hit) => hit.start).toList(), all.map((hit) => hit.start).toList());
    expect(() => findSourceTextMatches(source, 'echo', startOffset: -1),
        throwsArgumentError);
    expect(() => findSourceTextMatches(source, 'echo',
        startOffset: source.length + 1), throwsArgumentError);
  });

  test('a cursor inside an emoji never splits source or duplicates hits', () {
    const source = 'needle 📖needle then needle';
    final lowSurrogate = source.indexOf('📖') + 1;
    final hits = findSourceTextMatches(source, 'needle',
        startOffset: lowSurrogate, maxResults: 3, contextChars: 1);
    expect(hits.map((hit) => hit.start).toList(), [
      source.indexOf('needle', source.indexOf('📖')),
      source.lastIndexOf('needle'),
      0,
    ]);
    for (final hit in hits) {
      expect(source.substring(hit.start, hit.end), 'needle');
    }
  });


  test('source search paginates beyond the first 100 without repeats', () {
    final source = List<String>.generate(
        235, (i) => 'hit$i').join(' ');
    final cursor = source.indexOf('hit198');
    final page1 = findSourceTextMatches(source, 'hit',
        startOffset: cursor, maxResults: 100);
    final page2 = findSourceTextMatches(source, 'hit',
        startOffset: cursor, skipResults: 100, maxResults: 100);
    final page3 = findSourceTextMatches(source, 'hit',
        startOffset: cursor, skipResults: 200, maxResults: 100);
    expect([page1.length, page2.length, page3.length], [100, 100, 35]);
    expect(page1.first.start, cursor);
    expect(page2.first.start, source.indexOf('hit63'));
    expect(page3.last.start, source.indexOf('hit197'));
    final all = [...page1, ...page2, ...page3];
    expect(all.map((match) => match.start).toSet().length, 235);
    expect(findSourceTextMatches(source, 'hit',
        startOffset: cursor, skipResults: 235), isEmpty);
    for (final hit in all) {
      expect(source.substring(hit.start, hit.end), 'hit');
    }
  });

  test('source page skipping respects UTF-16 offsets near emoji', () {
    const source = '📖 echo one, echo two, 📚 echo three';
    final emojiMiddle = source.indexOf('📚') + 1;
    final page = findSourceTextMatches(source, 'echo',
        startOffset: emojiMiddle, skipResults: 1, maxResults: 1,
        contextChars: 1);
    expect(page.single.start, source.indexOf('echo'));
    expect(page.single.excerpt, isNot(contains('\uFFFD')));
    expect(() => findSourceTextMatches(source, 'echo', skipResults: -1),
        throwsArgumentError);
  });

  test('search bounds number of results and ignores empty queries', () {
    expect(findMatchingSegments(segments, 'prima', maxResults: 1), [0]);
    expect(findMatchingSegments(segments, '   '), isEmpty);
    expect(() => findMatchingSegments(segments, 'a', maxResults: 0),
        throwsArgumentError);
  });
}
