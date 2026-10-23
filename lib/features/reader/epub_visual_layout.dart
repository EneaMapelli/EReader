import '../../data/book_decoder.dart';
import '../../domain/speech_segment.dart';
import 'epub_chapter_navigation.dart';

/// An unmodified substring of the extracted EPUB text, optionally covered
/// by one of the speech engine's original, source-aligned segments.
class EpubVisualRun {
  const EpubVisualRun(this.start, this.end, this.text, this.segmentIndex);
  final int start;
  final int end;
  final String text;
  final int? segmentIndex;
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
  });

  final int start;
  final int end;
  final List<EpubVisualRun> runs;
  final bool chapterStart;
  final bool heading;
  final int? firstSegmentIndex;

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
      runs.add(EpubVisualRun(
        from, to, source.substring(from, to), segmentIndex,
      ));
      if (segmentIndex != null) {
        firstSegment ??= segmentIndex;
        if (mapping[segmentIndex] == -1) {
          mapping[segmentIndex] = blocks.length;
        }
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
    blocks.add(EpubVisualBlock(
      start: start,
      end: end,
      runs: List.unmodifiable(runs),
      chapterStart: chapterStart,
      heading: chapter != null && normalized == chapter.title,
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

  return EpubVisualLayout(
    List.unmodifiable(blocks),
    List.unmodifiable(mapping),
  );
}

bool _visualWhitespace(int ch) =>
    ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 0xa0;
bool _highSurrogate(int ch) => ch >= 0xd800 && ch <= 0xdbff;
bool _lowSurrogate(int ch) => ch >= 0xdc00 && ch <= 0xdfff;
