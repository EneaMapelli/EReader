import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/library_reading_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

BookRecord record(
  String id, {
  BookFormat format = BookFormat.epub,
  BookReadingStatus status = BookReadingStatus.toRead,
  bool favorite = false,
  DateTime? opened,
}) => BookRecord(
  id: id,
  title: 'Book $id',
  localPath: '/unused/$id.epub',
  format: format,
  importedAt: DateTime.utc(2026, 10, 1),
  readingStatus: status,
  isFavorite: favorite,
  lastOpenedAt: opened,
);

void main() {
  final today = DateTime.utc(2026, 10, 30, 12);

  test('empty library is stable and never divides by zero', () {
    final stats = LibraryReadingStatistics.fromBooks([], now: today);
    expect(stats.totalBooks, 0);
    expect(stats.finishedFraction, 0);
    expect(stats.recentBooks, isEmpty);
    for (final status in BookReadingStatus.values) {
      expect(stats.countForStatus(status), 0);
    }
  });

  test('counts actual shelves/formats/favorites and distinct opened books',
      () {
    final stats = LibraryReadingStatistics.fromBooks([
      record('one', favorite: true, opened: today,
          status: BookReadingStatus.finished),
      record('two', format: BookFormat.pdf,
          status: BookReadingStatus.reading,
          opened: today.subtract(const Duration(days: 6))),
      record('three', format: BookFormat.txt,
          opened: today.subtract(const Duration(days: 20))),
      record('four'),
    ], now: today);
    expect(stats.totalBooks, 4);
    expect(stats.countForStatus(BookReadingStatus.finished), 1);
    expect(stats.countForStatus(BookReadingStatus.reading), 1);
    expect(stats.countForStatus(BookReadingStatus.toRead), 2);
    expect(stats.finishedFraction, .25);
    expect(stats.favoriteBooks, 1);
    expect(stats.everOpenedBooks, 3);
    expect(stats.openedInLastSevenDays, 2);
    expect(stats.countForFormat(BookFormat.epub), 2);
    expect(stats.countForFormat(BookFormat.pdf), 1);
    expect(stats.countForFormat(BookFormat.txt), 1);
    expect(stats.recentBooks.map((book) => book.id), ['one', 'two', 'three']);
  });

  test('inclusive seven-day boundary, excludes future clock skew', () {
    final stats = LibraryReadingStatistics.fromBooks([
      record('boundary',
          opened: today.subtract(const Duration(days: 7))),
      record('outside',
          opened: today.subtract(const Duration(days: 7, seconds: 1))),
      record('future', opened: today.add(const Duration(minutes: 1))),
    ], now: today);
    expect(stats.everOpenedBooks, 3);
    expect(stats.openedInLastSevenDays, 1);
    expect(stats.recentBooks.map((book) => book.id), ['boundary', 'outside']);
  });

  test('only five recent titles shown and source list untouched', () {
    final source = [
      for (var i = 0; i < 9; i++)
        record('book-$i', opened: today.subtract(Duration(hours: i))),
    ];
    final original = source.toList();
    final stats = LibraryReadingStatistics.fromBooks(source, now: today);
    expect(stats.recentBooks.length, 5);
    expect(stats.recentBooks.first.id, 'book-0');
    expect(stats.recentBooks.last.id, 'book-4');
    expect(source, original);
    expect(() => stats.recentBooks.clear(), throwsUnsupportedError);
    expect(() => stats.formatCounts.clear(), throwsUnsupportedError);
  });
}
