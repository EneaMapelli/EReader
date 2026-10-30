import 'book.dart';

/// Snapshot of existing local library metadata, NOT a session/activity log.
///
/// Reading shelves are user-set, and lastOpenedAt records only the *last*
/// reader launch. Consequently these counts must never be presented as
/// minutes read, completed pages, opening events or a daily reading streak.
class LibraryReadingStatistics {
  const LibraryReadingStatistics._({
    required this.totalBooks,
    required this.statusCounts,
    required this.formatCounts,
    required this.favoriteBooks,
    required this.everOpenedBooks,
    required this.openedInLastSevenDays,
    required this.recentBooks,
  });

  final int totalBooks;
  final Map<BookReadingStatus, int> statusCounts;
  final Map<BookFormat, int> formatCounts;
  final int favoriteBooks;
  final int everOpenedBooks;

  /// Number of distinct books whose *latest* opening was within 168 hours.
  /// This does not count sessions or books opened earlier in that interval
  /// and then opened outside it.
  final int openedInLastSevenDays;

  /// Up to five books with a known, non-future opening date, newest first.
  final List<BookRecord> recentBooks;

  int countForStatus(BookReadingStatus status) => statusCounts[status] ?? 0;
  int countForFormat(BookFormat format) => formatCounts[format] ?? 0;

  double get finishedFraction =>
      totalBooks == 0 ? 0 : countForStatus(BookReadingStatus.finished) / totalBooks;

  static LibraryReadingStatistics fromBooks(
    Iterable<BookRecord> source, {
    DateTime? now,
  }) {
    final books = source.toList(growable: false);
    final upperBound = (now ?? DateTime.now()).toUtc();
    final cutoff = upperBound.subtract(const Duration(days: 7));
    final statuses = {for (final value in BookReadingStatus.values) value: 0};
    final formats = {for (final value in BookFormat.values) value: 0};
    var favorites = 0;
    var everOpened = 0;
    var recentlyOpened = 0;
    final openedBooks = <BookRecord>[];

    for (final book in books) {
      statuses[book.readingStatus] = statuses[book.readingStatus]! + 1;
      formats[book.format] = formats[book.format]! + 1;
      if (book.isFavorite) favorites++;
      final lastOpened = book.lastOpenedAt?.toUtc();
      if (lastOpened == null) continue;
      everOpened++;
      // Ignore future clock-skew timestamps in recent activity; retain
      // them in the 'ever opened' count because they are recorded openings.
      if (lastOpened.isAfter(upperBound)) continue;
      openedBooks.add(book);
      if (!lastOpened.isBefore(cutoff)) recentlyOpened++;
    }
    openedBooks.sort((a, b) =>
        b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return LibraryReadingStatistics._(
      totalBooks: books.length,
      statusCounts: Map.unmodifiable(statuses),
      formatCounts: Map.unmodifiable(formats),
      favoriteBooks: favorites,
      everOpenedBooks: everOpened,
      openedInLastSevenDays: recentlyOpened,
      recentBooks: List.unmodifiable(openedBooks.take(5)),
    );
  }
}
