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
  });

  final String idref;
  final String title;
  final int start;
  final int end;
  final int segmentIndex;
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

/// Create the UI chapter directory against *actual* playable chunks, after
/// casting/quote processing. Empty headings and non-linear spine resources
/// have no playable segments and are omitted.
List<EpubChapter> buildEpubChapters(
    DocumentContent document, List<SpeechSegment> segments) {
  final chapters = <EpubChapter>[];
  var cursor = 0;
  for (final range in document.epubSpineRanges) {
    // Both lists are sorted by original text offsets. Walk each speech
    // segment at most once even for large EPUBs with thousands of files.
    while (cursor < segments.length &&
        segments[cursor].start < range.start) {
      cursor++;
    }
    if (cursor >= segments.length ||
        segments[cursor].start >= range.end) {
      continue;
    }
    chapters.add(EpubChapter(
      idref: range.idref,
      title: range.title.trim().isNotEmpty
          ? range.title.trim()
          : 'Chapter ${chapters.length + 1}',
      start: range.start,
      end: range.end,
      segmentIndex: cursor,
    ));
  }
  return List<EpubChapter>.unmodifiable(chapters);
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
  if (chapter == null || segment.start != chapter.start) return false;
  final normalized = segment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized == chapter.title;
}
