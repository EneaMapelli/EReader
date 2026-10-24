import '../../data/book_decoder.dart';
import '../../data/epub_inline_style.dart';
import '../../data/epub_embedded_content.dart';
import '../../domain/speech_segment.dart';
import 'epub_chapter_navigation.dart';

/// An unmodified substring of the extracted EPUB text, optionally covered
/// by one of the speech engine's original, source-aligned segments.
class EpubVisualRun {
  const EpubVisualRun(this.start, this.end, this.text, this.segmentIndex, {
    this.bold = false,
    this.italic = false,
    this.headingLevel = 0,
    this.linkTargetOffset,
  });
  final int start;
  final int end;
  final String text;
  final int? segmentIndex;
  final bool bold;
  final bool italic;
  final int headingLevel;
  final int? linkTargetOffset;
}

/// One paragraph-sized, text-only display unit. Reading anchors always
/// belong to the original EPUB spine and never to these presentation blocks.
class EpubVisualBlock {
  const EpubVisualBlock({
    required this.start,
    required this.end,
    required this.runs,
    required this.chapterStart,
    required this.heading,
    required this.firstSegmentIndex,
    this.images = const [],
    this.tables = const [],
  });

  final int start;
  final int end;
  final List<EpubVisualRun> runs;
  final bool chapterStart;
  final bool heading;
  final int? firstSegmentIndex;
  final List<EpubEmbeddedImage> images;
  final List<EpubTablePreview> tables;

  String get text => runs.map((run) => run.text).join();
}

class EpubVisualLayout {
  const EpubVisualLayout(this.blocks, this.segmentToBlock);
  final List<EpubVisualBlock> blocks;
  final List<int> segmentToBlock;

  int blockForSegment(int segmentIndex) {
    if (blocks.isEmpty || segmentToBlock.isEmpty) return 0;
    final index = segmentIndex.clamp(0, segmentToBlock.length - 1).toInt();
    final mapped = segmentToBlock[index];
    return mapped >= 0 ? mapped : 0;
  }
}

/// Paragraph breaks are also hard narration boundaries for EPUB so a
/// coalesced quoted turn does not span two independently rendered blocks.
/// Entries are sorted and refer only to original UTF-16 source positions.
List<int> epubParagraphHardBoundaries(DocumentContent document) {
  final boundaries = <int>[];
  final newline = RegExp(r'\n[ \t]*\n+');
  for (final range in document.epubSpineRanges) {
    if (range.start < 0 || range.end < range.start ||
        range.end > document.text.length) {
      throw const FormatException('Invalid EPUB paragraph ranges');
    }
    if (range.start > 0) boundaries.add(range.start);
    for (final match in newline.allMatches(
        document.text.substring(range.start, range.end))) {
      boundaries.add(range.start + match.end);
    }
  }
  return List.unmodifiable(boundaries);
}

