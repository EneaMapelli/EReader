import '../../data/book_decoder.dart';
import '../../data/epub_inline_style.dart';
import '../../data/epub_embedded_content.dart';
import '../../domain/speech_segment.dart';
import 'epub_chapter_navigation.dart';

/// An unmodified substring of the extracted EPUB text, optionally covered
/// by one of the speech engine's original, source-aligned segments.
class EpubVisualRun {
  /// Explicit text remains supported by existing fixtures and callers.
  const EpubVisualRun(this.start, this.end, String text, this.segmentIndex, {
    this.bold = false,
    this.italic = false,
    this.headingLevel = 0,
    this.linkTargetOffset,
    this.auxiliaryFootnoteKey,
    this.isFootnote = false,
  }) : _text = text, _source = null;

  /// Keep source offsets rather than allocating thousands of overlapping
  /// substring copies before a paragraph is shown on screen.
  EpubVisualRun.fromSource(
    this.start, this.end, String source, this.segmentIndex, {
    this.bold = false,
    this.italic = false,
    this.headingLevel = 0,
    this.linkTargetOffset,
    this.auxiliaryFootnoteKey,
    this.isFootnote = false,
  }) : _source = source, _text = null;

  final int start;
  final int end;
  final String? _text;
  final String? _source;
  String get text => _text ?? _source!.substring(start, end);
  final int? segmentIndex;
  final bool bold;
  final bool italic;
  final int headingLevel;
  final int? linkTargetOffset;
  final String? auxiliaryFootnoteKey;
  final bool isFootnote;

  /// A source-exact visual fragment. Slicing does NOT create a new speech
  /// segment or alter link/footnote/speaker styling. For source-backed runs
  /// it also avoids copying the underlying text until Flutter paints it.
  EpubVisualRun visualSlice(int from, int to) {
    if (from < start || to > end || from >= to) {
      throw RangeError.range(from, start, end, 'from');
    }
    if (from == start && to == end) return this;
    final visible = _source == null
        ? EpubVisualRun(from, to,
            _text!.substring(from - start, to - start), segmentIndex,
            bold: bold, italic: italic, headingLevel: headingLevel,
            linkTargetOffset: linkTargetOffset,
            auxiliaryFootnoteKey: auxiliaryFootnoteKey,
            isFootnote: isFootnote)
        : EpubVisualRun.fromSource(from, to, _source!, segmentIndex,
            bold: bold, italic: italic, headingLevel: headingLevel,
            linkTargetOffset: linkTargetOffset,
            auxiliaryFootnoteKey: auxiliaryFootnoteKey,
            isFootnote: isFootnote);
    return visible;
  }
}

/// A display-only row in the original XHTML text/image sequence. Each
/// image is embedded AT its normalized source offset, not appended after
/// the whole paragraph. No source characters, speech chunks or anchors
/// are inserted by this presentation-only structure.
class EpubVisualFlowItem {
  const EpubVisualFlowItem.text(this.runs)
      : image = null, table = null;
  const EpubVisualFlowItem.image(this.image)
      : runs = const [], table = null;
  const EpubVisualFlowItem.table(this.table)
      : runs = const [], image = null;

  final List<EpubVisualRun> runs;
  final EpubEmbeddedImage? image;
  /// Non-destructive, user-expanded preview after original table source.
  final EpubTablePreview? table;
}

