import 'dart:convert';
import 'dart:typed_data';

import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_embedded_content.dart';
import 'package:ereader/data/epub_structural_markup.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/epub_paragraph_tile.dart';
import 'package:ereader/features/reader/epub_progressive_layout.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
    'AAAAC0lEQVR42mP8/x8AAwMCAO1WlU0AAAAASUVORK5CYII=',
  ));
  EpubEmbeddedImage picture(int position, String alt, {String? spine}) =>
      EpubEmbeddedImage(offset: position, bytes: bytes, alt: alt,
          resourcePath: 'images/$alt.png', spineIdref: spine);

  List<String> flattened(List<EpubVisualFlowItem> parts) => [
    for (final part in parts)
      if (part.image != null) 'IMG:${part.image!.alt}'
      else 'TXT:${part.runs.map((run) => run.text).join()}',
  ];

  test('image between two halves of same TTS run preserves source and voice',
      () {
    const source = 'Before a picture, after a picture.';
    const speechIndex = 17;
    final flow = epubVisualFlow(EpubVisualBlock(
      start: 0, end: source.length, chapterStart: false, heading: false,
      firstSegmentIndex: speechIndex,
      runs: [
        EpubVisualRun.fromSource(0, source.length, source, speechIndex,
          italic: true, bold: true, linkTargetOffset: 123,
          isFootnote: true),
      ],
      images: [picture(18, 'middle')],
    ));
    expect(flattened(flow), [
      'TXT:${source.substring(0, 18)}',
      'IMG:middle',
      'TXT:${source.substring(18)}',
    ]);
    final texts = [
      for (final part in flow) ...part.runs,
    ];
    expect(texts.map((run) => run.text).join(), source);
    expect(texts.map((run) => run.start), [0, 18]);
    expect(texts.map((run) => run.end), [18, source.length]);
    expect(texts.every((run) => run.segmentIndex == speechIndex), isTrue);
    expect(texts.every((run) => run.bold && run.italic), isTrue);
    expect(texts.every((run) =>
        run.linkTargetOffset == 123 && run.isFootnote), isTrue);
  });

  test('images before, after and at same source position retain EPUB order',
      () {
    const source = 'Head Tail';
    final flow = epubVisualFlow(EpubVisualBlock(
      start: 0, end: source.length, heading: false, chapterStart: false,
      firstSegmentIndex: 0,
      runs: [EpubVisualRun.fromSource(0, source.length, source, 0)],
      images: [
        picture(source.length, 'end'),
        picture(0, 'before'),
        picture(4, 'first'),
        picture(4, 'second'),
      ],
    ));
    expect(flattened(flow),
        ['IMG:before', 'TXT:Head', 'IMG:first',
         'IMG:second', 'TXT: Tail', 'IMG:end']);
    expect(flow.where((part) => part.image == null)
        .expand((part) => part.runs).map((run) => run.text).join(), source);
  });

  test('UTF-16 picture positions never change an emoji or source anchor',
      () {
    const source = 'A 🐉 dragon and 📖 book.';
    final boundary = source.indexOf(' and');
    final original = EpubVisualRun.fromSource(0, source.length, source, 4,
        bold: true, auxiliaryFootnoteKey: 'footnote-1');
    final flow = epubVisualFlow(EpubVisualBlock(
      start: 0, end: source.length, chapterStart: false, heading: false,
      firstSegmentIndex: 4,
      runs: [original],
      images: [picture(boundary, 'emoji-place')],
    ));
    expect(flattened(flow), [
      'TXT:${source.substring(0, boundary)}',
      'IMG:emoji-place',
      'TXT:${source.substring(boundary)}',
    ]);
    expect(flow.expand((part) => part.runs)
        .map((run) => run.text).join(), source);
    expect(flow.expand((part) => part.runs)
        .every((run) => run.auxiliaryFootnoteKey == 'footnote-1'), isTrue);
    expect(original.text, source,
        reason: 'The untouched source-backed run still exists for TTS');
  });

  test('stale image offset inside surrogate pair snaps after entire emoji',
      () {
    const source = 'A 🐉 end';
    final lowSurrogateOffset = source.indexOf('🐉') + 1;
    final flow = epubVisualFlow(EpubVisualBlock(
      start: 0, end: source.length, heading: false, chapterStart: false,
      firstSegmentIndex: 0,
      runs: [EpubVisualRun.fromSource(0, source.length, source, 0)],
      images: [picture(lowSurrogateOffset, 'safe-emoji')],
    ));
    expect(flattened(flow),
        ['TXT:A 🐉', 'IMG:safe-emoji', 'TXT: end']);
    expect(flow.expand((part) => part.runs).map((run) => run.text).join(),
        source);
  });

  test('no image retains original runs without speech change', () {
    const block = EpubVisualBlock(
      start: 0, end: 5, chapterStart: false, heading: false,
      firstSegmentIndex: 0,
      runs: [EpubVisualRun(0, 5, 'Hello', 0)],
    );
    final parts = epubVisualFlow(block);
    expect(parts, hasLength(1));
    expect(identical(parts.single.runs, block.runs), isTrue);
    expect(parts.single.runs.single.text, 'Hello');
    expect(parts.single.image, isNull);
  });

  test('visual-only image blocks never create hidden text or TTS', () {
    final block = EpubVisualBlock(
      start: 7, end: 7, chapterStart: true, heading: false,
      firstSegmentIndex: null, runs: const [],
      images: [picture(7, 'Cover')],
      visualOnlySectionTitle: 'A cover',
    );
    expect(flattened(epubVisualFlow(block)), ['IMG:Cover']);
    expect(block.text, isEmpty);
  });

  test('eager and progressive EPUB layouts agree on physical image ownership',
      () {
    const source = 'Before image. Later text.\n\nSecond chapter.';
    final divider = source.indexOf('\n\n');
    final secondStart = divider + 2;
    final ranges = [
      EpubSpineRange(idref: 'one', href: 'one.xhtml',
          start: 0, end: divider, title: 'First'),
      EpubSpineRange(idref: 'two', href: 'two.xhtml',
          start: secondStart, end: source.length, title: 'Second'),
    ];
    final parts = [
      SpeechSegment(0, divider, source.substring(0, divider)),
      SpeechSegment(secondStart, source.length, source.substring(secondStart)),
    ];
    final images = [
      picture(7, 'inside', spine: 'one'),
      picture(divider, 'end-of-first', spine: 'one'),
      picture(secondStart, 'start-of-second', spine: 'two'),
    ];
    final document = DocumentContent(title: 'Inline pictures', text: source,
        epubSpineRanges: ranges, epubImages: images);
    final chapters = buildEpubChapters(document, parts);
    final progressive = buildProgressiveEpubVisualLayout(
        document, parts, chapters);
    final eager = buildEpubVisualLayout(document, parts, chapters);
    for (final layout in [progressive, eager]) {
      expect(layout.blocks, hasLength(2));
      expect(layout.blocks[0].images.map((img) => img.alt),
          ['inside', 'end-of-first']);
      expect(layout.blocks[1].images.map((img) => img.alt),
          ['start-of-second']);
      expect(flattened(epubVisualFlow(layout.blocks[0])), [
        'TXT:${source.substring(0, 7)}',
        'IMG:inside',
        'TXT:${source.substring(7, divider)}',
        'IMG:end-of-first',
      ]);
      expect(flattened(epubVisualFlow(layout.blocks[1])), [
        'IMG:start-of-second', 'TXT:Second chapter.',
      ]);
      expect(layout.blocks.map((block) => block.text).join(), 
          'Before image. Later text.Second chapter.');
      expect(layout.segmentToBlock, [0, 1]);
    }
  });

  test('table preview appears immediately after table source, not at bottom',
      () {
    const source = 'Intro. Col1Col2 Final paragraph.';
    final end = source.indexOf(' Final');
    final block = EpubVisualBlock(
      start: 0, end: source.length, heading: false, chapterStart: false,
      firstSegmentIndex: 0,
      runs: [EpubVisualRun.fromSource(0, source.length, source, 0)],
      tables: [EpubTablePreview(7, end, const [
        ['Col1', 'Col2'],
      ])],
    );
    final flow = epubVisualFlow(block);
    expect(flow, hasLength(3));
    expect(flow.first.runs.map((run) => run.text).join(),
        source.substring(0, end));
    expect(flow[1].table, same(block.tables.single));
    expect(flow.last.runs.map((run) => run.text).join(),
        source.substring(end));
    expect(flow.expand((part) => part.runs)
        .map((run) => run.text).join(), source,
        reason: 'Optional table preview must never delete spoken text');
  });

  test('semantic figure-caption range preserves existing TTS and link mask',
      () {
    const source = 'Prose.Fig 1: north.Prose again.';
    final start = source.indexOf('Fig 1:');
    final end = start + 'Fig 1: north.'.length;
    final initial = [
      EpubVisualRun.fromSource(0, source.length, source, 3,
        bold: true, linkTargetOffset: 10, isFootnote: true),
    ];
    final runs = epubApplyFigureCaptions(
        initial, [EpubFigureCaption(start, end)]);
    expect(runs.map((run) => run.text).join(), source);
    expect(runs.map((run) => run.figureCaption),
        [false, true, false]);
    expect(runs.every((run) => run.segmentIndex == 3), isTrue);
    expect(runs.every((run) =>
        run.bold && run.linkTargetOffset == 10 && run.isFootnote), isTrue);
    expect(initial.single.text, source);
  });

  test('eager and progressive captions and table previews agree', () {
    const source = 'Text.AB.Fig 2.Other.';
    final figureStart = source.indexOf('Fig 2.');
    final figureEnd = figureStart + 'Fig 2.'.length;
    final tableStart = source.indexOf('AB');
    final tableEnd = tableStart + 2;
    const chunks = [SpeechSegment(0, source.length, source)];
    final document = DocumentContent(
      title: 'Figure and table',
      text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 's', href: 's.xhtml',
            start: 0, end: source.length),
      ],
      epubTables: [EpubTablePreview(tableStart, tableEnd,
          const [['A', 'B']])],
      epubFigureCaptions: [EpubFigureCaption(figureStart, figureEnd)],
    );
    final chapters = buildEpubChapters(document, chunks);
    final layouts = [
      buildProgressiveEpubVisualLayout(document, chunks, chapters),
      buildEpubVisualLayout(document, chunks, chapters),
    ];
    for (final layout in layouts) {
      final block = layout.blocks.single;
      expect(block.runs.map((run) => run.text).join(), source);
      final caption = block.runs.where((run) => run.figureCaption).toList();
      expect(caption.map((run) => run.text).join(), 'Fig 2.');
      final flow = epubVisualFlow(block);
      expect(flow.map((part) => part.table).whereType<EpubTablePreview>(),
          hasLength(1));
      expect(flow.expand((part) => part.runs)
          .map((run) => run.text).join(), source);
    }
  });

  test('invalid overlapping figure captions fail closed in both layouts',
      () {
    const source = 'ABCDEF';
    const speech = [SpeechSegment(0, 6, source)];
    final bad = DocumentContent(
      title: 'Bad ranges', text: source,
      epubSpineRanges: const [
        EpubSpineRange(idref: 'a', href: 'a.xhtml', start: 0, end: 6),
      ],
      epubFigureCaptions: const [
        EpubFigureCaption(1, 4), EpubFigureCaption(3, 5),
      ],
    );
    final chapters = buildEpubChapters(bad, speech);
    expect(() => buildProgressiveEpubVisualLayout(
        bad, speech, chapters), throwsFormatException);
    expect(() => buildEpubVisualLayout(
        bad, speech, chapters), throwsFormatException);
  });

  testWidgets('widget paints image between the preceding and following text',
      (tester) async {
    const source = 'Before the image. After the image.';
    final sourceImageOffset = source.indexOf(' After');
    final block = EpubVisualBlock(
      start: 0, end: source.length, heading: false, chapterStart: false,
      firstSegmentIndex: 0,
      runs: [EpubVisualRun.fromSource(0, source.length, source, 0)],
      images: [picture(sourceImageOffset, 'middle')],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: block, activeSegmentIndex: 0, fontSize: 18,
        onSelectSegment: (_) {},
      )),
    ));
    expect(find.byType(Image), findsOneWidget);
    final rich = find.byType(RichText);
    expect(rich, findsWidgets);
    final chunks = tester.widgetList<RichText>(rich)
        .map((widget) => widget.text.toPlainText())
        .where((text) => text.contains('Before') || text.contains(' After'))
        .toList();
    expect(chunks, ['Before the image.', ' After the image.']);
  });
}
