import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentContent documentOf(String text, {String title = 'Chapter One'}) =>
    DocumentContent(
      title: 'Novel',
      text: text,
      epubSpineRanges: [
        EpubSpineRange(
          idref: 'one', href: 'one.xhtml', start: 0, end: text.length,
          title: title,
        ),
      ],
    );

void main() {
  test('paragraph runs concatenate to exact source and locate spoken spans', () {
    const source =
        'Chapter One\n\nOne sentence. Another sentence.\n\nLast paragraph!';
    final document = documentOf(source);
    final segments = segmentEpubSpine(document);
    final chapters = buildEpubChapters(document, segments);
    final layout = buildEpubVisualLayout(document, segments, chapters);
    expect(layout.blocks.length, 3);
    expect(layout.blocks.first.heading, isTrue);
    expect(layout.blocks.first.chapterStart, isTrue);
    expect(layout.blocks[1].heading, isFalse);
    expect(layout.blocks.map((b) => b.text).toList(), [
      'Chapter One', 'One sentence. Another sentence.', 'Last paragraph!',
    ]);
    for (final block in layout.blocks) {
      expect(source.substring(block.start, block.end), block.text);
      expect(block.runs.map((r) => r.text).join(), block.text);
      for (final run in block.runs) {
        expect(source.substring(run.start, run.end), run.text);
      }
    }
    for (var index = 0; index < segments.length; index++) {
      final block = layout.blocks[layout.blockForSegment(index)];
      expect(segments[index].end, greaterThan(block.start));
      expect(segments[index].start, lessThan(block.end));
    }
    final last = layout.blocks.last;
    final anchor = document.anchorAt(BookFormat.epub, last.start);
    expect(anchor.sourceId, 'one');
    expect(document.offsetOf(anchor), last.start);
  });

  test('spine boundaries prevent adjacent paragraphs from merging', () {
    const first = '«Here is a long quotation that keeps going';
    const second = ' and closes here after a paragraph»';
    final source = '$first\n\n$second';
    final doc = documentOf(source, title: 'No heading');
    final original = segmentEpubSpine(doc);
    final quoted = splitQuotedSegmentsWithRegions(original);
    final boundaries = epubParagraphHardBoundaries(doc);
    expect(boundaries, [first.length + 2]);
    final prepared = coalesceQuotedSpeech(
      source: source,
      chunks: [for (final q in quoted) q.segment],
      quotedChunks: quoted,
      speakerByStart: const {},
      hardBoundaries: boundaries,
    );
    expect(prepared.segments.any((s) =>
        s.start < boundaries.first && s.end > boundaries.first), isFalse);
    final layout = buildEpubVisualLayout(
      doc, prepared.segments,
      buildEpubChapters(doc, prepared.segments),
    );
    expect(layout.blocks.length, 2);
    expect(layout.blocks[1].start, boundaries.first);
  });

  test('spine chapter boundaries and two paragraphs keep chapter mapping', () {
    const first = 'Introduction.\n\nMore introductory material.';
    const second = 'New chapter heading\n\nSome text from chapter two.';
    final source = '$first\n\n$second';
    final secondStart = first.length + 2;
    final doc = DocumentContent(
      title: 'Two chapters', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'one', href: 'one.xhtml',
            start: 0, end: first.length, title: 'Intro'),
        EpubSpineRange(idref: 'two', href: 'two.xhtml',
            start: secondStart, end: source.length,
            title: 'New chapter heading'),
      ],
    );
    final segments = segmentEpubSpine(doc);
    final chapters = buildEpubChapters(doc, segments);
    final layout = buildEpubVisualLayout(doc, segments, chapters);
    expect(layout.blocks.length, 4);
    expect(layout.blocks[2].chapterStart, isTrue);
    expect(layout.blocks[2].heading, isTrue);
    expect(layout.blocks[2].start, secondStart);
    expect(layout.blocks[1].end, lessThan(secondStart));
    expect(layout.blocks[2].firstSegmentIndex,
        chapters[1].segmentIndex);
    expect(layout.blockForSegment(chapters[1].segmentIndex), 2);
  });

  test('long surrogate-bearing paragraph splits safely and retains text', () {
    final source = List.filled(70, '📖').join();
    final doc = documentOf(source, title: 'Non-heading');
    final segments = segmentEpubSpine(doc);
    final layout = buildEpubVisualLayout(
      doc, segments, buildEpubChapters(doc, segments),
      maxBlockChars: 17,
    );
    expect(layout.blocks.length, greaterThan(2));
    expect(layout.blocks.map((b) => b.text).join(), source);
    for (final block in layout.blocks) {
      final startUnit = source.codeUnitAt(block.start);
      final endUnit = source.codeUnitAt(block.end - 1);
      expect(startUnit >= 0xDC00 && startUnit <= 0xDFFF, isFalse);
      expect(endUnit >= 0xD800 && endUnit <= 0xDBFF, isFalse);
      expect(block.text.runes.length, greaterThan(0));
    }
  });

  test('gaps between speech segments remain readable and unmodified', () {
    const source = 'Hi there.\n\nA second paragraph.';
    final doc = documentOf(source, title: 'Not a title');
    const segments = [
      SpeechSegment(0, 2, 'Hi'),
      SpeechSegment(4, 9, 'there'),
      SpeechSegment(11, 12, 'A'),
      SpeechSegment(13, 19, 'second'),
    ];
    final layout = buildEpubVisualLayout(
      doc, segments, buildEpubChapters(doc, segments),
    );
    expect(layout.blocks.map((b) => b.text).join(' | '),
        'Hi there. | A second paragraph.');
    expect(layout.blocks.first.runs.any((r) => r.segmentIndex == null), isTrue);
    expect(layout.blocks.last.runs.any((r) => r.segmentIndex == null), isTrue);
  });

  test('source-mismatched and overlapping spoken chunks are rejected', () {
    const doc = DocumentContent(
      title: 'X', text: 'Hello there',
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml',
            start: 0, end: 11),
      ],
    );
    expect(() => buildEpubVisualLayout(doc, const [
      SpeechSegment(0, 5, 'Wrong'),
    ], const []), throwsFormatException);
    expect(() => buildEpubVisualLayout(doc, const [
      SpeechSegment(0, 5, 'Hello'),
      SpeechSegment(3, 8, 'lo th'),
    ], const []), throwsFormatException);
  });

  test('invalid/empty input and impossible max lengths fail predictably', () {
    const empty = DocumentContent(title: 'Empty', text: '');
    final blank = buildEpubVisualLayout(empty, const [], const []);
    expect(blank.blocks, isEmpty);
    expect(blank.blockForSegment(0), 0);
    expect(() => buildEpubVisualLayout(empty, const [], const [],
        maxBlockChars: 0), throwsArgumentError);
    const broken = DocumentContent(
      title: 'Broken', text: 'abc',
      epubSpineRanges: [
        EpubSpineRange(idref: 'oops', href: 'broken.xhtml',
            start: 1, end: 9),
      ],
    );
    expect(() => buildEpubVisualLayout(broken, const [], const []),
        throwsFormatException);
  });
}
