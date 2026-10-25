import 'dart:collection';

import '../../data/book_decoder.dart';
import '../../data/epub_embedded_content.dart';
import '../../data/epub_inline_style.dart';
import '../../domain/speech_segment.dart';
import 'epub_chapter_navigation.dart';
import 'epub_visual_layout.dart';

/// Immutable, source-exact paragraph bounds without eager text runs.
/// This index is cheap enough to build before opening the scrolling reader.
class _ParagraphBounds {
  const _ParagraphBounds(this.start, this.end, this.chapterStart,
      this.firstSegmentIndex);
  final int start;
  final int end;
  final bool chapterStart;
  final int? firstSegmentIndex;
}

/// Read-only virtual list: materializes a single paragraph on demand.
/// The LRU ensures that a 100k-paragraph book never retains 100k lists of
/// rich-text spans and source/link/style annotations in memory.
class ProgressiveEpubBlocks extends ListBase<EpubVisualBlock> {
  ProgressiveEpubBlocks._(this._bounds, this._build, this.maxCachedBlocks);
  final List<_ParagraphBounds> _bounds;
  final EpubVisualBlock Function(int) _build;
  final int maxCachedBlocks;
  final LinkedHashMap<int, EpubVisualBlock> _cache = LinkedHashMap();
  int _materializations = 0;

  int get cachedBlockCount => _cache.length;
  int get materializations => _materializations;

  @override
  int get length => _bounds.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Progressive EPUB blocks are immutable');

  @override
  EpubVisualBlock operator [](int index) {
    RangeError.checkValidIndex(index, _bounds);
    final existing = _cache.remove(index);
    if (existing != null) {
      _cache[index] = existing;
      return existing;
    }
    final block = _build(index);
    _materializations++;
    _cache[index] = block;
    if (_cache.length > maxCachedBlocks) {
      _cache.remove(_cache.keys.first);
    }
    return block;
  }

  @override
  void operator []=(int index, EpubVisualBlock value) =>
      throw UnsupportedError('Progressive EPUB blocks are immutable');
}