/// Stable source-order interleave of original text, local images and an
/// optional bounded table preview. Tables stay in the TTS/source text; their
/// visual previews are collapsed by default and anchored at table.end,
/// so a preview does not render at the bottom of an unrelated paragraph.
/// Equal-offset images preserve extraction order; table previews follow
/// the tied images. No synthetic text is passed to TTS or search.
List<EpubVisualFlowItem> epubVisualFlow(EpubVisualBlock block) {
  if (block.images.isEmpty && block.tables.isEmpty) {
    return block.runs.isEmpty
        ? const []
        : [EpubVisualFlowItem.text(block.runs)];
  }
  final events = <({
    int offset, int kind, int order,
    EpubEmbeddedImage? image, EpubTablePreview? table
  })>[
    for (var i = 0; i < block.images.length; i++)
      (offset: block.images[i].offset, kind: 0, order: i,
       image: block.images[i], table: null),
    for (var i = 0; i < block.tables.length; i++)
      (offset: block.tables[i].end, kind: 1, order: i,
       image: null, table: block.tables[i]),
  ]..sort((a, b) {
    var order = a.offset.compareTo(b.offset);
    if (order != 0) return order;
    order = a.kind.compareTo(b.kind);
    return order != 0 ? order : a.order.compareTo(b.order);
  });
  final pieces = <EpubVisualFlowItem>[];
  final pendingText = <EpubVisualRun>[];
  final runs = List<EpubVisualRun>.of(block.runs);
  var cursor = 0;

  void emitText() {
    if (pendingText.isEmpty) return;
    pieces.add(EpubVisualFlowItem.text(
        List<EpubVisualRun>.unmodifiable(pendingText)));
    pendingText.clear();
  }

  for (final event in events) {
    var position = event.offset.clamp(block.start, block.end).toInt();
    // A malformed image offset inside an emoji surrogate pair must not
    // cause two invalid Flutter text spans. The already source-aligned
    // table-end position is handled by the same safeguard.
    for (var i = cursor; i < runs.length; i++) {
      final run = runs[i];
      if (run.start >= position) break;
      if (run.end <= position) continue;
      final runText = run.text;
      final relative = position - run.start;
      if (relative > 0 && relative < runText.length) {
        final before = runText.codeUnitAt(relative - 1);
        final after = runText.codeUnitAt(relative);
        if (before >= 0xd800 && before <= 0xdbff &&
            after >= 0xdc00 && after <= 0xdfff) {
          position++;
        }
      }
      break;
    }
    while (cursor < runs.length) {
      final run = runs[cursor];
      if (run.start >= position) break;
      if (run.end <= position) {
        pendingText.add(run);
        cursor++;
      } else {
        // The fragment is split for painting, never for TTS/casting.
        pendingText.add(run.visualSlice(run.start, position));
        runs[cursor] = run.visualSlice(position, run.end);
        break;
      }
    }
    emitText();
    if (event.image case final picture?) {
      pieces.add(EpubVisualFlowItem.image(picture));
    } else if (event.table case final preview?) {
      pieces.add(EpubVisualFlowItem.table(preview));
    }
  }
  while (cursor < runs.length) {
    pendingText.add(runs[cursor++]);
  }
  emitText();
  return List<EpubVisualFlowItem>.unmodifiable(pieces);
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
    this.visualOnlySectionTitle,
  });

  final int start;
  final int end;
  final List<EpubVisualRun> runs;
  final bool chapterStart;
  final bool heading;
  final int? firstSegmentIndex;
  final List<EpubEmbeddedImage> images;
  final List<EpubTablePreview> tables;
  /// Display-only, for an OPF item whose XHTML produced no readable text.
  /// This label is not present in source text and must NEVER reach TTS.
  final String? visualOnlySectionTitle;

  String get text => runs.map((run) => run.text).join();
}

/// The visible reading checkpoint and the nearest playable speech cursor
/// are deliberately independent: an image caption can be visible even
/// when it has no TTS speech segment of its own.
class EpubVisibleReadingPosition {
  const EpubVisibleReadingPosition(this.sourceOffset, this.segmentIndex);

  final int sourceOffset;
  final int segmentIndex;
}

class EpubVisualLayout {
  const EpubVisualLayout(this.blocks, this.segmentToBlock, {
    int Function(int)? indexedBlockForSourceOffset,
    Map<String, int> spineBlockIndices = const {},
    Map<int, String> silentSpineIdsByBlock = const {},
    EpubVisibleReadingPosition Function(int, List<SpeechSegment>)?
        indexedPositionForVisibleBlock,
  }) : _indexedBlockForSourceOffset = indexedBlockForSourceOffset,
       _spineBlockIndices = spineBlockIndices,
       _silentSpineIdsByBlock = silentSpineIdsByBlock,
       _indexedPositionForVisibleBlock = indexedPositionForVisibleBlock;

