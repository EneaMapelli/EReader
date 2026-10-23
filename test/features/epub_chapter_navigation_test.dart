import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
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
    expect(merged.segments.any((part) => part.start == bStart), isTrue);
    expect(buildEpubChapters(document, merged.segments).length, 2);
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
    expect(chapters.map((c) => c.idref).toList(), ['intro', 'main']);
    expect(chapters.map((c) => c.title).toList(),
        ['Chapter 1', 'Chapter III']);
    expect(chapterIndexForOffset(chapters, -100), 0);
    expect(chapterIndexForOffset(const [], 2), -1);
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