/// Index the whole book's *boundaries*, not all of its paragraph runs.
/// Source, TTS segment indices and persisted reading anchors never change.
/// Both this and the eager reference renderer use the same canonical text.
EpubVisualLayout buildProgressiveEpubVisualLayout(
  DocumentContent document,
  List<SpeechSegment> segments,
  List<EpubChapter> chapters, {
  int maxBlockChars = 2400,
  int maxCachedBlocks = 48,
}) {
  if (maxBlockChars < 16) {
    throw ArgumentError.value(maxBlockChars, 'maxBlockChars');
  }
  if (maxCachedBlocks < 1 || maxCachedBlocks > 256) {
    throw ArgumentError.value(maxCachedBlocks, 'maxCachedBlocks');
  }
  final source = document.text;
  final styles = document.epubInlineStyles;
  final links = document.epubLinks;
  final safeKeys = {
    for (final entry in document.epubAuxiliaryFootnotePreviews) entry.key,
  };

  var previous = 0;
  for (final segment in segments) {
    if (segment.start < previous || segment.end <= segment.start ||
        segment.end > source.length ||
        source.substring(segment.start, segment.end) != segment.text) {
      throw const FormatException('Invalid progressive EPUB speech segment');
    }
    previous = segment.end;
  }
  previous = 0;
  for (final style in styles) {
    if (style.start < previous || style.end <= style.start ||
        style.end > source.length ||
        style.headingLevel < 0 || style.headingLevel > 6) {
      throw const FormatException('Invalid progressive EPUB style');
    }
    previous = style.end;
  }
  previous = 0;
  for (final link in links) {
    final target = link.targetOffset;
    final aux = link.auxiliaryFootnoteKey;
    final spineTarget = target != null && target >= 0 &&
        target < source.length && aux == null;
    final auxiliaryTarget = target == null && aux != null &&
        link.isFootnote && safeKeys.contains(aux);
    if (link.start < previous || link.end <= link.start ||
        link.end > source.length ||
        !(spineTarget || auxiliaryTarget)) {
      throw const FormatException('Invalid progressive EPUB internal link');
    }
    previous = link.end;
  }

  // End-position binary searches also handle sparse speech segments and
  // paragraphs that contain presentation-only source text.
  int firstSegmentAfter(int offset) {
    var low = 0;
    var high = segments.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (segments[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  final bounds = <_ParagraphBounds>[];
  final mapping = List<int>.filled(segments.length, -1);
  // Blocks are visited in monotonically increasing source order. Advance
  // a single segment cursor rather than binary-searching every paragraph.
  // This changes boundary-to-segment indexing from O(B log S) toward
  // O(B + S), retaining first-block ownership for segments spanning blocks.
  var indexSegmentCursor = 0;
  const maxIndexedParagraphs = 300000;

  void indexBlock(int rawStart, int rawEnd, bool chapterStart) {
    var start = rawStart;
    var end = rawEnd;
    while (start < end && _white(source.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _white(source.codeUnitAt(end - 1))) {
      end--;
    }
    if (start >= end) return;
    if (bounds.length >= maxIndexedParagraphs) {
      throw const FormatException('EPUB paragraph index budget exceeded');
    }
    while (indexSegmentCursor < segments.length &&
        segments[indexSegmentCursor].end <= start) {
      indexSegmentCursor++;
    }
    int? firstSegment;
    for (var i = indexSegmentCursor;
        i < segments.length && segments[i].start < end; i++) {
      if (segments[i].end <= start) continue;
      firstSegment ??= i;
      if (mapping[i] == -1) mapping[i] = bounds.length;
    }
    bounds.add(_ParagraphBounds(start, end, chapterStart, firstSegment));
  }

  void indexBounded(int start, int end, bool chapterStart) {
    var cursor = start;
    var first = chapterStart;
    while (cursor < end) {
      final target = cursor + maxBlockChars;
      if (target >= end) {
        indexBlock(cursor, end, first);
        return;
      }
      var split = target;
      for (var j = target; j > cursor + maxBlockChars ~/ 2; j--) {
        if (_white(source.codeUnitAt(j - 1))) {
          split = j;
          break;
        }
      }
      split = backtrackCommonGraphemeBoundary(
          source, start: cursor, end: split);
      indexBlock(cursor, split, first);
      first = false;
      cursor = split;
    }
  }

  final separators = RegExp(r'\n[ \t]*\n+');
  var previousEnd = 0;
  for (final spine in document.epubSpineRanges) {
    if (spine.start < previousEnd || spine.end < spine.start ||
        spine.end > source.length) {
      throw const FormatException('Invalid progressive EPUB spine');
    }
    previousEnd = spine.end;
    var cursor = spine.start;
    var first = true;
    for (final match in separators.allMatches(source, spine.start)) {
      if (match.start >= spine.end || match.end > spine.end) break;
      if (match.start > cursor) {
        indexBounded(cursor, match.start, first);
        first = false;
      }
      cursor = match.end;
    }
    if (cursor < spine.end) indexBounded(cursor, spine.end, first);
  }

  // Resource attachment is indexed once; accessing a block cannot cause
  // repeated scans across every picture or table in the entire EPUB.
  int nearestBlock(int offset) {
    if (bounds.isEmpty) return -1;
    var low = 0;
    var high = bounds.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (bounds[mid].end < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < bounds.length ? low : bounds.length - 1;
  }

  final images = <int, List<EpubEmbeddedImage>>{};
  for (final image in document.epubImages) {
    if (image.offset < 0 || image.offset > source.length) continue;
    final idx = nearestBlock(image.offset);
    if (idx >= 0) images.putIfAbsent(idx, () => []).add(image);
  }
  final tables = <int, List<EpubTablePreview>>{};
  for (final table in document.epubTables) {
    if (table.start < 0 || table.end > source.length ||
        table.start >= table.end) continue;
    final idx = nearestBlock(table.start);
    if (idx >= 0) tables.putIfAbsent(idx, () => []).add(table);
  }
  // O(log paragraphs), with no rich-block materialization.
  int indexedBlockForSourceOffset(int offset) {
    if (bounds.isEmpty) return 0;
    var low = 0, high = bounds.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (bounds[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < bounds.length ? low : bounds.length - 1;
  }

  final frozenImages = {
    for (final item in images.entries)
      item.key: List<EpubEmbeddedImage>.unmodifiable(item.value),
  };
  final frozenTables = {
    for (final item in tables.entries)
      item.key: List<EpubTablePreview>.unmodifiable(item.value),
  };
  final headings = {for (final chapter in chapters) chapter.start: chapter};

  // Generic source-offset lookup for disjoint, sorted markup regions.
  int firstStyleAt(int offset) {
    var low = 0, high = styles.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (styles[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  int firstLinkAt(int offset) {
    var low = 0, high = links.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (links[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  EpubVisualBlock materialize(int blockIndex) {
    final meta = bounds[blockIndex];
    final runs = <EpubVisualRun>[];
    var styleIndex = firstStyleAt(meta.start);
    var linkIndex = firstLinkAt(meta.start);

    void append(int start, int end, int? segmentIndex) {
      var offset = start;
      while (offset < end) {
        while (styleIndex < styles.length &&
            styles[styleIndex].end <= offset) {
          styleIndex++;
        }
        var until = end;
        EpubInlineStyleSpan? style;
        if (styleIndex < styles.length) {
          final candidate = styles[styleIndex];
          if (candidate.start > offset) {
            if (candidate.start < until) until = candidate.start;
          } else {
            style = candidate;
            if (candidate.end < until) until = candidate.end;
          }
        }
        while (linkIndex < links.length && links[linkIndex].end <= offset) {
          linkIndex++;
        }
        int? target;
        String? auxKey;
        var footnote = false;
        if (linkIndex < links.length) {
          final link = links[linkIndex];
          if (link.start > offset) {
            if (link.start < until) until = link.start;
          } else {
            target = link.targetOffset;
            auxKey = link.auxiliaryFootnoteKey;
            footnote = link.isFootnote;
            if (link.end < until) until = link.end;
          }
        }
        if (until <= offset) {
          throw const FormatException('Non-progressing EPUB visual run');
        }
        runs.add(EpubVisualRun.fromSource(
          offset, until, source, segmentIndex,
          bold: style?.bold ?? false,
          italic: style?.italic ?? false,
          headingLevel: style?.headingLevel ?? 0,
          linkTargetOffset: target,
          auxiliaryFootnoteKey: auxKey,
          isFootnote: footnote,
        ));
        offset = until;
      }
    }

    var current = meta.start;
    var segmentIndex = firstSegmentAfter(current);
    while (current < meta.end) {
      while (segmentIndex < segments.length &&
          segments[segmentIndex].end <= current) {
        segmentIndex++;
      }
      if (segmentIndex >= segments.length ||
          segments[segmentIndex].start >= meta.end) {
        append(current, meta.end, null);
        break;
      }
      final segment = segments[segmentIndex];
      if (segment.start > current) {
        final gapEnd = segment.start < meta.end
            ? segment.start : meta.end;
        append(current, gapEnd, null);
        current = gapEnd;
        continue;
      }
      final until = segment.end < meta.end ? segment.end : meta.end;
      append(current, until, segmentIndex);
      current = until;
    }

    final semantic = runs.isNotEmpty && runs.every((r) =>
        r.headingLevel > 0 ||
        _sourceWhitespaceOnly(source, r.start, r.end));
    final chapter = headings[meta.start];
    final named = chapter != null &&
        source.substring(meta.start, meta.end)
            .replaceAll(RegExp(r'\s+'), ' ').trim() == chapter.title;
    return EpubVisualBlock(
      start: meta.start,
      end: meta.end,
      runs: List<EpubVisualRun>.unmodifiable(runs),
      chapterStart: meta.chapterStart,
      heading: semantic || named,
      firstSegmentIndex: meta.firstSegmentIndex,
      images: frozenImages[blockIndex] ?? const [],
      tables: frozenTables[blockIndex] ?? const [],
    );
  }

  // Scroll/checkpoint events need only this compact index. Avoid
  // allocating EpubVisualRun objects just to persist a visible block's
  // UTF-16 position, even on a huge book with no speech for some blocks.
  EpubVisibleReadingPosition indexedPositionForVisibleBlock(
      int index, List<SpeechSegment> playable) {
    RangeError.checkValidIndex(index, bounds);
    final metadata = bounds[index];
    final segment = metadata.firstSegmentIndex ??
        speechSegmentIndexForOffset(playable, metadata.start);
    return EpubVisibleReadingPosition(metadata.start, segment);
  }

  return EpubVisualLayout(
    ProgressiveEpubBlocks._(bounds, materialize, maxCachedBlocks),
    List<int>.unmodifiable(mapping),
    indexedBlockForSourceOffset: indexedBlockForSourceOffset,
    indexedPositionForVisibleBlock: indexedPositionForVisibleBlock,
  );
}

bool _white(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a ||
    unit == 0x0d || unit == 0xa0;
bool _sourceWhitespaceOnly(String source, int start, int end) {
  for (var i = start; i < end; i++) {
    final unit = source.codeUnitAt(i);
    final white = _white(unit) || unit == 0x0b || unit == 0x0c ||
        unit == 0x85 || unit == 0x1680 ||
        (unit >= 0x2000 && unit <= 0x200a) ||
        unit == 0x2028 || unit == 0x2029 || unit == 0x202f ||
        unit == 0x205f || unit == 0x3000 || unit == 0xfeff;
    if (!white) return false;
  }
  return true;
}
