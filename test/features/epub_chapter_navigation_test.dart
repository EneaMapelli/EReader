import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chapters retain accurate UTF-16 offsets and source spine IDs', () {
    const a = 'First chapter. 📖';
    const b = 'Second chapter! Part two.';
    final source = '$a\n\n$b';
    final bStart = a.length + 2;
    final document = DocumentContent(
      title: 'Book', text: source,
      epubSpineRanges: [
        EpubSpineRange(
          idref: 'intro', href: 'Text/intro.xhtml',
          start: 0, end: a.length, title: 'Opening'),
        EpubSpineRange(
          idref: 'main', href: 'Text/main.xhtml',
          start: bStart, end: source.length, title: 'Main Chapter'),
      ],
    );
    final chunks = segmentEpubSpine(document);
    expect(chunks.length, greaterThanOrEqualTo(2));
    expect(chunks.every((segment) =>
        source.substring(segment.start, segment.end) == segment.text), isTrue);
    expect(chunks.where((segment) => segment.start < bStart)
        .every((segment) => segment.end <= a.length), isTrue);
    expect(chunks.where((segment) => segment.start >= bStart).isNotEmpty, isTrue);

    final chapters = buildEpubChapters(document, chunks);
    expect(chapters.length, 2);
    expect(chapters.map((chapter) => chapter.title).toList(),
        ['Opening', 'Main Chapter']);
    expect(chunks[chapters[1].segmentIndex].start, bStart);
    expect(chapterIndexForOffset(chapters, 0), 0);
    expect(chapterIndexForOffset(chapters, bStart), 1);
    expect(chapterIndexForOffset(chapters, source.length), 1);

    final anchor = document.anchorAt(
        BookFormat.epub, chunks[chapters[1].segmentIndex].start);
    expect(anchor.kind, AnchorKind.epubSpine);
    expect(anchor.sourceId, 'main');
    expect(anchor.localOffset, 0);
    expect(document.offsetOf(
      const ReadingAnchor(
        kind: AnchorKind.epubSpine, sourceId: 'main', localOffset: 0,
      )), bStart);
  });

  test('quote coalescing never merges across hard EPUB spine boundary', () {
    const a = '«A long quotation from chapter one';
    const b = ' continues here and ends in chapter two»';
    final source = '$a\n\n$b';
    final bStart = a.length + 2;
    final document = DocumentContent(
      title: 'Book', text: source,
      epubSpineRanges: [
        EpubSpineRange(
          idref: 'one', href: 'one.xhtml',
          start: 0, end: a.length, title: 'One'),
        EpubSpineRange(
          idref: 'two', href: 'two.xhtml',
          start: bStart, end: source.length, title: 'Two'),
      ],
    );
    final originals = segmentEpubSpine(document);
    final quotes = splitQuotedSegmentsWithRegions(originals);
    final merged = coalesceQuotedSpeech(
      source: source,
      chunks: [for (final quote in quotes) quote.segment],
      quotedChunks: quotes,
      speakerByStart: const {},
      hardBoundaries: [bStart],
    );
    expect(merged.segments.where((segment) =>
        segment.start < bStart && segment.end > bStart), isEmpty);
    // The second spine begins with a leading space, which the speech
    // splitter intentionally excludes from spoken text. It must not
    // invent a spoken segment at that whitespace-only source offset.
    final secondSpine = merged.segments.where(
        (part) => part.start >= bStart).toList();
    expect(secondSpine, isNotEmpty);
    expect(secondSpine.first.start, bStart + 1);
    expect(secondSpine.every((part) => part.start >= bStart), isTrue);
    expect(buildEpubChapters(document, merged.segments).length, 2);
  });


  test('unclosed quote in prior spine cannot turn next chapter into dialogue',
      () {
    const first = '«Old dialogue without a closing mark';
    const second = 'Narrator text. «Fresh dialogue» follows.';
    const source = '$first\n\n$second';
    final bStart = first.length + 2;
    final document = DocumentContent(
      title: 'Book', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml',
            start: 0, end: first.length, title: 'A'),
        EpubSpineRange(idref: 'b', href: 'b.xhtml',
            start: bStart, end: source.length, title: 'B'),
      ],
    );
    final quotes = splitQuotedSegmentsWithRegions(
        segmentEpubSpine(document), resetAt: [bStart]);
    final narrator = quotes.firstWhere(
        (item) => item.segment.text.contains('Narrator text.'));
    final fresh = quotes.firstWhere(
        (item) => item.segment.text.contains('«Fresh dialogue»'));
    expect(narrator.quoteGroup, isNull);
    expect(fresh.quoteGroup, isNotNull);
    expect(fresh.segment.start, source.indexOf('«Fresh dialogue»'));
  });

  test('fallback chapter labels and missing playable ranges are stable', () {
    const content = DocumentContent(
      title: 'Book',
      text: 'Intro\n\nMain',
      epubSpineRanges: [
        EpubSpineRange(idref: 'intro', href: 'intro.xhtml',
            start: 0, end: 5),
        EpubSpineRange(idref: 'empty', href: 'empty.xhtml',
            start: 5, end: 7),
        EpubSpineRange(idref: 'main', href: 'main.xhtml',
            start: 7, end: 11, title: '  Chapter III  '),
      ],
    );
    final speech = segmentEpubSpine(content);
    final chapters = buildEpubChapters(content, speech);
    // Visual-only OPF spine sections must remain accessible from the
    // directory even though they have no narratable text themselves.
    expect(chapters.map((c) => c.idref).toList(),
        ['intro', 'empty', 'main']);
    expect(chapters.map((c) => c.title).toList(),
        ['Chapter 1', 'Chapter 2', 'Chapter III']);
    expect(chapters.map((c) => c.hasSpeech), [true, false, true]);
    expect(chapters.map((c) => c.segmentIndex), [0, 1, 1]);
    expect(chapters[1].start, 5);
    expect(chapters[1].end, 7);
    expect(chapterIndexForOffset(chapters, 5), 1);
    expect(chapterIndexForOffset(chapters, 7), 2);
    expect(chapterIndexForOffset(chapters, -100), 0);
    expect(chapterIndexForOffset(const [], 2), -1);
  });

  test('standalone heading gets accessible style without inserting text', () {
    const heading = EpubChapter(
      idref: 'ch1', title: 'Chapter One', start: 0, end: 100,
      segmentIndex: 0,
    );
    expect(isStandaloneChapterHeading(
      heading, const SpeechSegment(0, 11, 'Chapter One')), isTrue);
    expect(isStandaloneChapterHeading(
      heading, const SpeechSegment(
        0, 32, 'Chapter One followed by narration')), isFalse);
    expect(isStandaloneChapterHeading(
      heading, const SpeechSegment(12, 23, 'Chapter One')), isFalse);
    expect(isStandaloneChapterHeading(
      null, const SpeechSegment(0, 11, 'Chapter One')), isFalse);
  });

  test('binary chapter lookup remains correct across 20000 sections',
      () {
    final chapters = List<EpubChapter>.generate(
      20000,
      (index) => EpubChapter(
        idref: 'id$index', title: 'Chapter $index',
        start: index * 17, end: (index + 1) * 17,
        segmentIndex: index,
      ),
    );
    for (final index in [0, 1, 10, 999, 12000, 19999]) {
      expect(chapterIndexForOffset(chapters, index * 17), index);
      expect(chapterIndexForOffset(chapters, index * 17 + 16), index);
    }
    expect(chapterIndexForOffset(chapters, -100), 0);
    expect(chapterIndexForOffset(chapters, 999999), 19999);
    expect(chapterIndexForOffset(const [], 0), -1);
  });

  test('source fragment inside a long speech chunk maps to that chunk', () {
    const segments = [
      SpeechSegment(0, 9, 'Beginning'),
      SpeechSegment(11, 24, 'Secondphrase.'),
      SpeechSegment(28, 35, 'Closing'),
    ];
    expect(speechSegmentIndexForOffset(segments, 0), 0);
    expect(speechSegmentIndexForOffset(segments, 5), 0);
    expect(speechSegmentIndexForOffset(segments, 9), 1);
    expect(speechSegmentIndexForOffset(segments, 12), 1);
    expect(speechSegmentIndexForOffset(segments, 27), 2);
    expect(speechSegmentIndexForOffset(segments, 999), 2);
    expect(speechSegmentIndexForOffset(const [], 5), -1);
  });

  test('TXT fallback segmentation unchanged without EPUB spine', () {
    const source = 'A sentence. Another sentence.';
    const plain = DocumentContent(title: 'Text', text: source);
    final chunks = segmentEpubSpine(plain);
    expect(chunks.map((chunk) => chunk.text).toList(),
        ['A sentence.', 'Another sentence.']);
    expect(buildEpubChapters(plain, chunks), isEmpty);
  });

  test('invalid overlapping or out-of-range spine offsets fail closed', () {
    const overlapping = DocumentContent(
      title: 'Book',
      text: 'abcdefghijkl',
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml', start: 0, end: 8),
        EpubSpineRange(idref: 'b', href: 'b.xhtml', start: 6, end: 12),
      ],
    );
    expect(() => segmentEpubSpine(overlapping), throwsFormatException);

    const invalid = DocumentContent(
      title: 'Book',
      text: 'a',
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml', start: 0, end: 3),
      ],
    );
    expect(() => segmentEpubSpine(invalid), throwsFormatException);
  });
}