  final List<EpubVisualBlock> blocks;
  final List<int> segmentToBlock;
  final int Function(int)? _indexedBlockForSourceOffset;
  final Map<String, int> _spineBlockIndices;
  final Map<int, String> _silentSpineIdsByBlock;

  /// This block has no text source coordinates unique to itself.
  /// Never infer its identity solely from its (possibly shared) offset.
  String? silentSpineIdrefForBlock(int index) =>
      _silentSpineIdsByBlock[index];

  /// Empty XHTML spine entries may share a source offset with the following
  /// section. Only the OPF idref uniquely selects the correct visual block.
  int blockForSpine(String idref, int sourceOffset) =>
      _spineBlockIndices[idref] ?? blockForSourceOffset(sourceOffset);
  final EpubVisibleReadingPosition Function(int, List<SpeechSegment>)?
      _indexedPositionForVisibleBlock;

  /// Exact source jumps also resolve unspoken internal links and notes.
  /// The progressive callback searches its index without building rich runs.
  int blockForSourceOffset(int sourceOffset) {
    if (blocks.isEmpty) return 0;
    final indexed = _indexedBlockForSourceOffset;
    if (indexed != null) return indexed(sourceOffset);
    var low = 0, high = blocks.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (blocks[mid].end <= sourceOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < blocks.length ? low : blocks.length - 1;
  }

  /// Reading progress follows the actual visible paragraph, even for
  /// images, captions and otherwise non-spoken EPUB sections. The audio
  /// cursor still points to a playable segment where available.
  EpubVisibleReadingPosition positionForVisibleBlock(
      int blockIndex, List<SpeechSegment> segments) {
    RangeError.checkValidIndex(blockIndex, blocks);
    final indexed = _indexedPositionForVisibleBlock;
    if (indexed != null) return indexed(blockIndex, segments);
    final block = blocks[blockIndex];
    final playable = block.firstSegmentIndex ??
        speechSourceDestinationIndexForOffset(segments, block.start);
    return EpubVisibleReadingPosition(block.start, playable);
  }

  int blockForSegment(int segmentIndex) {
    if (blocks.isEmpty || segmentToBlock.isEmpty) return 0;
    final index = segmentIndex.clamp(0, segmentToBlock.length - 1).toInt();
    final mapped = segmentToBlock[index];
    return mapped >= 0 ? mapped : 0;
  }
}

/// A small UI-independent guard for precise EPUB bookmarks. A link/TOC
/// target or persisted source anchor may be inside an unspoken paragraph.
/// The virtual list's initial position notification is not user navigation:
/// do not rewrite the exact source offset to the first speech segment.
/// Only a DIFFERENT visible paragraph or explicit speech playback releases
/// the guard. This object never stores text or mutates SQLite.
class EpubVisualSourceCheckpoint {
  EpubVisualSourceCheckpoint({
    this.pendingTargetTimeout = const Duration(seconds: 5),
  }) : assert(!pendingTargetTimeout.isNegative);

  /// A failed/stale jump must not suppress genuine manual scrolling forever.
  /// Stopwatch is monotonic and runs only while awaiting the first target.
  final Duration pendingTargetTimeout;
  final Stopwatch _targetWait = Stopwatch();
  int? _offset;
  int? _targetBlockIndex;
  bool _awaitingTarget = false;

  int? get offset => _offset;

  /// [awaitTarget] is used for a programmatic jump or initial restore:
  /// Flutter may briefly report the PREVIOUS viewport while jumpTo or
  /// initialScrollIndex is still being laid out.
  void hold(int? sourceOffset, {
    bool awaitTarget = false,
    int? targetBlockIndex,
  }) {
    _offset = sourceOffset;
    _targetBlockIndex = sourceOffset == null ? null : targetBlockIndex;
    _awaitingTarget = sourceOffset != null && awaitTarget;
    _targetWait
      ..stop()
      ..reset();
    if (_awaitingTarget) _targetWait.start();
  }

  void clear() {
    _offset = null;
    _targetBlockIndex = null;
    _awaitingTarget = false;
    _targetWait
      ..stop()
      ..reset();
  }

