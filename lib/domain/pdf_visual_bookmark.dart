/// A saved *physical* page in a PDF, independent of any speech/text anchor.
/// Usable with scanned documents that contain no extractable text.
class PdfVisualBookmark {
  const PdfVisualBookmark({
    required this.id,
    required this.bookId,
    required this.title,
    required this.pageNumber,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String title;
  final int pageNumber;
  final DateTime createdAt;

  void validate() {
    if (id.trim().isEmpty || id.length > 160 ||
        bookId.trim().isEmpty || bookId.length > 160 ||
        title.trim().isEmpty || title.length > 200 ||
        title.runes.any((r) => r < 32 || r == 127) ||
        pageNumber < 1 || pageNumber > 100000) {
      throw const FormatException('Invalid visual PDF bookmark');
    }
  }
}
