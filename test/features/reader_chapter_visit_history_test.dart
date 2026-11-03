import 'package:ereader/features/reader/epub_link_history.dart';
import 'package:ereader/features/reader/reader_chapter_visit_history.dart';
import 'package:ereader/features/reader/reader_progress_return_point.dart';
import 'package:flutter_test/flutter_test.dart';

bool record(ReaderChapterVisitHistory history, {
  required int from,
  required int to,
  String title = 'Chapter',
  int number = 2,
  int count = 5,
  String? originSpine,
  String? destinationSpine,
}) => history.recordCommittedJump(
  fromOffset: from, toOffset: to, sourceLength: 2000,
  sectionTitle: title, sectionNumber: number, sectionCount: count,
  originSpineIdref: originSpine, destinationSpineIdref: destinationSpine,
);

void main() {
  test('chapter visits are newest-first, immutable, and preserve metadata', () {
    final history = ReaderChapterVisitHistory();
    expect(history.canReturn, isFalse);
    expect(history.length, 0);
    expect(history.latest, isNull);
    expect(record(history, from: 150, to: 300,
        title: 'Introduction', number: 1), isTrue);
    final first = history.latest!;
    expect(first.sourceOffset, 150);
    expect(first.sectionTitle, 'Introduction');
    expect(first.sectionNumber, 1);
    expect(first.sectionCount, 5);
    expect(record(history, from: 300, to: 700,
        title: 'Part Two', number: 2), isTrue);
    expect(history.recent.map((e) => e.sourceOffset), [300, 150]);
    expect(history.latest!.sectionTitle, 'Part Two');
    expect(() => history.recent.clear(), throwsUnsupportedError);
  });

  test('selecting older visit removes selected and newer, retains older', () {
    final history = ReaderChapterVisitHistory();
    record(history, from: 100, to: 200, number: 1);
    record(history, from: 200, to: 300, number: 2);
    record(history, from: 300, to: 400, number: 3);
    record(history, from: 400, to: 500, number: 4);
    final revision = history.revision;
    final older = history.recent[2]; // source 200
    expect(older.sourceOffset, 200);
    expect(history.consumeThrough(older, expectedRevision: revision), isTrue);
    expect(history.recent.map((e) => e.sourceOffset), [100]);
    expect(history.canReturn, isTrue);
    expect(history.consumeThrough(older,
        expectedRevision: history.revision), isFalse);
    final latest = history.latest!;
    expect(history.consumeThrough(latest,
        expectedRevision: history.revision), isTrue);
    expect(history.canReturn, isFalse);
  });

  test('old or forged selections cannot consume an updated history', () {
    final history = ReaderChapterVisitHistory();
    record(history, from: 100, to: 300);
    final prior = history.latest!;
    final staleRevision = history.revision;
    record(history, from: 300, to: 700);
    expect(history.consumeThrough(prior,
        expectedRevision: staleRevision), isFalse);
    expect(history.length, 2);
    expect(history.consumeThrough(const ReaderChapterVisit(
      sourceOffset: 100, sectionTitle: 'Chapter',
      sectionNumber: 2, sectionCount: 5,
    ), expectedRevision: history.revision), isFalse,
        reason: 'Equal locations from a different sheet are not visit IDs');
    expect(history.contains(prior), isTrue);
  });

  test('full 20 entry history evicts oldest without affecting newest', () {
    final history = ReaderChapterVisitHistory();
    for (var i = 0; i < 37; i++) {
      expect(record(history,
          from: i * 10, to: i * 10 + 5), isTrue);
    }
    expect(history.length, 20);
    expect(history.recent.first.sourceOffset, 360);
    expect(history.recent.last.sourceOffset, 170);
    expect(history.recent.map((e) => e.sourceOffset).toSet().length, 20);
    final earlierSnapshot = history.recent;
    record(history, from: 500, to: 550);
    expect(earlierSnapshot.first.sourceOffset, 360,
        reason: 'An open sheet owns its read-only snapshot');
    expect(history.length, 20);
    expect(history.contains(earlierSnapshot.last), isFalse);
  });

  test('invalid, no-op and malformed source visits do not alter history', () {
    final history = ReaderChapterVisitHistory();
    record(history, from: 200, to: 500);
    final revision = history.revision;
    final original = history.latest!;
    final invalid = [
      (-1, 500, 1000, 1, 5, 'Chapter'),
      (200, 1001, 1000, 1, 5, 'Chapter'),
      (200, 500, 0, 1, 5, 'Chapter'),
      (200, 200, 1000, 1, 5, 'Chapter'),
      (200, 500, 1000, 0, 5, 'Chapter'),
      (200, 500, 1000, 6, 5, 'Chapter'),
      (200, 500, 1000, 1, 0, 'Chapter'),
      (200, 500, 1000, 1, 5, '  '),
    ];
    for (final value in invalid) {
      expect(history.recordCommittedJump(
        fromOffset: value.$1, toOffset: value.$2,
        sourceLength: value.$3, sectionNumber: value.$4,
        sectionCount: value.$5, sectionTitle: value.$6,
      ), isFalse);
    }
    expect(record(history, from: 200, to: 500,
        originSpine: ''), isFalse);
    expect(record(history, from: 200, to: 500,
        destinationSpine: ''), isFalse);
    expect(history.revision, revision);
    expect(history.latest, same(original));
  });

  test('same-offset silent illustrated covers remain separate visits', () {
    final history = ReaderChapterVisitHistory();
    expect(record(history, from: 0, to: 0, number: 1,
        originSpine: 'cover-b', destinationSpine: 'cover-a'), isTrue);
    expect(history.latest!.sourceOffset, 0);
    expect(history.latest!.spineIdref, 'cover-b');
    expect(record(history, from: 0, to: 0,
        originSpine: 'cover-b', destinationSpine: 'cover-b'), isFalse);
    final original = history.latest!;
    expect(history.contains(original), isTrue);
    expect(history.consumeThrough(original,
        expectedRevision: history.revision), isTrue);
    expect(history.canReturn, isFalse);
  });

  test('chapter history never consumes percentage or EPUB link returns', () {
    final history = ReaderChapterVisitHistory();
    final percent = ReaderProgressReturnPoint();
    final links = EpubLinkHistory();
    record(history, from: 100, to: 400);
    record(history, from: 400, to: 700);
    percent.recordCommittedJump(
        fromOffset: 700, toOffset: 900, sourceLength: 2000);
    links.push(900, 1100);
    final older = history.recent.last;
    expect(history.consumeThrough(older,
        expectedRevision: history.revision), isTrue);
    expect(history.canReturn, isFalse);
    expect(percent.origin, 700);
    expect(links.last, 900);
    record(history, from: 900, to: 1500);
    history.clear();
    expect(history.canReturn, isFalse);
    expect(percent.canReturn, isTrue);
    expect(links.canReturn, isTrue);
  });

  test('tiny maximum history keeps only configured number of visits', () {
    final history = ReaderChapterVisitHistory(maxDepth: 1);
    for (var i = 0; i < 10; i++) {
      expect(record(history, from: i, to: i + 100), isTrue);
    }
    expect(history.length, 1);
    expect(history.latest!.sourceOffset, 9);
  });
}
