import 'book.dart';

/// Library-only view controls. Filtering never changes SQLite records.
enum LibrarySortOrder { recentlyImported, titleAscending, titleDescending, authorAscending, seriesAscending, format }

List<BookRecord> filterAndSortLibraryBooks(
  Iterable<BookRecord> books, {
  String query = '',
  BookFormat? format,
  LibrarySortOrder sort = LibrarySortOrder.recentlyImported,
}) {
  final needle = query.trim().toLowerCase();
  final matching = <BookRecord>[
    for (final book in books)
      if ((format == null || book.format == format) &&
          (needle.isEmpty ||
              book.title.toLowerCase().contains(needle) ||
              (book.author?.toLowerCase().contains(needle) ?? false) ||
              (book.series?.toLowerCase().contains(needle) ?? false)))
        book,
  ];
  int compare(BookRecord a, BookRecord b) {
    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    switch (sort) {
      case LibrarySortOrder.recentlyImported:
        final date = b.importedAt.compareTo(a.importedAt);
        if (date != 0) return date;
        break;
      case LibrarySortOrder.titleAscending:
        if (title != 0) return title;
        break;
      case LibrarySortOrder.titleDescending:
        if (title != 0) return -title;
        break;
      case LibrarySortOrder.authorAscending:
        final author = (a.author ?? '').toLowerCase().compareTo(
          (b.author ?? '').toLowerCase());
        if (author != 0) return author;
        if (title != 0) return title;
        break;
      case LibrarySortOrder.seriesAscending:
        final series = (a.series ?? '').toLowerCase().compareTo(
          (b.series ?? '').toLowerCase());
        if (series != 0) return series;
        if (title != 0) return title;
        break;
      case LibrarySortOrder.format:
        final byFormat = a.format.name.compareTo(b.format.name);
        if (byFormat != 0) return byFormat;
        if (title != 0) return title;
        break;
    }
    // Stable ties avoid flickering when titles or timestamps coincide.
    return a.id.compareTo(b.id);
  }
  matching.sort(compare);
  return List<BookRecord>.unmodifiable(matching);
}
