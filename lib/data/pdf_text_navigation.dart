import 'book_decoder.dart';

/// Maps between physical PDF pages and offsets in the extracted text layer.
/// Visual pages and spoken text checkpoints remain different concepts:
/// scanned/blank pages need not have any text span.
///
/// Returning null means there is no selectable text to speak; no OCR or
/// synthetic text is introduced by these helpers.
int? pdfTextOffsetForVisualPage(
  List<PdfPageRange> ranges,
  int pageNumber,
) {
  if (pageNumber < 1 || ranges.isEmpty) return null;
  for (final range in ranges) {
    if (range.pageNumber >= pageNumber && range.end > range.start) {
      return range.start;
    }
  }
  // If the selected page and everything after it are image-only, do
  // NOT silently narrate an earlier physical page (which the user did not
  // choose). The caller can explain that no text is available here.
  return null;
}

/// Physical page for a saved spoken-text offset. Includes pages omitted from
/// the text layer only indirectly: the next containing page is used.
int? pdfVisualPageForTextOffset(
  List<PdfPageRange> ranges,
  int sourceOffset,
) {
  if (sourceOffset < 0 || ranges.isEmpty) return null;
  for (final range in ranges) {
    if (sourceOffset < range.end) return range.pageNumber;
  }
  return ranges.last.pageNumber;
}
