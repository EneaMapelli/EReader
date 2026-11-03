import 'package:ereader/features/reader/epub_link_history.dart';
import 'package:ereader/features/reader/reader_progress_return_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chapter return and percentage return own distinct session state', () {
    final chapters = ReaderProgressReturnPoint();
    final percentages = ReaderProgressReturnPoint();
    final links = EpubLinkHistory();
    expect(chapters.canReturn, isFalse);

    expect(chapters.recordCommittedJump(
        fromOffset: 150, toOffset: 420, sourceLength: 1000), isTrue);
    expect(percentages.canReturn, isFalse,
        reason: 'A chapter change must not create a percentage history');
    expect(links.canReturn, isFalse,
        reason: 'A chapter change is not an internal EPUB link');

    expect(percentages.recordCommittedJump(
        fromOffset: 420, toOffset: 780, sourceLength: 1000), isTrue);
    links.push(780, 850);
    expect(chapters.origin, 150);
    expect(percentages.origin, 420);
    expect(links.lastLocation!.sourceOffset, 780);

    final chapterRevision = chapters.revision;
    expect(chapters.consumeIfOrigin(
        150, expectedRevision: chapterRevision), isTrue);
    expect(chapters.canReturn, isFalse);
    expect(percentages.canReturn, isTrue);
    expect(links.canReturn, isTrue);
  });

  test('silent illustrated OPF origin preserves its identity', () {
    final sections = ReaderProgressReturnPoint();
    expect(sections.recordCommittedJump(
      fromOffset: 0,
      toOffset: 0,
      sourceLength: 100,
      originSpineIdref: 'cover-b',
      destinationSpineIdref: 'cover-a',
    ), isTrue,
        reason: 'Two silent EPUB items can share a text offset');
    expect(sections.origin, 0);
    expect(sections.originSpineIdref, 'cover-b');

    // The exact same source and same silent item is not a real jump.
    final revision = sections.revision;
    expect(sections.recordCommittedJump(
      fromOffset: 0,
      toOffset: 0,
      sourceLength: 100,
      originSpineIdref: 'cover-b',
      destinationSpineIdref: 'cover-b',
    ), isFalse);
    expect(sections.revision, revision);
    expect(sections.originSpineIdref, 'cover-b');
    expect(sections.consumeIfOrigin(
        0, expectedRevision: revision), isTrue);
    expect(sections.canReturn, isFalse);
  });

  test('superseded or invalid chapter movements do not change return state', () {
    final sections = ReaderProgressReturnPoint();
    expect(sections.recordCommittedJump(
        fromOffset: 100, toOffset: 500,
        sourceLength: 1000), isTrue);
    final firstRevision = sections.revision;
    for (final invalid in [
      (-1, 500, 1000), (100, 1001, 1000), (100, 100, 1000),
      (100, 200, 0),
    ]) {
      expect(sections.recordCommittedJump(
        fromOffset: invalid.$1,
        toOffset: invalid.$2,
        sourceLength: invalid.$3,
      ), isFalse);
      expect(sections.origin, 100);
      expect(sections.revision, firstRevision);
    }
    expect(sections.recordCommittedJump(
        fromOffset: 500, toOffset: 800,
        sourceLength: 1000), isTrue);
    expect(sections.consumeIfOrigin(100,
        expectedRevision: firstRevision), isFalse);
    expect(sections.origin, 500);
    expect(sections.consumeIfOrigin(500,
        expectedRevision: firstRevision), isFalse,
        reason: 'Old completed returns never eat a newer chapter history');
    expect(sections.consumeIfOrigin(500,
        expectedRevision: sections.revision), isTrue);
  });

  test('reloading book clears chapter history without touching percent', () {
    final chapter = ReaderProgressReturnPoint();
    final percent = ReaderProgressReturnPoint();
    chapter.recordCommittedJump(
        fromOffset: 11, toOffset: 99, sourceLength: 100);
    percent.recordCommittedJump(
        fromOffset: 30, toOffset: 60, sourceLength: 100);
    chapter.clear();
    expect(chapter.canReturn, isFalse);
    expect(percent.canReturn, isTrue,
        reason: 'Clearing one session history does not mutate another');
  });
}
