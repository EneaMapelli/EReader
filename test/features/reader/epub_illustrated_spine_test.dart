import 'dart:convert';

import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_embedded_content.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/epub_paragraph_tile.dart';
import 'package:ereader/features/reader/epub_progressive_layout.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = 'A narrated passage.';
  final clips = [SpeechSegment(0, source.length, source)];

  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
    'AAAAC0lEQVR42mP8/x8AAwMCAO1WlU0AAAAASUVORK5CYII=');

  DocumentContent sample() => DocumentContent(
    title: 'Illustrated EPUB',
    text: source,
    epubSpineRanges: [
      EpubSpineRange(idref: 'cover-a', href: 'a.xhtml',
          start: 0, end: 0, title: 'First cover'),
      EpubSpineRange(idref: 'cover-b', href: 'b.xhtml',
          start: 0, end: 0, title: 'Second cover'),
      EpubSpineRange(idref: 'story', href: 'story.xhtml',
          start: 0, end: source.length, title: 'Story'),
      EpubSpineRange(idref: 'appendix', href: 'back.xhtml',
          start: source.length, end: source.length,
          title: 'Illustrated appendix'),
    ],
    epubImages: [
      EpubEmbeddedImage(offset: 0, bytes: png, alt: 'Picture A',
          resourcePath: 'images/a.png', spineIdref: 'cover-a'),
      EpubEmbeddedImage(offset: 0, bytes: png, alt: 'Picture B',
          resourcePath: 'images/b.png', spineIdref: 'cover-b'),
      EpubEmbeddedImage(offset: source.length, bytes: png,
          alt: 'The final picture', resourcePath: 'images/back.png',
          spineIdref: 'appendix'),
    ],
  );

  test('shared source offsets keep independent OPF illustrated blocks', () {
    final document = sample();
    final chapters = buildEpubChapters(document, clips);
    final layout = buildProgressiveEpubVisualLayout(document, clips, chapters);
    expect(layout.blocks, hasLength(4));
    expect(layout.blockForSpine('cover-a', 0), 0);
    expect(layout.blockForSpine('cover-b', 0), 1);
    expect(layout.blockForSpine('appendix', source.length), 3);
    expect(layout.blockForSourceOffset(0), 2,
        reason: 'A source offset alone must NOT guess which empty OPF cover');
    expect(layout.silentSpineIdrefForBlock(0), 'cover-a');
    expect(layout.silentSpineIdrefForBlock(1), 'cover-b');
    expect(layout.silentSpineIdrefForBlock(2), isNull);
    expect(layout.silentSpineIdrefForBlock(3), 'appendix');
    expect(layout.blocks[0].images.single.alt, 'Picture A');
    expect(layout.blocks[1].images.single.alt, 'Picture B');
    expect(layout.blocks[2].images, isEmpty);
    expect(layout.blocks[3].images.single.alt, 'The final picture');
    expect(layout.blocks[0].visualOnlySectionTitle, 'First cover');
    expect(layout.blocks[1].visualOnlySectionTitle, 'Second cover');
    expect(layout.blocks[3].visualOnlySectionTitle, 'Illustrated appendix');
    expect(layout.blocks[0].text, isEmpty);
    expect(layout.blocks[1].runs, isEmpty);
    expect(layout.blocks[3].firstSegmentIndex, isNull);
    expect(layout.positionForVisibleBlock(0, clips).sourceOffset, 0);
    expect(layout.positionForVisibleBlock(3, clips).sourceOffset,
        source.length);
    expect(layout.positionForVisibleBlock(3, clips).segmentIndex,
        clips.length,
        reason: 'Scrolling to a trailing silent image must not replay TTS');
    final coverBookmark = const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'cover-b', localOffset: 0,
    );
    expect(document.offsetOf(coverBookmark), 0);
    expect(layout.blockForSpine(coverBookmark.sourceId, 0), 1,
        reason: 'The OPF ID, not its shared UTF-16 offset, selects cover B');
    expect(layout.blockForSegment(0), 2);
  });

  test('remote audio EOF preserves first illustrated appendix identity',
      () {
    final document = sample();
    final chapters = buildEpubChapters(document, clips);
    final targets = buildEpubMediaChapterTargets(
        chapters, clips.length, document.text.length);
    final eof = targets[clips.length]!;
    final layout = buildProgressiveEpubVisualLayout(
        document, clips, chapters);
    expect(eof.sourceOffset, source.length);
    expect(eof.silentSpineIdref, 'appendix');
    final targetBlock = layout.blockForSpine(
        eof.silentSpineIdref!, eof.sourceOffset);
    expect(targetBlock, 3);
    final anchor = ReadingAnchor(
      kind: AnchorKind.epubSpine,
      sourceId: eof.silentSpineIdref!,
      localOffset: 0,
    );
    expect(document.offsetOf(anchor), source.length);
    expect(layout.blockForSpine(anchor.sourceId, eof.sourceOffset), 3);
    // The same source offset is not a sufficient visual section ID.
    expect(layout.blockForSourceOffset(source.length), isNot(0));
  });

  test('visual checkpoint pin keeps exact empty OPF tile selected', () {
    final document = sample();
    final layout = buildProgressiveEpubVisualLayout(document, clips,
        buildEpubChapters(document, clips));
    final guard = EpubVisualSourceCheckpoint();
    guard.hold(0, awaitTarget: true, targetBlockIndex: 0);
    expect(guard.preserveOnVisibleBlock(0, layout), isTrue);
    expect(guard.offset, 0);
    expect(guard.preserveOnVisibleBlock(1, layout), isFalse,
        reason: 'Moving from cover A to same-offset cover B is real scroll');
    expect(guard.offset, isNull);
  });

  testWidgets('a local illustrated-only tile renders as image, not text TTS',
      (tester) async {
    final document = sample();
    final layout = buildProgressiveEpubVisualLayout(document, clips,
        buildEpubChapters(document, clips));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EpubParagraphTile(
        block: layout.blocks[0],
        activeSegmentIndex: 0,
        fontSize: 18,
        onSelectSegment: (_) =>
            fail('An illustrated-only tile must not request speech'),
      )),
    ));
    expect(find.text('First cover'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text(source), findsNothing);
    expect(layout.blocks[0].runs, isEmpty);
  });
}
