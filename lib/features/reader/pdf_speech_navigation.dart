import '../../data/book_decoder.dart';
import '../../domain/speech_segment.dart';

/// Speak each extracted PDF page independently. A shared TTS chunk across
/// page boundaries would be attributed to only its first page, breaking
/// page-anchored progress and some multi-voice assignments.
///
/// Text extraction already uses physical page order and a canonical global
/// UTF-16 source. Splitting here NEVER rewrites it or infers layout order.
/// Image-only/empty pages have no text range and cannot be narrated.
List<SpeechSegment> segmentPdfPages(DocumentContent document, {
  int maxChars = 400,
}) {
  final pages = document.pdfPageRanges;
  if (pages.isEmpty) return segmentSpeech(document.text,
      maxChars: maxChars);
  final segments = <SpeechSegment>[];
  var lastEnd = 0;
  for (final page in pages) {
    if (page.pageNumber < 1 || page.start < lastEnd ||
        page.end <= page.start || page.end > document.text.length) {
      throw const FormatException('Invalid physical PDF text page ranges');
    }
    // A synthetic page separator (typically two newlines) is not
    // narratable. Page offsets stay GLOBAL for bookmarks and cast tags.
    if (document.text.substring(lastEnd, page.start).trim().isNotEmpty) {
      throw const FormatException('PDF page separator contains text');
    }
    segments.addAll(segmentSpeechRange(document.text,
      start: page.start, end: page.end, maxChars: maxChars));
    lastEnd = page.end;
  }
  if (document.text.substring(lastEnd).trim().isNotEmpty) {
    throw const FormatException('PDF text extends beyond page ranges');
  }
  return List<SpeechSegment>.unmodifiable(segments);
}

/// Quotation carryover must reset at each physical PDF page. A truncated
/// quote on one page is not evidence that another page has the same speaker.
List<int> pdfSpeechQuoteResetOffsets(DocumentContent document) =>
    List<int>.unmodifiable([
      for (final page in document.pdfPageRanges.skip(1)) page.start,
    ]);
