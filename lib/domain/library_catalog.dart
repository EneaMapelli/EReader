import 'book.dart';
import 'library_search_query.dart';

/// Library-only view controls. Filtering never changes SQLite records.
enum LibrarySortOrder {
  recentlyImported,
  recentlyOpened,
  titleAscending,
  titleDescending,
  authorAscending,
  seriesAscending,
  format,
  favoritesFirst,
  readingStatus,
}

/// Opening a reader is different from advancing narration or finishing a book.
/// Filtering uses only the existing explicit-open timestamp in SQLite.
enum LibraryActivityFilter { all, opened, neverOpened }

List<BookRecord> filterAndSortLibraryBooks(
  Iterable<BookRecord> books, {
  String query = '',
  BookFormat? format,
  LibraryActivityFilter activity = LibraryActivityFilter.all,
  LibrarySortOrder sort = LibrarySortOrder.recentlyImported,
  bool favoritesOnly = false,
  BookReadingStatus? readingStatus,
  Set<String>? collectionBookIds,
}) {
  // Compile the query once per rebuild, not once per catalog item.
  final search = LibrarySearchQuery.parse(query);
  final matching = <BookRecord>[
    for (final book in books)
      if ((collectionBookIds == null || collectionBookIds.contains(book.id)) &&
          (readingStatus == null || book.readingStatus == readingStatus) &&
          (!favoritesOnly || book.isFavorite) &&
          (format == null || book.format == format) &&
          (activity == LibraryActivityFilter.all ||
              (activity == LibraryActivityFilter.opened &&
                  book.lastOpenedAt != null) ||
              (activity == LibraryActivityFilter.neverOpened &&
                  book.lastOpenedAt == null)) &&
          search.matches(book))
        book,
  ];
  int compare(BookRecord a, BookRecord b) {
    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    switch (sort) {
      case LibrarySortOrder.recentlyOpened:
        final aOpened = a.lastOpenedAt;
        final bOpened = b.lastOpenedAt;
        if (aOpened != null && bOpened != null) {
          final byOpen = bOpened.compareTo(aOpened);
          if (byOpen != 0) return byOpen;
        } else if (aOpened != null) {
          return -1;
        } else if (bOpened != null) {
          return 1;
        }
        // Unopened and equal-timestamp books remain deterministic.
        final imported = b.importedAt.compareTo(a.importedAt);
        if (imported != 0) return imported;
        break;
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
      case LibrarySortOrder.readingStatus:
        // Actively reading first, then queued books, then completed shelf.
        int rank(BookReadingStatus status) => switch (status) {
          BookReadingStatus.reading => 0,
          BookReadingStatus.toRead => 1,
          BookReadingStatus.finished => 2,
        };
        final byShelf = rank(a.readingStatus).compareTo(rank(b.readingStatus));
        if (byShelf != 0) return byShelf;
        if (title != 0) return title;
        break;
      case LibrarySortOrder.favoritesFirst:
        if (a.isFavorite != b.isFavorite) {
          return a.isFavorite ? -1 : 1;
        }
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
