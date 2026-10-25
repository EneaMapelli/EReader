import 'dart:typed_data';

import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_embedded_content.dart';
import 'package:ereader/data/epub_inline_style.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/epub_progressive_layout.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentContent chapter(String source, {
  List<EpubInlineStyleSpan> styles = const [],
  List<EpubInternalLink> links = const [],
  List<EpubAuxiliaryFootnotePreview> notes = const [],
  List<EpubEmbeddedImage> images = const [],
  List<EpubTablePreview> tables = const [],
  String title = 'No matching heading',
}) => DocumentContent(
  title: 'Book',
  text: source,
  epubSpineRanges: [
    EpubSpineRange(idref: 'a', href: 'a.xhtml', start: 0,
        end: source.length, title: title),
  ],
  epubInlineStyles: styles,
  epubLinks: links,
  epubAuxiliaryFootnotePreviews: notes,
  epubImages: images,
  epubTables: tables,
);

void compareLayouts(EpubVisualLayout old, EpubVisualLayout progressive,
    List<SpeechSegment> segments) {
  expect(progressive.blocks.length, old.blocks.length);
  expect(progressive.segmentToBlock, old.segmentToBlock);
  for (var i = 0; i < segments.length; i++) {
    expect(progressive.blockForSegment(i), old.blockForSegment(i));
  }
  for (var i = 0; i < old.blocks.length; i++) {
    final a = old.blocks[i], b = progressive.blocks[i];
    expect((b.start, b.end), (a.start, a.end));
    expect(b.chapterStart, a.chapterStart);
    expect(b.heading, a.heading);
    expect(b.firstSegmentIndex, a.firstSegmentIndex);
    expect(b.text, a.text);
    expect(b.images.length, a.images.length);
    expect(b.tables.length, a.tables.length);
    expect(b.runs.length, a.runs.length);
    for (var j = 0; j < a.runs.length; j++) {
      final original = a.runs[j], lazy = b.runs[j];
      expect((lazy.start, lazy.end), (original.start, original.end));
      expect(lazy.text, original.text);
      expect(lazy.segmentIndex, original.segmentIndex);
      expect((lazy.bold, lazy.italic, lazy.headingLevel),
          (original.bold, original.italic, original.headingLevel));
      expect(lazy.linkTargetOffset, original.linkTargetOffset);
      expect(lazy.isFootnote, original.isFootnote);
      expect(lazy.auxiliaryFootnoteKey, original.auxiliaryFootnoteKey);
    }
  }
}

