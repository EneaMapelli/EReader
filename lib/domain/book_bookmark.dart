import 'reading_anchor.dart';

/// User-defined named position in an imported book. The source-relative
/// anchor is preferred; global UTF-16 offset supports legacy/extraction fallback.
class BookBookmark {
  const BookBookmark({
    required this.id,
    required this.bookId,
    required this.title,
    required this.globalOffset,
    required this.createdAt,
    this.anchor,
  });

  final String id;
  final String bookId;
  final String title;
  final int globalOffset;
  final DateTime createdAt;
  final ReadingAnchor? anchor;

  void validate() {
    if (id.isEmpty || id.length > 128 || bookId.isEmpty) {
      throw const FormatException('Bookmark ID and book ID are required');
    }
    if (title.trim().isEmpty || title.length > 200) {
      throw const FormatException('Bookmark title must have 1-200 characters');
    }
    if (globalOffset < 0) {
      throw const FormatException('Bookmark position must be nonnegative');
    }
  }
}
