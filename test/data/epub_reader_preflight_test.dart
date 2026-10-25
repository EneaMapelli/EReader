import 'dart:io';

import 'package:archive/archive.dart';
import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/data/epub_reader_preflight.dart';
import 'package:ereader/data/epub_progress_recovery.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('ereader-preflight-');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  Future<String> writeEpub({
    String first = '<html><body><h2>Chapter One</h2>'
        '<p>She whispered «Hello 📖!» and waited.</p>'
        '<p>A second paragraph with words.</p></body></html>',
    String second = '<html><body><p>Another chapter starts.</p>'
        '<p>Its next paragraph finishes here.</p></body></html>',
  }) async {
    final archive = Archive()
      ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..add(ArchiveFile.string('META-INF/container.xml',
          '<container><rootfiles>'
          '<rootfile full-path="OPS/content.opf"/>'
          '</rootfiles></container>'))
      ..add(ArchiveFile.string('OPS/content.opf',
          '<package><metadata><title>Preflight Test</title></metadata>'
          '<manifest>'
          '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="a"/>'
          '<itemref idref="b"/></spine></package>'))
      ..add(ArchiveFile.string('OPS/a.xhtml', first))
      ..add(ArchiveFile.string('OPS/b.xhtml', second));
    final file = File(p.join(temporary.path, 'preflight.epub'));
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return file.path;
  }

  test('worker preflight produces same source, quotes and hard boundaries',
      () async {
    final path = await writeEpub();
    final worker = await prepareEpubReader(path);
    final extracted = await PrototypeDocumentDecoder().read(
        BookRecord(id: 'preflight', title: 'Book',
          localPath: path, format: BookFormat.epub,
          importedAt: DateTime.utc(2026, 10, 25)));
    expect(worker.document.text, extracted.text);
    expect(worker.document.title, extracted.title);
    expect(worker.document.epubSpineRanges.map((r) => r.idref),
        extracted.epubSpineRanges.map((r) => r.idref));
    final directQuote = splitQuotedSegmentsWithRegions(
      segmentEpubSpine(extracted),
      resetAt: [
        for (final range in extracted.epubSpineRanges.skip(1)) range.start,
      ],
    );
    expect(worker.quoted.length, directQuote.length);
    for (var i = 0; i < directQuote.length; i++) {
      final a = worker.quoted[i], b = directQuote[i];
      expect((a.segment.start, a.segment.end, a.segment.text, a.quoteGroup),
          (b.segment.start, b.segment.end, b.segment.text, b.quoteGroup));
      expect(extracted.text.substring(a.segment.start, a.segment.end),
          a.segment.text);
    }
    expect(worker.hardBoundaries, epubParagraphHardBoundaries(extracted));
    expect(worker.quoted.any((q) => q.quoteGroup != null), isTrue);
  });

  test('background worker handles many paragraphs without altering source',
      () async {
    final paragraphs = List.generate(
        1500, (i) => '<p>Paragraph $i. Another sentence.</p>').join();
    final path = await writeEpub(
      first: '<html><body>$paragraphs</body></html>',
      second: '<html><body><p>The end 📖.</p></body></html>',
    );
    final preflight = await prepareEpubReader(path);
    expect(preflight.document.epubSpineRanges.length, 2);
    expect(preflight.quoted.length, greaterThan(1500));
    expect(preflight.hardBoundaries, isNotEmpty);
    final ranges = preflight.document.epubSpineRanges;
    expect(preflight.hardBoundaries, contains(ranges.last.start));
    for (final q in preflight.quoted) {
      final segment = q.segment;
      expect(preflight.document.text.substring(segment.start, segment.end),
          segment.text);
    }
  });

  test('worker verifies an exact v2 checkpoint using its own EPUB source',
      () async {
    final path = await writeEpub();
    final first = await prepareEpubReader(path);
    final offset = first.document.text.indexOf('second paragraph');
    expect(offset, greaterThan(0));
    final anchor = first.document.anchorAt(BookFormat.epub, offset);
    final withResume = await prepareEpubReader(
      path, resume: EpubResumeRequest(anchor: anchor, legacyOffset: 0),
    );
    expect(withResume.resumeRecovery?.status,
        EpubProgressRecoveryStatus.exact);
    expect(withResume.resumeRecovery?.offset, offset);
    expect(withResume.resumeRecovery?.shouldPersist, isFalse);
    expect(withResume.timings.resumeRecoveryUs, isNotNull);
    expect(withResume.timings.resumeRecoveryUs, greaterThanOrEqualTo(0));
    expect(withResume.timings.toJson()['resumeRecoveryUs'], isNotNull);
    expect(first.resumeRecovery, isNull);
    expect(first.timings.resumeRecoveryUs, isNull);
  });

  test('worker relocates a unique changed-chapter anchor, never a stale ID',
      () async {
    final path = await writeEpub(
      first: '<html><body><p>The morning starts. '
          'A unique passage continues.</p></body></html>',
    );
    final original = await prepareEpubReader(path);
    final oldOffset = original.document.text.indexOf('unique passage');
    expect(oldOffset, greaterThan(0));
    final anchor = original.document.anchorAt(BookFormat.epub, oldOffset);
    await writeEpub(
      first: '<html><body><p>The morning starts.</p>'
          '<p>A unique passage continues.</p></body></html>',
    );
    final changed = await prepareEpubReader(
      path, resume: EpubResumeRequest(
        anchor: anchor, legacyOffset: oldOffset,
      ),
    );
    final relocatedOffset = changed.document.text.indexOf('unique passage');
    expect(relocatedOffset, greaterThan(oldOffset));
    expect(changed.resumeRecovery?.status,
        EpubProgressRecoveryStatus.relocated);
    expect(changed.resumeRecovery?.offset, relocatedOffset);
    expect(changed.resumeRecovery?.shouldPersist, isTrue);
    final unknownSection = await prepareEpubReader(
      path, resume: const EpubResumeRequest(
        anchor: ReadingAnchor(
          kind: AnchorKind.epubSpine, sourceId: 'removed',
          localOffset: 0,
        ),
        legacyOffset: 500,
      ),
    );
    expect(unknownSection.resumeRecovery?.status,
        EpubProgressRecoveryStatus.needsReview);
    expect(unknownSection.resumeRecovery?.shouldPersist, isFalse);
    expect(unknownSection.resumeRecovery?.offset, 0);
  });

  test('worker handles offset-only legacy checkpoints without rewrites',
      () async {
    final path = await writeEpub();
    final result = await prepareEpubReader(
      path, resume: const EpubResumeRequest(
        anchor: null, legacyOffset: 9,
      ),
    );
    expect(result.resumeRecovery?.status,
        EpubProgressRecoveryStatus.legacyUnverified);
    expect(result.resumeRecovery?.offset, 9);
    expect(result.resumeRecovery?.shouldPersist, isFalse);
  });

  test('preflight timing report records nonnegative stages and safe counts',
      () async {
    final path = await writeEpub();
    final prepared = await prepareEpubReader(path);
    final metrics = prepared.timings;
    final values = metrics.toJson();
    expect(values.values.every((value) => value >= 0), isTrue);
    expect(metrics.workerTotalUs, greaterThanOrEqualTo(
        metrics.archiveReadUs + metrics.xhtmlExtractionUs +
        metrics.speechSegmentationUs + metrics.quoteGroupingUs +
        metrics.paragraphBoundariesUs));
    expect(metrics.compressedBytes, greaterThan(0));
    expect(metrics.spineItems, 2);
    expect(metrics.sourceCodeUnits, prepared.document.text.length);
    expect(metrics.speechSegments, greaterThan(0));
    expect(values.keys, isNot(contains('localPath')));
    expect(values.keys, isNot(contains('bookText')));
    expect(values.keys, isNot(contains('apiKey')));
  });

  test('cancel while worker spawn is in flight settles future exactly once',
      () async {
    final path = await writeEpub();
    final task = startEpubReaderPreflight(path);
    final cancelled = expectLater(
        task.result, throwsA(isA<EpubPreflightCancelled>()));
    task.cancel();
    task.cancel();
    expect(task.isFinished, isTrue);
    await cancelled;
    // The immediately cancelled spawn may still complete asynchronously;
    // its eventual isolate must be killed instead of leaking CPU work.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final fresh = await prepareEpubReader(path);
    expect(fresh.document.text, contains('Chapter One'));
  });

  test('independent preflights cannot cancel each other', () async {
    final path = await writeEpub();
    final cancelled = startEpubReaderPreflight(path);
    final survivor = startEpubReaderPreflight(path);
    final outcome = expectLater(cancelled.result,
        throwsA(isA<EpubPreflightCancelled>()));
    cancelled.cancel();
    await outcome;
    final prepared = await survivor.result;
    expect(prepared.document.epubSpineRanges.length, 2);
    expect(survivor.isFinished, isTrue);
  });

  test('cancelled sibling never interrupts concurrent valid EPUB workers',
      () async {
    final paragraphs = List<String>.generate(
        400, (i) => '<p>Section $i has a safe sentence.</p>').join();
    final path = await writeEpub(
      first: '<html><body>$paragraphs</body></html>',
    );
    final tasks = [
      for (var i = 0; i < 6; i++) startEpubReaderPreflight(path),
    ];
    final cancelled = <Future<void>>[];
    for (final index in [1, 3, 5]) {
      cancelled.add(expectLater(tasks[index].result,
          throwsA(isA<EpubPreflightCancelled>())));
      tasks[index].cancel();
    }
    final surviving = await Future.wait([
      for (final index in [0, 2, 4]) tasks[index].result,
    ]);
    await Future.wait(cancelled);
    for (final prepared in surviving) {
      expect(prepared.document.text, contains('Section 399'));
      expect(prepared.document.epubSpineRanges, hasLength(2));
      expect(prepared.quoted, isNotEmpty);
    }
    expect(tasks.every((task) => task.isFinished), isTrue);
  });

  test('multiple worker exit notifications do not mask valid results',
      () async {
    final path = await writeEpub();
    // Launch several isolated preflights at the same time, each owning
    // a distinct ReceivePort and its own final Isolate.exit payload.
    // No exit notification may be mistaken for a missing response.
    final tasks = [
      for (var i = 0; i < 4; i++) startEpubReaderPreflight(path),
    ];
    final outcomes = await Future.wait(
      [for (final task in tasks) task.result],
    );
    expect(outcomes.length, 4);
    for (var i = 0; i < tasks.length; i++) {
      expect(tasks[i].isFinished, isTrue);
      expect(outcomes[i].document.text, contains('Chapter One'));
      expect(outcomes[i].quoted, isNotEmpty);
    }
  });

  test('worker fails closed on missing or invalid input', () async {
    final missing = p.join(temporary.path, 'missing.epub');
    await expectLater(prepareEpubReader(missing),
        throwsA(isA<FileSystemException>()));
    final bad = File(p.join(temporary.path, 'corrupt.epub'));
    await bad.writeAsString('not a valid ZIP');
    await expectLater(prepareEpubReader(bad.path), throwsFormatException);
  });
}