void main() {
  test('eager and progressive renders match normal EPUB speech and headings',
      () {
    const source =
        'Chapter One\n\nFirst line. Second line!\n\nClosing chapter.';
    final document = chapter(source, title: 'Chapter One');
    final segments = segmentEpubSpine(document);
    final chapters = buildEpubChapters(document, segments);
    final eager = buildEpubVisualLayout(document, segments, chapters);
    final lazy = buildProgressiveEpubVisualLayout(document, segments, chapters);
    expect((lazy.blocks as ProgressiveEpubBlocks).cachedBlockCount, 0);
    compareLayouts(eager, lazy, segments);
    expect((lazy.blocks as ProgressiveEpubBlocks).cachedBlockCount, 3);
  });

  test('rich runs, source-exact links, notes and embedded overlays match', () {
    const source = 'Heading\n\nBold and italic. [1]\n\nSee table.';
    final image = EpubEmbeddedImage(
      offset: source.indexOf('See'),
      bytes: Uint8List.fromList([1, 2, 3]),
      alt: 'Diagram', resourcePath: 'safe.png',
    );
    final noteStart = source.indexOf('[1]');
    final doc = chapter(source, title: 'Heading',
      styles: [
        EpubInlineStyleSpan(0, 7, headingLevel: 2),
        EpubInlineStyleSpan(source.indexOf('Bold'),
            source.indexOf('Bold') + 4, bold: true),
        EpubInlineStyleSpan(source.indexOf('italic'),
            source.indexOf('italic') + 6, italic: true),
      ],
      links: [
        EpubInternalLink(noteStart, noteStart + 3, null,
            isFootnote: true, auxiliaryFootnoteKey: 'notes.xhtml#1'),
      ],
      notes: const [
        EpubAuxiliaryFootnotePreview('notes.xhtml#1', 'The note'),
      ],
      images: [image],
      tables: [
        EpubTablePreview(source.indexOf('See'), source.length,
          const [['Name', 'Value'], ['one', '1']]),
      ],
    );
    final speech = segmentEpubSpine(doc);
    final chapters = buildEpubChapters(doc, speech);
    compareLayouts(
      buildEpubVisualLayout(doc, speech, chapters),
      buildProgressiveEpubVisualLayout(doc, speech, chapters),
      speech,
    );
  });

  test('gaps, spine boundaries and punctuation retain exact mapping', () {
    const a = 'First chapter. A long passage.';
    const b = 'Second 📖 section with whitespace.';
    final source = '$a\n\n$b';
    final second = a.length + 2;
    final document = DocumentContent(
      title: 'Split',
      text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'a', href: 'a.xhtml',
            start: 0, end: a.length, title: 'Intro'),
        EpubSpineRange(idref: 'b', href: 'b.xhtml',
            start: second, end: source.length, title: 'Continuation'),
      ],
    );
    final spoken = [
      SpeechSegment(0, 5, source.substring(0, 5)),
      SpeechSegment(7, a.length, source.substring(7, a.length)),
      SpeechSegment(second, second + 9,
          source.substring(second, second + 9)),
      SpeechSegment(second + 10, source.length,
          source.substring(second + 10)),
    ];
    final chapters = buildEpubChapters(document, spoken);
    compareLayouts(
      buildEpubVisualLayout(document, spoken, chapters),
      buildProgressiveEpubVisualLayout(document, spoken, chapters),
      spoken,
    );
  });

  test('long emoji paragraph splitting remains surrogate-safe', () {
    final source = List.filled(140, '📖').join();
    final document = chapter(source);
    final spoken = segmentEpubSpine(document);
    final chapters = buildEpubChapters(document, spoken);
    final eager = buildEpubVisualLayout(
        document, spoken, chapters, maxBlockChars: 17);
    final progressive = buildProgressiveEpubVisualLayout(
        document, spoken, chapters, maxBlockChars: 17);
    compareLayouts(eager, progressive, spoken);
    expect(progressive.blocks.length, greaterThan(10));
    expect(progressive.blocks.map((b) => b.text).join(), source);
  });

  test('12000 paragraphs index without constructing any rich runs', () {
    final paragraphs = List<String>.generate(
        12000, (i) => 'Entry $i: novel paragraph 📖.');
    final text = paragraphs.join('\n\n');
    final doc = chapter(text);
    final chunks = <SpeechSegment>[];
    var offset = 0;
    for (final paragraph in paragraphs) {
      chunks.add(SpeechSegment(offset, offset + paragraph.length, paragraph));
      offset += paragraph.length + 2;
    }
    final layout = buildProgressiveEpubVisualLayout(
        doc, chunks, const [], maxCachedBlocks: 6);
    final blocks = layout.blocks as ProgressiveEpubBlocks;
    expect(blocks.length, 12000);
    expect(blocks.materializations, 0);
    expect(blocks.cachedBlockCount, 0);
    for (final idx in [0, 1, 150, 4000, 8000, 11998, 11999]) {
      expect(layout.blockForSegment(idx), idx);
      expect(layout.blockForSourceOffset(chunks[idx].start + 2), idx);
      expect(blocks.materializations, 0);
    }
    // Seven distinct blocks exceed a six-slot LRU; the old fixture
    // checked eviction after six accesses, which cannot evict anything.
    for (final idx in [0, 1, 150, 4000, 8000, 11998, 11999]) {
      expect(blocks[idx].text, paragraphs[idx]);
    }
    expect(blocks.cachedBlockCount, 6);
    expect(blocks.materializations, 7);
    expect(blocks[0].text, paragraphs[0]); // evicted first block
    expect(blocks.cachedBlockCount, 6);
    expect(blocks.materializations, 8);
    expect(blocks[0].text, paragraphs[0]); // cached
    expect(blocks.materializations, 8);
    expect(() => blocks[0] = blocks[0], throwsUnsupportedError);
    expect(() => blocks.length = 3, throwsUnsupportedError);
  });

  test('source-offset link in unspoken gap resolves without hydration',
      () {
    const source = 'Prelude.\n\nMiddle.\n\nLast.';
    final doc = chapter(source);
    final speech = segmentEpubSpine(doc);
    final layout = buildProgressiveEpubVisualLayout(
        doc, speech, const [], maxCachedBlocks: 2);
    final eager = buildEpubVisualLayout(doc, speech, const []);
    final lazy = layout.blocks as ProgressiveEpubBlocks;
    expect(lazy.materializations, 0);
    final targets = <int, int>{
      -42: 0,
      0: 0,
      'Prelude.'.length: 1,
      source.indexOf('Middle.'): 1,
      source.indexOf('Last.'): 2,
      source.length + 100: 2,
    };
    for (final entry in targets.entries) {
      expect(layout.blockForSourceOffset(entry.key), entry.value);
      expect(eager.blockForSourceOffset(entry.key), entry.value);
      expect(lazy.materializations, 0);
    }
    expect(layout.blocks[2].text, 'Last.');
    expect(lazy.materializations, 1);
  });

  test('link target in a wholly unspoken paragraph stays visual',
      () {
    const source = 'Opening.\n\nImage caption without speech.\n\nNarrated ending.';
    final captionStart = source.indexOf('Image caption');
    final endingStart = source.indexOf('Narrated ending.');
    final doc = chapter(source);
    final speech = [
      SpeechSegment(endingStart, source.length, 'Narrated ending.'),
    ];
    final progressive = buildProgressiveEpubVisualLayout(
        doc, speech, const []);
    final eager = buildEpubVisualLayout(doc, speech, const []);
    final lazy = progressive.blocks as ProgressiveEpubBlocks;

    expect(progressive.blockForSegment(0), 2,
        reason: 'The only TTS segment is in the last paragraph');
    expect(progressive.blockForSourceOffset(captionStart), 1);
    expect(eager.blockForSourceOffset(captionStart), 1);
    expect(progressive.blockForSourceOffset(captionStart + 9), 1);
    expect(lazy.materializations, 0);
    expect(progressive.blocks[1].text, 'Image caption without speech.');
    expect(lazy.materializations, 1);
    expect(progressive.blocks[1].firstSegmentIndex, isNull);
  });

  test('exact EPUB checkpoint resists initial rebuild, not real scrolling',
      () {
    const source = 'Narration start.\n\nSilent illustration caption.\n\nThe end.';
    final doc = chapter(source);
    final speechStart = source.indexOf('The end.');
    final spoken = [
      SpeechSegment(speechStart, source.length, 'The end.'),
    ];
    final layout = buildProgressiveEpubVisualLayout(doc, spoken, const []);
    final blocks = layout.blocks as ProgressiveEpubBlocks;
    final exact = source.indexOf('illustration');
    final guard = EpubVisualSourceCheckpoint()..hold(exact);

    expect(guard.offset, exact);
    expect(guard.preserveOnVisibleBlock(1, layout), isTrue);
    expect(guard.preserveOnVisibleBlock(1, layout), isTrue);
    expect(guard.offset, exact);
    expect(blocks.materializations, 0,
        reason: 'Restoring a checkpoint must not hydrate every paragraph');

    // Scrolling to another real paragraph releases the original offset.
    expect(guard.preserveOnVisibleBlock(2, layout), isFalse);
    expect(guard.offset, isNull);
    expect(guard.preserveOnVisibleBlock(1, layout), isFalse);

    // An explicit Play/seek ends visual-only checkpoint protection.
    guard.hold(exact);
    guard.clear();
    expect(guard.offset, isNull);
    expect(blocks.materializations, 0);
  });

  test('monotonic segment cursor matches eager layout across many blocks',
      () {
    final source = List.filled(120, 'One segment spans several blocks. ')
        .join();
    final doc = chapter(source);
    const chunkSize = 305;
    final segments = <SpeechSegment>[];
    for (var start = 0; start < source.length; start += chunkSize) {
      final end = start + chunkSize < source.length
          ? start + chunkSize : source.length;
      // These are global source-aligned chunks: visual block boundaries
      // deliberately do not match segment boundaries.
      segments.add(SpeechSegment(start, end, source.substring(start, end)));
    }
    final eager = buildEpubVisualLayout(
        doc, segments, const [], maxBlockChars: 95);
    final progressive = buildProgressiveEpubVisualLayout(
        doc, segments, const [], maxBlockChars: 95, maxCachedBlocks: 4);
    compareLayouts(eager, progressive, segments);
    final lazy = progressive.blocks as ProgressiveEpubBlocks;
    expect(lazy.cachedBlockCount, lessThanOrEqualTo(4));
    expect(lazy.materializations, eager.blocks.length);
    expect(progressive.segmentToBlock.first, 0);
    expect(progressive.segmentToBlock.last,
        greaterThan(progressive.segmentToBlock.first));
  });

  test('prevents unsafe style, link or TTS metadata at index construction',
      () {
    const source = 'Simple prose.';
    final corruptStyle = chapter(source,
      styles: const [EpubInlineStyleSpan(0, 30, bold: true)]);
    final corruptLink = chapter(source,
      links: const [EpubInternalLink(0, 5, 999)]);
    const segment = [SpeechSegment(0, 13, source)];
    expect(() => buildProgressiveEpubVisualLayout(
        corruptStyle, segment, const []), throwsFormatException);
    expect(() => buildProgressiveEpubVisualLayout(
        corruptLink, segment, const []), throwsFormatException);
    expect(() => buildProgressiveEpubVisualLayout(
        chapter(source), const [SpeechSegment(0, 12, 'bad segment')],
        const []), throwsFormatException);
  });

  test('rejects zero cache and too-small paragraph budgets', () {
    final doc = chapter('Normal book.');
    expect(() => buildProgressiveEpubVisualLayout(
        doc, const [], const [], maxCachedBlocks: 0), throwsArgumentError);
    expect(() => buildProgressiveEpubVisualLayout(
        doc, const [], const [], maxBlockChars: 10), throwsArgumentError);
  });

  test('presentation-only footnotes remain tappable with zero speech chunks',
      () {
    const text = 'See [1] for the note.';
    final start = text.indexOf('[1]');
    final doc = chapter(text,
      notes: const [EpubAuxiliaryFootnotePreview('note.xhtml#n1', 'Note')],
      links: [EpubInternalLink(start, start + 3, null,
          isFootnote: true, auxiliaryFootnoteKey: 'note.xhtml#n1')],
    );
    final visual = buildProgressiveEpubVisualLayout(doc, const [], const []);
    expect(visual.segmentToBlock, isEmpty);
    expect(visual.blocks.single.text, text);
    final noteRun = visual.blocks.single.runs.singleWhere(
        (run) => run.auxiliaryFootnoteKey != null);
    expect(noteRun.text, '[1]');
    expect(noteRun.linkTargetOffset, isNull);
    expect(noteRun.isFootnote, isTrue);
  });
}
