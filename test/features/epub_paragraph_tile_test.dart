import 'package:ereader/features/reader/epub_paragraph_tile.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
import 'package:ereader/data/epub_embedded_content.dart';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const spokenParagraph = EpubVisualBlock(
  start: 0,
  end: 11,
  chapterStart: false,
  heading: false,
  firstSegmentIndex: 0,
  runs: [
    EpubVisualRun(0, 5, 'Hello', 0),
    EpubVisualRun(5, 6, ' ', null),
    EpubVisualRun(6, 11, 'world', 1),
  ],
);

List<TextSpan> leafTextSpans(InlineSpan source) {
  final result = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) result.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }
  }
  visit(source);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB paragraph preserves exact words and selective TTS styling',
      (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: spokenParagraph,
        activeSegmentIndex: 1,
        fontSize: 19,
        onSelectSegment: tapped.add,
      )),
    ));
    final target = find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    );
    final rich = tester.widget<RichText>(target);
    final spans = leafTextSpans(rich.text);
    expect(spans.map((s) => s.text).join(), 'Hello world');
    expect(spans[0].style?.backgroundColor, isNull);
    expect(spans[1].recognizer, isNull,
        reason: 'Unspoken separators must not be clickable as speech');
    expect(spans[2].style?.backgroundColor, isNotNull);
    (spans[0].recognizer! as TapGestureRecognizer).onTap!();
    (spans[2].recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped, [0, 1],
        reason: 'A tap must select the exact corresponding speech segment');
  });

  testWidgets('standalone chapter heading retains accessible heading semantics',
      (tester) async {
    const heading = EpubVisualBlock(
      start: 0, end: 7, chapterStart: true, heading: true,
      firstSegmentIndex: 0,
      runs: [EpubVisualRun(0, 7, 'Opening', 0)],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: heading,
        activeSegmentIndex: 0,
        fontSize: 19,
        onSelectSegment: (_) {},
      )),
    ));
    final semantics = tester.widgetList<Semantics>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(Semantics),
    ));
    expect(semantics.any((item) => item.properties.header == true), isTrue);
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    ));
    expect(rich.text.toPlainText(), 'Opening');
    expect(rich.text.style?.fontSize, 24);
  });

  testWidgets('warm paper and night palettes keep text and highlight readable',
      (tester) async {
    for (final palette in [
      EpubReadingPalette.sepia,
      EpubReadingPalette.night,
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EpubParagraphTile(
          block: spokenParagraph,
          activeSegmentIndex: 1,
          fontSize: 20,
          palette: palette,
          onSelectSegment: (_) {},
        )),
      ));
      final context = tester.element(find.byType(EpubParagraphTile));
      final rich = tester.widget<RichText>(find.descendant(
        of: find.byType(EpubParagraphTile),
        matching: find.byType(RichText),
      ));
      final spans = leafTextSpans(rich.text);
      expect(rich.text.toPlainText(), 'Hello world');
      expect(spans.last.style?.backgroundColor, palette.highlight(context));
      expect(rich.text.style?.color, palette.foreground(context));
      expect(palette.background(context), isNot(palette.foreground(context)));
    }
  });

  testWidgets('author emphasis remains visible during TTS highlighting',
      (tester) async {
    const styled = EpubVisualBlock(
      start: 0, end: 16, chapterStart: false, heading: false,
      firstSegmentIndex: 0,
      runs: [
        EpubVisualRun(0, 6, 'Alpha ', 0),
        EpubVisualRun(6, 10, 'BETA', 0, bold: true),
        EpubVisualRun(10, 11, ' ', null),
        EpubVisualRun(11, 16, 'gamma', 1, italic: true),
      ],
    );
    final chosen = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: styled,
        activeSegmentIndex: 0,
        fontSize: 20,
        onSelectSegment: chosen.add,
      )),
    ));
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    ));
    final spans = leafTextSpans(rich.text);
    expect(rich.text.toPlainText(), 'Alpha BETA gamma');
    final boldSpan = spans.firstWhere((span) => span.text == 'BETA');
    final italicSpan = spans.firstWhere((span) => span.text == 'gamma');
    expect(boldSpan.style?.fontWeight, FontWeight.w700);
    expect(boldSpan.style?.backgroundColor, isNotNull);
    expect(italicSpan.style?.fontStyle, FontStyle.italic);
    expect(italicSpan.style?.backgroundColor, isNull);
    (boldSpan.recognizer! as TapGestureRecognizer).onTap!();
    (italicSpan.recognizer! as TapGestureRecognizer).onTap!();
    expect(chosen, [0, 1]);
  });

  testWidgets('semantic h2 is accessible even without a spine title match',
      (tester) async {
    const heading = EpubVisualBlock(
      start: 0, end: 7, chapterStart: false,
      heading: true, firstSegmentIndex: 0,
      runs: [
        EpubVisualRun(0, 7, 'Section', 0, headingLevel: 2),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: heading, activeSegmentIndex: -1,
        fontSize: 18, onSelectSegment: (_) {},
      )),
    ));
    final semantics = tester.widgetList<Semantics>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(Semantics),
    ));
    expect(semantics.any((value) => value.properties.header == true), isTrue);
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    ));
    expect(rich.text.toPlainText(), 'Section');
    expect(leafTextSpans(rich.text).single.style?.fontWeight,
        FontWeight.w700);
  });

  testWidgets('internal link acts on source target rather than speech',
      (tester) async {
    const block = EpubVisualBlock(
      start: 0, end: 9, chapterStart: false,
      heading: false, firstSegmentIndex: 0,
      runs: [
        EpubVisualRun(0, 4, 'Jump', 0, linkTargetOffset: 42),
        EpubVisualRun(4, 9, ' next', 0),
      ],
    );
    final links = <int>[];
    final speech = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: block, activeSegmentIndex: 0, fontSize: 18,
        onSelectSegment: speech.add,
        onOpenLink: links.add,
      )),
    ));
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    ));
    final spans = leafTextSpans(rich.text);
    expect(spans.first.style?.decoration, TextDecoration.underline);
    (spans.first.recognizer! as TapGestureRecognizer).onTap!();
    (spans.last.recognizer! as TapGestureRecognizer).onTap!();
    expect(links, [42]);
    expect(speech, [0]);
  });

  testWidgets('bounded local picture and ragged table preview appear safely',
      (tester) async {
    // Minimal real 1x1 PNG; the resource is passed as in-memory data.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mP8/x8AAwMCAO1WlU0AAAAASUVORK5CYII=');
    final block = EpubVisualBlock(
      start: 0, end: 7, chapterStart: false,
      heading: false, firstSegmentIndex: 0,
      runs: const [EpubVisualRun(0, 7, 'Caption', 0)],
      images: [EpubEmbeddedImage(
        offset: 7, bytes: png, alt: 'A diagram', resourcePath: 'diagram.png',
      )],
      tables: const [
        EpubTablePreview(0, 7, [
          ['Column A', 'Column B'], ['Only A'],
        ]),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: EpubParagraphTile(
          block: block, activeSegmentIndex: 0, fontSize: 18,
          onSelectSegment: (_) {},
        ),
      )),
    ));
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('Table preview'), findsOneWidget);
    await tester.tap(find.textContaining('Table preview'));
    await tester.pumpAndSettle();
    expect(find.text('Column A'), findsOneWidget);
    expect(find.text('Column B'), findsOneWidget);
    expect(find.text('Only A'), findsOneWidget);
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    ));
    expect(rich.text.toPlainText(), 'Caption',
        reason: 'TTS source remains present exactly once in the paragraph');
  });

  testWidgets('new paragraph data replaces stale tap recognizers', (tester) async {
    final tapped = <int>[];
    Widget frame(EpubVisualBlock block) => MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: block,
        activeSegmentIndex: 1,
        fontSize: 20,
        onSelectSegment: tapped.add,
      )),
    );
    await tester.pumpWidget(frame(spokenParagraph));
    const next = EpubVisualBlock(
      start: 25, end: 32, chapterStart: false, heading: false,
      firstSegmentIndex: 5,
      runs: [EpubVisualRun(25, 32, 'Another', 5)],
    );
    await tester.pumpWidget(frame(next));
    final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(EpubParagraphTile),
      matching: find.byType(RichText),
    ));
    final span = leafTextSpans(rich.text).single;
    (span.recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped, [5]);
    expect(rich.text.toPlainText(), 'Another');
  });
}
