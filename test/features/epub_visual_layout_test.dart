import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/data/epub_inline_style.dart';
import 'package:ereader/data/epub_embedded_content.dart';
import 'dart:typed_data';
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
  test('lazy source-backed runs retain exact Unicode and old const API', () {
    const source = 'Start 📖 middle.';
    final lazy = EpubVisualRun.fromSource(
      6, 8, source, 0, italic: true,
    );
    expect(lazy.text, '📖');
    expect(lazy.start, 6);
    expect(lazy.end, 8);
    expect(lazy.segmentIndex, 0);
    expect(lazy.italic, isTrue);
    const old = EpubVisualRun(0, 5, 'Start', 0);
    expect(old.text, 'Start');
  });

  test('large EPUB builds 12000 paragraph blocks with stable source mapping',
      () {
    final paragraphs = List<String>.generate(
      12000, (i) => 'Paragraph $i 📖 with words.',
    );
    final source = paragraphs.join('\n\n');
    final chunks = <SpeechSegment>[];
    var cursor = 0;
    for (final paragraph in paragraphs) {
      chunks.add(SpeechSegment(
        cursor, cursor + paragraph.length, paragraph));
      cursor += paragraph.length + 2;
    }
    final document = documentOf(source, title: 'Not a paragraph');
    final layout = buildEpubVisualLayout(document, chunks, const []);
    expect(layout.blocks.length, paragraphs.length);
    expect(layout.segmentToBlock.length, paragraphs.length);
    expect(epubParagraphHardBoundaries(document).length,
        paragraphs.length - 1);
    for (final index in [0, 1, 500, 5999, 11999]) {
      final block = layout.blocks[index];
      expect(layout.blockForSegment(index), index);
      expect(block.start, chunks[index].start);
      expect(block.end, chunks[index].end);
      expect(block.text, paragraphs[index]);
      expect(block.runs.map((r) => r.text).join(), paragraphs[index]);
    }
    expect(layout.blocks.first.chapterStart, isTrue);
    expect(layout.blocks.last.chapterStart, isFalse);
  });

  test('paragraph regex at spine boundary does not consume next chapter',
      () {
    const first = 'Alpha ends with break.\n';
    const second = 'Beta begins.';
    final source = '$first\n\n$second';
    final startSecond = first.length + 2;
    final doc = DocumentContent(
      title: 'Two chapters',
      text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: 'first.xhtml',
            start: 0, end: first.length),
        EpubSpineRange(idref: 'second', href: 'second.xhtml',
            start: startSecond, end: source.length),
      ],
    );
    final pieces = [
      SpeechSegment(0, first.length, first),
      SpeechSegment(startSecond, source.length, second),
    ];
    final blocks = buildEpubVisualLayout(doc, pieces, const []).blocks;
    expect(blocks.length, 2);
    expect(blocks.first.text, 'Alpha ends with break.');
    expect(blocks.last.text, second);
    expect(blocks.last.chapterStart, isTrue);
    expect(epubParagraphHardBoundaries(doc), [startSecond]);
  });

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
      SpeechSegment(3, 8, 'there'),
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

  test('inline emphasis divides a TTS segment without altering its index', () {
    const source = 'Alpha BETA gamma.';
    const document = DocumentContent(
      title: 'Styled',
      text: source,
      epubSpineRanges: [
        EpubSpineRange(
          idref: 'a', href: 'a.xhtml', start: 0, end: 17,
        ),
      ],
      epubInlineStyles: [
        EpubInlineStyleSpan(6, 10, bold: true),
        EpubInlineStyleSpan(11, 16, italic: true),
      ],
    );
    const segments = [
      SpeechSegment(0, 10, 'Alpha BETA'),
      SpeechSegment(11, 17, 'gamma.'),
    ];
    final layout = buildEpubVisualLayout(
        document, segments, buildEpubChapters(document, segments));
    expect(layout.blocks.length, 1);
    final runs = layout.blocks.single.runs;
    expect(runs.map((r) => r.text).join(), source);
    expect(runs.where((r) => r.bold).map((r) => r.text).join(), 'BETA');
    expect(runs.where((r) => r.italic).map((r) => r.text).join(), 'gamma');
    expect(runs.first.segmentIndex, 0);
    expect(runs.firstWhere((r) => r.bold).segmentIndex, 0);
    expect(runs.firstWhere((r) => r.italic).segmentIndex, 1);
    expect(layout.blockForSegment(0), 0);
    expect(layout.blockForSegment(1), 0);
  });

  test('semantic h2 and Unicode inline spans preserve original anchors', () {
    const source = 'Opening 📖\n\nWords in italic.';
    const document = DocumentContent(
      title: 'Styled',
      text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml',
            start: 0, end: 28),
      ],
      epubInlineStyles: [
        EpubInlineStyleSpan(0, 10, headingLevel: 2),
        EpubInlineStyleSpan(21, 27, italic: true),
      ],
    );
    final segments = segmentEpubSpine(document);
    final layout = buildEpubVisualLayout(
        document, segments, buildEpubChapters(document, segments));
    expect(layout.blocks.length, 2);
    expect(layout.blocks.first.heading, isTrue);
    expect(layout.blocks.first.text, 'Opening 📖');
    expect(layout.blocks.first.runs.every((r) => r.headingLevel == 2),
        isTrue);
    expect(layout.blocks.last.text, 'Words in italic.');
    final target = source.indexOf('italic');
    final anchor = document.anchorAt(BookFormat.epub, target);
    expect(document.offsetOf(anchor), target);
  });

  test('invalid overlapping or out-of-bounds typography fails closed', () {
    const source = 'Hello world';
    const base = [
      EpubSpineRange(idref: 'a', href: 'a.xhtml',
          start: 0, end: 11),
    ];
    const speech = [SpeechSegment(0, 11, source)];
    expect(() => buildEpubVisualLayout(
      const DocumentContent(title: 'X', text: source,
        epubSpineRanges: base,
        epubInlineStyles: [
          EpubInlineStyleSpan(0, 6, bold: true),
          EpubInlineStyleSpan(4, 10, italic: true),
        ]),
      speech, const [],
    ), throwsFormatException);
    expect(() => buildEpubVisualLayout(
      const DocumentContent(title: 'X', text: source,
        epubSpineRanges: base,
        epubInlineStyles: [
          EpubInlineStyleSpan(0, 12, bold: true),
        ]),
      speech, const [],
    ), throwsFormatException);
  });

  test('in-book link splits visual run without losing spoken segment ID',
      () {
    const source = 'Chapter links are source exact.';
    const doc = DocumentContent(
      title: 'Book', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml',
            start: 0, end: 31),
      ],
      epubLinks: [EpubInternalLink(8, 13, 0)],
    );
    const segments = [
      SpeechSegment(0, 31, source),
    ];
    final layout = buildEpubVisualLayout(doc, segments, const []);
    expect(layout.blocks.length, 1);
    final runs = layout.blocks.single.runs;
    expect(runs.map((r) => r.text).join(), source);
    expect(runs.where((r) => r.linkTargetOffset != null)
        .map((r) => r.text).join(), source.substring(8, 13));
    expect(runs.where((r) => r.linkTargetOffset == 0)
        .every((r) => r.segmentIndex == 0), isTrue);
  });

  test('footnote source markers keep TTS segment identity and target', () {
    const source = 'Check [1] for details.';
    const document = DocumentContent(
      title: 'Note', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'body', href: 'body.xhtml',
            start: 0, end: 22),
      ],
      epubLinks: [EpubInternalLink(6, 9, 0, isFootnote: true)],
    );
    const spoken = [SpeechSegment(0, 22, source)];
    final layout = buildEpubVisualLayout(document, spoken, const []);
    final note = layout.blocks.single.runs.firstWhere(
        (run) => run.isFootnote);
    expect(note.text, '[1]');
    expect(note.linkTargetOffset, 0);
    expect(note.segmentIndex, 0);
    expect(layout.blocks.single.text, source);
  });

  test('image and table metadata attach without changing paragraph text',
      () {
    const source = 'Opening.\n\nImage caption.\n\nRow1Row2';
    final image = EpubEmbeddedImage(
      offset: source.indexOf('Image'),
      bytes: Uint8List.fromList([1, 2, 3]),
      alt: 'Illustration', resourcePath: 'img.png',
    );
    final doc = DocumentContent(
      title: 'Book', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml',
            start: 0, end: source.length),
      ],
      epubImages: [image],
      epubTables: [
        EpubTablePreview(
          source.indexOf('Row1'), source.length,
          const [['First', 'Second'], ['One']],
        ),
      ],
    );
    final segments = segmentEpubSpine(doc);
    final layout = buildEpubVisualLayout(
        doc, segments, buildEpubChapters(doc, segments));
    expect(layout.blocks.length, 3);
    expect(layout.blocks.map((b) => b.text).toList(),
        ['Opening.', 'Image caption.', 'Row1Row2']);
    expect(layout.blocks[1].images.single.resourcePath, 'img.png');
    expect(layout.blocks[2].tables.single.rows.length, 2);
    for (final block in layout.blocks) {
      expect(source.substring(block.start, block.end), block.text);
    }
  });

  test('auxiliary note marker preserves source speech and has no target offset',
      () {
    const source = 'Read [1] now.';
    const key = 'OPS/Text/notes.xhtml#fn1';
    const doc = DocumentContent(
      title: 'Note', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'main', href: 'main.xhtml',
            start: 0, end: source.length),
      ],
      epubAuxiliaryFootnotePreviews: [
        EpubAuxiliaryFootnotePreview(key, 'Note only in auxiliary XHTML'),
      ],
      epubLinks: [
        EpubInternalLink(5, 8, null,
            isFootnote: true, auxiliaryFootnoteKey: key),
      ],
    );
    final chunks = segmentEpubSpine(doc);
    final layout = buildEpubVisualLayout(doc, chunks, const []);
    expect(layout.blocks.single.text, source);
    final note = layout.blocks.single.runs.singleWhere(
        (run) => run.auxiliaryFootnoteKey != null);
    expect(note.text, '[1]');
    expect(note.linkTargetOffset, isNull);
    expect(note.auxiliaryFootnoteKey, key);
    expect(note.isFootnote, isTrue);
    expect(note.segmentIndex, isNotNull);
  });

  test('unresolved auxiliary reference is rejected before rendering', () {
    const source = 'Read [1] now.';
    const doc = DocumentContent(
      title: 'Note', text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'main', href: 'main.xhtml',
            start: 0, end: source.length),
      ],
      epubLinks: [
        EpubInternalLink(5, 8, null, isFootnote: true,
            auxiliaryFootnoteKey: 'missing.xhtml#fn1'),
      ],
    );
    expect(() => buildEpubVisualLayout(
        doc, segmentEpubSpine(doc), const []), throwsFormatException);
  });

  test('invalid or overlapping fragment links cannot redirect narration',
      () {
    const source = 'A single line';
    const base = [
      EpubSpineRange(idref: 'x', href: 'x.xhtml', start: 0, end: 13),
    ];
    const spoken = [SpeechSegment(0, 13, source)];
    expect(() => buildEpubVisualLayout(
      const DocumentContent(title: 'X', text: source,
        epubSpineRanges: base,
        epubLinks: [
          EpubInternalLink(0, 5, 2),
          EpubInternalLink(3, 7, 4),
        ]),
      spoken, const [],
    ), throwsFormatException);
    expect(() => buildEpubVisualLayout(
      const DocumentContent(title: 'X', text: source,
        epubSpineRanges: base,
        epubLinks: [EpubInternalLink(0, 3, 99)]),
      spoken, const [],
    ), throwsFormatException);
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