  /// Preserve a precise checkpoint while its target paragraph is visible,
  /// even if that paragraph is too short to be the FIRST item in the viewport.
  /// Ignore a stale previous viewport before the target is first observed.
  /// Once observed, navigating until it is fully out of view releases it.
  bool preserveOnVisibleBlocks(
      Iterable<int> visibleBlocks, EpubVisualLayout layout) {
    final held = _offset;
    if (held == null) return false;
    final targetBlock = _targetBlockIndex ??
        layout.blockForSourceOffset(held);
    if (visibleBlocks.contains(targetBlock)) {
      _awaitingTarget = false;
      _targetWait.stop();
      return true;
    }
    if (_awaitingTarget &&
        _targetWait.elapsed < pendingTargetTimeout) {
      return true;
    }
    // The jump target is no longer visible, or never arrived within
    // the bounded grace period. Real scrolling must be allowed again.
    clear();
    return false;
  }

  /// Convenience for a single visible paragraph (unit regressions).
  bool preserveOnVisibleBlock(int blockIndex, EpubVisualLayout layout) =>
      preserveOnVisibleBlocks([blockIndex], layout);
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
    // Run the regex on the canonical source with a starting index.
    // Copying each whole chapter first temporarily doubles text memory.
    for (final match in newline.allMatches(document.text, range.start)) {
      if (match.start >= range.end || match.end > range.end) break;
      boundaries.add(match.end);
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
  // Do not traverse all auxiliary previews for every hyperlink: books
  // with thousands of note references would otherwise take O(L * N).
  final auxiliaryKeys = <String>{
    for (final note in document.epubAuxiliaryFootnotePreviews) note.key,
  };
  var lastLinkEnd = 0;
  for (final link in links) {
    final target = link.targetOffset;
    final auxiliary = link.auxiliaryFootnoteKey;
    final validSpineTarget = target != null && target >= 0 &&
        target < source.length && auxiliary == null;
    final validAuxiliary = target == null && link.isFootnote &&
        auxiliary != null && auxiliary.isNotEmpty &&
        auxiliaryKeys.contains(auxiliary);
    if (link.start < lastLinkEnd || link.end <= link.start ||
        link.end > source.length ||
        !(validSpineTarget || validAuxiliary)) {
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
  final silentSpineBlocks = <String, int>{};
  final spineBlockBounds = <String, ({int first, int last})>{};
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
        String? auxiliaryFootnoteKey;
        var isFootnote = false;
        if (linkCursor < links.length) {
          final link = links[linkCursor];
          if (link.start > offset) {
            if (link.start < until) until = link.start;
          } else {
            linkTarget = link.targetOffset;
            auxiliaryFootnoteKey = link.auxiliaryFootnoteKey;
            isFootnote = link.isFootnote;
            if (link.end < until) until = link.end;
          }
        }
        if (until <= offset) {
          throw const FormatException('Non-progressing EPUB visual metadata');
        }
        runs.add(EpubVisualRun.fromSource(
          offset, until, source, segmentIndex,
          bold: style?.bold ?? false,
          italic: style?.italic ?? false,
          headingLevel: style?.headingLevel ?? 0,
          linkTargetOffset: linkTarget,
          auxiliaryFootnoteKey: auxiliaryFootnoteKey,
          isFootnote: isFootnote,
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
    // Do not materialize every spoken substring merely to check whether
    // a block has semantic heading styling.
    final semanticHeading = runs.isNotEmpty &&
        runs.every((run) => run.headingLevel > 0 ||
            _sourceWhitespaceOnly(source, run.start, run.end));
    final publisherHeading = chapter != null &&
        source.substring(start, end)
            .replaceAll(RegExp(r'\s+'), ' ').trim() == chapter.title;
    blocks.add(EpubVisualBlock(
      start: start,
      end: end,
      runs: List.unmodifiable(runs),
      chapterStart: chapterStart,
      heading: semanticHeading || publisherHeading,
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
      // Prefer a whitespace break, then backtrack away from a compound
      // Unicode character. Shared with TTS and the progressive renderer.
      var split = target;
      for (var j = target; j > cursor + maxBlockChars ~/ 2; j--) {
        if (_visualWhitespace(source.codeUnitAt(j - 1))) {
          split = j;
          break;
        }
      }
      split = backtrackCommonGraphemeBoundary(
          source, start: cursor, end: split);
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
    final spineFirstBlock = blocks.length;
    if (spine.start == spine.end) {
      silentSpineBlocks[spine.idref] = blocks.length;
      blocks.add(EpubVisualBlock(
        start: spine.start, end: spine.end, runs: const [],
        chapterStart: true, heading: false, firstSegmentIndex: null,
        visualOnlySectionTitle: spine.title.trim().isEmpty
            ? 'Illustrated section' : spine.title.trim(),
      ));
      spineBlockBounds[spine.idref] = (
        first: spineFirstBlock, last: blocks.length - 1);
      continue;
    }
    var cursor = spine.start;
    var isFirst = true;
    // Scan the existing string directly. Whole-spine substrings are
    // expensive for large EPUB volumes and add no useful information.
    for (final match in doubleNewline.allMatches(source, spine.start)) {
      if (match.start >= spine.end || match.end > spine.end) break;
      final until = match.start;
      if (until > cursor) {
        addBounded(cursor, until, isFirst);
        isFirst = false;
      }
      cursor = match.end;
    }
    if (cursor < spine.end) {
      addBounded(cursor, spine.end, isFirst);
    }
    if (blocks.length > spineFirstBlock) {
      spineBlockBounds[spine.idref] = (
        first: spineFirstBlock, last: blocks.length - 1);
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
    final owner = image.spineIdref == null
        ? null : spineBlockBounds[image.spineIdref];
    final nearest = findBlock(image.offset);
    final block = owner == null || nearest < 0
        ? nearest : nearest.clamp(owner.first, owner.last).toInt();
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
  // Most EPUBs have no eligible images/table previews. In that case,
  // reuse the original block objects and avoid a second complete block
  // graph. With overlays, only materialize changed paragraph objects.
  if (imageByBlock.isEmpty && tablesByBlock.isEmpty) {
    return EpubVisualLayout(
      List.unmodifiable(blocks),
      List.unmodifiable(mapping),
      spineBlockIndices: Map<String, int>.unmodifiable(silentSpineBlocks),
      silentSpineIdsByBlock: Map<int, String>.unmodifiable({
        for (final entry in silentSpineBlocks.entries)
          entry.value: entry.key,
      }),
    );
  }
  final enriched = List<EpubVisualBlock>.of(blocks);
  final affected = <int>{...imageByBlock.keys, ...tablesByBlock.keys};
  for (final index in affected) {
    final block = blocks[index];
    enriched[index] = EpubVisualBlock(
      start: block.start, end: block.end,
      runs: block.runs,
      chapterStart: block.chapterStart,
      heading: block.heading,
      firstSegmentIndex: block.firstSegmentIndex,
      images: List.unmodifiable(imageByBlock[index] ?? const []),
      tables: List.unmodifiable(tablesByBlock[index] ?? const []),
      visualOnlySectionTitle: block.visualOnlySectionTitle,
    );
  }
  return EpubVisualLayout(
    List.unmodifiable(enriched),
    List.unmodifiable(mapping),
    spineBlockIndices: Map<String, int>.unmodifiable(silentSpineBlocks),
    silentSpineIdsByBlock: Map<int, String>.unmodifiable({
      for (final entry in silentSpineBlocks.entries)
        entry.value: entry.key,
    }),
  );
}

bool _sourceWhitespaceOnly(String source, int start, int end) {
  for (var i = start; i < end; i++) {
    final unit = source.codeUnitAt(i);
    // Keep Dart trim-style Unicode whitespace semantics without making
    // a substring for every run just to inspect heading boundaries.
    final whitespace = _visualWhitespace(unit) ||
        unit == 0x0b || unit == 0x0c || unit == 0x85 ||
        unit == 0x1680 || (unit >= 0x2000 && unit <= 0x200a) ||
        unit == 0x2028 || unit == 0x2029 || unit == 0x202f ||
        unit == 0x205f || unit == 0x3000 || unit == 0xfeff;
    if (!whitespace) return false;
  }
  return true;
}

bool _visualWhitespace(int ch) =>
    ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 0xa0;