/// Paragraph-aware *safe text* EPUB renderer model. It never executes XHTML,
/// fetches resources or changes the source text sent to the TTS engine.
/// Long paragraphs are split for lazy loading; no visual block crosses an
/// EPUB spine boundary even if the input lacks paragraph separators.
EpubVisualLayout buildEpubVisualLayout(
  DocumentContent document,
  List<SpeechSegment> segments,
  List<EpubChapter> chapters, {
  int maxBlockChars = 2400,
}) {
  if (maxBlockChars < 16) {
    throw ArgumentError.value(maxBlockChars, 'maxBlockChars');
  }
  final source = document.text;
  final styles = document.epubInlineStyles;
  final links = document.epubLinks;
  var lastLinkEnd = 0;
  for (final link in links) {
    if (link.start < lastLinkEnd || link.end <= link.start ||
        link.end > source.length ||
        link.targetOffset < 0 || link.targetOffset > source.length) {
      throw const FormatException('Invalid EPUB internal link ranges');
    }
    lastLinkEnd = link.end;
  }
  var lastStyleEnd = 0;
  for (final style in styles) {
    if (style.start < lastStyleEnd || style.end <= style.start ||
        style.end > source.length || style.headingLevel < 0 ||
        style.headingLevel > 6) {
      throw const FormatException('Invalid EPUB inline style ranges');
    }
    lastStyleEnd = style.end;
  }
  var previousEnd = 0;
  for (final segment in segments) {
    if (segment.start < previousEnd || segment.end <= segment.start ||
        segment.end > source.length ||
        source.substring(segment.start, segment.end) != segment.text) {
      throw const FormatException('Invalid source-aligned speech segment');
    }
    previousEnd = segment.end;
  }

  final blocks = <EpubVisualBlock>[];
  final mapping = List<int>.filled(segments.length, -1);
  var segmentCursor = 0;
  var styleCursor = 0;
  var linkCursor = 0;
  var previousSpineEnd = 0;
  final headings = {for (final chapter in chapters) chapter.start: chapter};
  final doubleNewline = RegExp(r'\n[ \t]*\n+');

  void addBlock(int rawStart, int rawEnd, bool chapterStart) {
    var start = rawStart;
    var end = rawEnd;
    while (start < end && _visualWhitespace(source.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _visualWhitespace(source.codeUnitAt(end - 1))) {
      end--;
    }
    if (start == end) return;

    while (segmentCursor < segments.length &&
        segments[segmentCursor].end <= start) {
      segmentCursor++;
    }
    var current = start;
    var index = segmentCursor;
    final runs = <EpubVisualRun>[];
    int? firstSegment;
    void append(int from, int to, int? segmentIndex) {
      if (from >= to) return;
      if (segmentIndex != null) {
        firstSegment ??= segmentIndex;
        if (mapping[segmentIndex] == -1) {
          mapping[segmentIndex] = blocks.length;
        }
      }
      // Preserve both the TTS run index and the semantic XHTML style. A
      // bold/italic span can begin or end in the middle of one speech chunk.
      // Since source and style offsets are sorted, all blocks are linear.
      var offset = from;
      while (offset < to) {
        while (styleCursor < styles.length &&
            styles[styleCursor].end <= offset) {
          styleCursor++;
        }
        EpubInlineStyleSpan? style;
        var until = to;
        if (styleCursor < styles.length) {
          final candidate = styles[styleCursor];
          if (candidate.start > offset) {
            if (candidate.start < until) until = candidate.start;
          } else {
            style = candidate;
            if (candidate.end < until) until = candidate.end;
          }
        }
        while (linkCursor < links.length &&
            links[linkCursor].end <= offset) {
          linkCursor++;
        }
        int? linkTarget;
        if (linkCursor < links.length) {
          final link = links[linkCursor];
          if (link.start > offset) {
            if (link.start < until) until = link.start;
          } else {
            linkTarget = link.targetOffset;
            if (link.end < until) until = link.end;
          }
        }
        if (until <= offset) {
          throw const FormatException('Non-progressing EPUB visual metadata');
        }
        runs.add(EpubVisualRun(
          offset, until, source.substring(offset, until), segmentIndex,
          bold: style?.bold ?? false,
          italic: style?.italic ?? false,
          headingLevel: style?.headingLevel ?? 0,
          linkTargetOffset: linkTarget,
        ));
        offset = until;
      }
    }

    while (current < end) {
      while (index < segments.length &&
          segments[index].end <= current) {
        index++;
      }
      if (index >= segments.length || segments[index].start >= end) {
        append(current, end, null);
        break;
      }
      final segment = segments[index];
      if (segment.start > current) {
        final gapEnd = segment.start < end ? segment.start : end;
        append(current, gapEnd, null);
        current = gapEnd;
        continue;
      }
      final runEnd = segment.end < end ? segment.end : end;
      append(current, runEnd, index);
      current = runEnd;
    }

    final chapter = headings[start];
    final normalized = source.substring(start, end)
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    final semanticHeading = runs.isNotEmpty &&
        runs.every((run) =>
            run.headingLevel > 0 || run.text.trim().isEmpty);
    blocks.add(EpubVisualBlock(
      start: start,
      end: end,
      runs: List.unmodifiable(runs),
      chapterStart: chapterStart,
      heading: semanticHeading ||
          (chapter != null && normalized == chapter.title),
      firstSegmentIndex: firstSegment,
    ));
  }

  void addBounded(int start, int end, bool chapterStart) {
    var cursor = start;
    var first = chapterStart;
    while (cursor < end) {
      var target = cursor + maxBlockChars;
      if (target >= end) {
        addBlock(cursor, end, first);
        return;
      }
      // Prefer to break before the limit without splitting a UTF-16
      // surrogate pair, so all visible chunks remain source-exact.
      var split = target;
      for (var j = target; j > cursor + maxBlockChars ~/ 2; j--) {
        if (_visualWhitespace(source.codeUnitAt(j - 1))) {
          split = j;
          break;
        }
      }
      if (split < end &&
          _lowSurrogate(source.codeUnitAt(split)) &&
          _highSurrogate(source.codeUnitAt(split - 1))) {
        split--;
      }
      if (split <= cursor) split = target;
      addBlock(cursor, split, first);
      first = false;
      cursor = split;
    }
  }

  for (final spine in document.epubSpineRanges) {
    if (spine.start < previousSpineEnd ||
        spine.end < spine.start || spine.end > source.length) {
      throw const FormatException('Invalid EPUB visual spine range');
    }
    previousSpineEnd = spine.end;
    var cursor = spine.start;
    var isFirst = true;
    for (final match in doubleNewline.allMatches(
        source.substring(spine.start, spine.end))) {
      final until = spine.start + match.start;
      if (until > cursor) {
        addBounded(cursor, until, isFirst);
        isFirst = false;
      }
      cursor = spine.start + match.end;
    }
    if (cursor < spine.end) {
      addBounded(cursor, spine.end, isFirst);
    }
  }

  // Resource overlays belong to the closest readable paragraph block.
  // They do not insert characters, or shift any source/voice anchor.
  // Only a small, bounded number of embedded assets is retained.
  int findBlock(int offset) {
    if (blocks.isEmpty) return -1;
    var low = 0, high = blocks.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (blocks[mid].end < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < blocks.length ? low : blocks.length - 1;
  }

  final imageByBlock = <int, List<EpubEmbeddedImage>>{};
  for (final image in document.epubImages) {
    if (image.offset < 0 || image.offset > source.length) continue;
    final block = findBlock(image.offset);
    if (block >= 0) {
      imageByBlock.putIfAbsent(block, () => []).add(image);
    }
  }
  final tablesByBlock = <int, List<EpubTablePreview>>{};
  for (final table in document.epubTables) {
    if (table.start < 0 || table.end > source.length ||
        table.start >= table.end) continue;
    final block = findBlock(table.start);
    if (block >= 0) {
      tablesByBlock.putIfAbsent(block, () => []).add(table);
    }
  }
  final enriched = [
    for (var i = 0; i < blocks.length; i++)
      EpubVisualBlock(
        start: blocks[i].start, end: blocks[i].end,
        runs: blocks[i].runs,
        chapterStart: blocks[i].chapterStart,
        heading: blocks[i].heading,
        firstSegmentIndex: blocks[i].firstSegmentIndex,
        images: List.unmodifiable(imageByBlock[i] ?? const []),
        tables: List.unmodifiable(tablesByBlock[i] ?? const []),
      ),
  ];
  return EpubVisualLayout(
    List.unmodifiable(enriched),
    List.unmodifiable(mapping),
  );
}

bool _visualWhitespace(int ch) =>
    ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 0xa0;
bool _highSurrogate(int ch) => ch >= 0xd800 && ch <= 0xdbff;
bool _lowSurrogate(int ch) => ch >= 0xdc00 && ch <= 0xdfff;
