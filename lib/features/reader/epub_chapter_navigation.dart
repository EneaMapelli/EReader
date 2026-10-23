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
    final chapterText = document.text.substring(range.start, range.end);
    for (final part in segmentSpeech(chapterText)) {
      result.add(SpeechSegment(
        range.start + part.start,
        range.start + part.end,
        part.text,
      ));
    }
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

int chapterIndexForOffset(List<EpubChapter> chapters, int offset) {
  if (chapters.isEmpty) return -1;
  for (var i = chapters.length - 1; i >= 0; i--) {
    if (offset >= chapters[i].start) return i;
  }
  return 0;
}
