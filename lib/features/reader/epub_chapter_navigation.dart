import '../../data/book_decoder.dart';
import '../../domain/speech_segment.dart';

/// A navigable OPF spine item. Chapters are *not* assumed to be equivalent
/// to EPUB NCX/navigation entries: these are the readable XHTML spine units.
/// Indices always refer to the exact current ReaderPlayer segment list.
class EpubChapter {
  const EpubChapter({
    required this.idref,
    required this.title,
    required this.start,
    required this.end,
    required this.segmentIndex,
    this.hasSpeech = true,
  });

  final String idref;
  final String title;
  final int start;
  final int end;
  /// Index of the first playable clip in or following the source range.
  /// segments.length means no later narration exists (silent final spine).
  final int segmentIndex;
  /// Whether this spine item itself contains a spoken TTS chunk.
  final bool hasSpeech;
}

/// Split TTS input at EPUB spine boundaries. This is crucial: a single audio
/// segment must not start in the previous chapter and straddle the start
/// of the next one, otherwise "go to chapter" can restart earlier text.
/// Text, speaker annotations and persisted anchors retain global UTF-16 offsets.
List<SpeechSegment> segmentEpubSpine(DocumentContent document) {
  if (document.epubSpineRanges.isEmpty) {
    return segmentSpeech(document.text);
  }
  final result = <SpeechSegment>[];
  var lastEnd = 0;
  for (final range in document.epubSpineRanges) {
    if (range.start < lastEnd || range.end < range.start ||
        range.end > document.text.length) {
      throw const FormatException('Invalid EPUB spine text ranges');
    }
    // Avoid a full second copy of each large XHTML spine item's text.
    // segmentSpeechRange returns the same segments with global offsets.
    result.addAll(segmentSpeechRange(
      document.text, start: range.start, end: range.end,
    ));
    lastEnd = range.end;
  }
  return result;
}

/// Preserve EVERY OPF spine section in visual navigation, including
/// sections whose contents are illustrations, whitespace or unspoken text.
/// The voice cursor is only a nearby NEXT playable segment; the exact
/// visual/source destination is the chapter.start value, not segment.start.
///
/// If there is no next playable segment, the cursor uses segments.length
/// (completed speech) rather than replaying text from the prior chapter.
List<EpubChapter> buildEpubChapters(
    DocumentContent document, List<SpeechSegment> segments) {
  final chapters = <EpubChapter>[];
  var cursor = 0;
  var lastEnd = 0;
  for (final range in document.epubSpineRanges) {
    if (range.start < lastEnd || range.end < range.start ||
        range.end > document.text.length) {
      throw const FormatException('Invalid EPUB chapter source ranges');
    }
    // Every TTS segment was already split at OPF spine boundaries;
    // a section with no segment keeps its exact source offset.
    while (cursor < segments.length &&
        segments[cursor].start < range.start) {
      cursor++;
    }
    final hasSpeech = cursor < segments.length &&
        segments[cursor].start < range.end;
    chapters.add(EpubChapter(
      idref: range.idref,
      title: range.title.trim().isNotEmpty
          ? range.title.trim()
          : 'Chapter ${chapters.length + 1}',
      start: range.start,
      end: range.end,
      segmentIndex: cursor,
      hasSpeech: hasSpeech,
    ));
    lastEnd = range.end;
  }
  return List<EpubChapter>.unmodifiable(chapters);
}

/// An Android media action targets a spoken chapter *and* the original
/// visual EPUB section. Silent illustration-only spines may share a UTF-16
/// source offset, so a source offset alone is not a unique visual bookmark.
class EpubMediaChapterTarget {
  const EpubMediaChapterTarget({
    required this.sourceOffset,
    this.silentSpineIdref,
  });

  final int sourceOffset;
  final String? silentSpineIdref;
}

/// Build one immutable source lookup when the reader opens, rather than
/// rescanning every OPF section for each lock-screen Next/Previous.
/// A completed narration may still have trailing illustrated-only spines;
/// target the FIRST such section, not the last same-offset illustration.
Map<int, EpubMediaChapterTarget> buildEpubMediaChapterTargets(
    List<EpubChapter> chapters, int speechSegmentCount,
    int sourceLength) {
  final targets = <int, EpubMediaChapterTarget>{};
  var lastSpokenChapter = -1;
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    if (chapter.hasSpeech &&
        chapter.segmentIndex >= 0 &&
        chapter.segmentIndex < speechSegmentCount) {
      lastSpokenChapter = i;
      targets.putIfAbsent(chapter.segmentIndex, () =>
          EpubMediaChapterTarget(sourceOffset: chapter.start));
    }
  }
  EpubChapter? trailingSilent;
  for (var i = lastSpokenChapter + 1; i < chapters.length; i++) {
    if (!chapters[i].hasSpeech) {
      trailingSilent = chapters[i];
      break;
    }
  }
  targets[speechSegmentCount] = trailingSilent == null
      ? EpubMediaChapterTarget(sourceOffset: sourceLength)
      : EpubMediaChapterTarget(
          sourceOffset: trailingSilent.start,
          silentSpineIdref: trailingSilent.idref,
        );
  return Map<int, EpubMediaChapterTarget>.unmodifiable(targets);
}

/// Resolve a verified EPUB source target to the containing/next playable
/// TTS segment. Sorted source-aligned segments make fragment jumps O(log N).
/// The exact target offset itself is persisted separately by the reader.
int speechSegmentIndexForOffset(List<SpeechSegment> segments, int offset) {
  if (segments.isEmpty) return -1;
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
  return low < segments.length ? low : segments.length - 1;
}

/// Resolve a source-exact VISUAL destination to the next narrated clip.
/// Unlike an ordinary "jump to previous playable clip" action, a link to
/// trailing non-narratable EPUB content MUST NOT replay the last sentence.
/// The persisted visual offset remains separate from this speech cursor.
int speechSourceDestinationIndexForOffset(
    List<SpeechSegment> segments, int offset) {
  if (segments.isEmpty) return -1;
  if (offset >= segments.last.end) return segments.length;
  return speechSegmentIndexForOffset(segments, offset);
}

/// Restore a saved spoken cursor, keeping an already completed book
/// completed. Unlike an explicit bookmark/TOC jump, a checkpoint at or
/// beyond the last utterance must NOT replay the final clip on opening.
///
/// A paragraph gap between chunks resolves to the next audible chunk;
/// a source offset inside an utterance restarts only that utterance.
/// Empty or whitespace-only documents have no playable cursor.
int speechResumeIndexForOffset(List<SpeechSegment> segments, int offset) {
  if (segments.isEmpty) return -1;
  if (offset >= segments.last.end) return segments.length;
  return speechSegmentIndexForOffset(segments, offset);
}

/// Chapters are ordered by OPF spine source start. A binary lookup
/// avoids rescanning thousands of navigation items during audio follow.
int chapterIndexForOffset(List<EpubChapter> chapters, int offset) {
  if (chapters.isEmpty) return -1;
  var low = 0;
  var high = chapters.length;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (chapters[mid].start <= offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low == 0 ? 0 : low - 1;
}


/// Mark only a *source-exact, standalone* chapter heading as semantic
/// heading text. Never insert an extra copy of the title into the book.
bool isStandaloneChapterHeading(EpubChapter? chapter, SpeechSegment segment) {
  if (chapter == null || !chapter.hasSpeech ||
      segment.start != chapter.start) return false;
  final normalized = segment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized == chapter.title;
}
