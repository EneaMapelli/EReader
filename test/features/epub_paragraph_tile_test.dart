import 'package:ereader/features/reader/epub_paragraph_tile.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
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
