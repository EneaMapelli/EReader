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

  test('back one visit and forward one visit restore both directions', () {
    final h = ReaderChapterVisitHistory();
    record(h, from: 100, to: 200, number: 1);
    record(h, from: 200, to: 300, number: 2);
    final selected = h.latest!;
    final revision = h.revision;
    final departed = const ReaderChapterVisit(
      sourceOffset: 300, sectionTitle: 'Chapter 3',
      sectionNumber: 3, sectionCount: 5,
    );
    expect(h.consumeThrough(selected,
        expectedRevision: revision, departedFrom: departed), isTrue);
    expect(h.recent.map((visit) => visit.sourceOffset), [100]);
    expect(h.canGoForward, isTrue);
    expect(h.nextForward, same(departed));
    final fromBack = selected;
    expect(h.consumeForward(departed,
        expectedRevision: h.revision, departedFrom: fromBack), isTrue);
    expect(h.canGoForward, isFalse);
    expect(h.recent.map((visit) => visit.sourceOffset), [200, 100]);
  });

  test('older Back visit produces Forward in chronological order', () {
    final h = ReaderChapterVisitHistory();
    record(h, from: 100, to: 200, number: 1); // A
    record(h, from: 200, to: 300, number: 2); // B
    record(h, from: 300, to: 400, number: 3); // C
    final departed = const ReaderChapterVisit(
      sourceOffset: 400, sectionTitle: 'Chapter 4',
      sectionNumber: 4, sectionCount: 5,
    ); // D
    final oldest = h.recent.last;
    expect(h.consumeThrough(oldest, expectedRevision: h.revision,
        departedFrom: departed), isTrue);
    expect(h.canReturn, isFalse);
    expect(h.nextForward!.sourceOffset, 200,
        reason: 'Back from D to A must go forward first to B');
    expect(h.forwardLength, 3);

    var current = oldest;
    for (final expectedSource in [200, 300, 400]) {
      final next = h.nextForward!;
      expect(next.sourceOffset, expectedSource);
      expect(h.consumeForward(next, expectedRevision: h.revision,
          departedFrom: current), isTrue);
      current = next;
    }
    expect(h.canGoForward, isFalse);
    expect(h.recent.map((e) => e.sourceOffset), [300, 200, 100]);
  });

  test('new committed chapter switch branches and clears only Forward', () {
    final h = ReaderChapterVisitHistory();
    record(h, from: 100, to: 200);
    final first = h.latest!;
    final visited = const ReaderChapterVisit(
      sourceOffset: 200, sectionTitle: 'Chapter 2',
      sectionNumber: 2, sectionCount: 5,
    );
    expect(h.consumeThrough(first,
        expectedRevision: h.revision, departedFrom: visited), isTrue);
    expect(h.canGoForward, isTrue);
    final previousRevision = h.revision;
    expect(record(h, from: 100, to: 100), isFalse);
    expect(h.canGoForward, isTrue,
        reason: 'Canceled or no-op chapter selection cannot erase redo');
    expect(h.revision, previousRevision);
    expect(record(h, from: 100, to: 350), isTrue);
    expect(h.canGoForward, isFalse,
        reason: 'A new committed chapter branch replaces forward history');
    expect(h.canReturn, isTrue);
  });

  test('stale or forged forward operations never consume redo entries', () {
    final h = ReaderChapterVisitHistory();
    record(h, from: 100, to: 200);
    final selected = h.latest!;
    final departed = const ReaderChapterVisit(
      sourceOffset: 200, sectionTitle: 'Chapter 2',
      sectionNumber: 2, sectionCount: 5,
    );
    expect(h.consumeThrough(selected, expectedRevision: h.revision,
        departedFrom: departed), isTrue);
    final revision = h.revision;
    expect(h.consumeForward(departed, expectedRevision: revision - 1,
        departedFrom: selected), isFalse);
    expect(h.consumeForward(const ReaderChapterVisit(
      sourceOffset: 200, sectionTitle: 'Chapter 2',
      sectionNumber: 2, sectionCount: 5,
    ), expectedRevision: revision, departedFrom: selected), isFalse);
    expect(h.canGoForward, isTrue);
    h.clear();
    expect(h.canGoForward, isFalse);
    expect(h.consumeForward(departed, expectedRevision: revision,
        departedFrom: selected), isFalse);
  });

  test('Forward keeps OPF silent spine identities at shared source offsets',
      () {
    final h = ReaderChapterVisitHistory();
    record(h, from: 0, to: 0, number: 1,
        originSpine: 'illustration-a', destinationSpine: 'illustration-b');
    final before = h.latest!;
    final after = const ReaderChapterVisit(
      sourceOffset: 0, spineIdref: 'illustration-b',
      sectionTitle: 'Illustration B',
      sectionNumber: 2, sectionCount: 3,
    );
    expect(h.consumeThrough(before, expectedRevision: h.revision,
        departedFrom: after), isTrue);
    expect(h.nextForward!.spineIdref, 'illustration-b');
    expect(h.consumeForward(after, expectedRevision: h.revision,
        departedFrom: before), isTrue);
    expect(h.latest!.spineIdref, 'illustration-a');
  });

  test('Forward stack is bounded when older visits are skipped', () {
    final h = ReaderChapterVisitHistory(maxDepth: 3);
    for (var i = 0; i < 3; i++) {
      record(h, from: 10 + i * 10, to: 20 + i * 10);
    }
    final oldest = h.recent.last;
    final departed = const ReaderChapterVisit(
      sourceOffset: 60, sectionTitle: 'Chapter 5',
      sectionNumber: 5, sectionCount: 5,
    );
    expect(h.consumeThrough(oldest, expectedRevision: h.revision,
        departedFrom: departed), isTrue);
    expect(h.forwardLength, 3);
    expect(h.nextForward!.sourceOffset, 20);
    // Repeating Back/Forward is bounded by the same capacity.
    final next = h.nextForward!;
    expect(h.consumeForward(next, expectedRevision: h.revision,
        departedFrom: oldest), isTrue);
    expect(h.forwardLength, 2);
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
