import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/library_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final books = <BookRecord>[
    BookRecord(id: 'b', title: 'Zulu', localPath: '/z',
        format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 24),
        progressOffset: 12),
    BookRecord(id: 'c', title: 'alpha', localPath: '/a',
        format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 25)),
    BookRecord(id: 'a', title: 'Alpha', localPath: '/b',
        format: BookFormat.pdf, importedAt: DateTime.utc(2026, 10, 25)),
    BookRecord(id: 'd', title: 'Beta', localPath: '/c',
        format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 20)),
  ];

  test('newest default has deterministic ties and preserves source order', () {
    final result = filterAndSortLibraryBooks(books);
    expect(result.map((b) => b.id), ['a', 'c', 'b', 'd']);
    expect(books.map((b) => b.id), ['b', 'c', 'a', 'd']);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('case-insensitive title sorting works in both directions', () {
    expect(filterAndSortLibraryBooks(books,
        sort: LibrarySortOrder.titleAscending).map((b) => b.id),
        ['a', 'c', 'd', 'b']);
    expect(filterAndSortLibraryBooks(books,
        sort: LibrarySortOrder.titleDescending).map((b) => b.id),
        ['b', 'd', 'a', 'c']);
  });

  test('query and format are combined without mutating storage', () {
    expect(filterAndSortLibraryBooks(books,
        query: '  ALPha  ').map((b) => b.id), ['a', 'c']);
    expect(filterAndSortLibraryBooks(books,
        query: 'alpha', format: BookFormat.epub).map((b) => b.id), ['c']);
    expect(filterAndSortLibraryBooks(books,
        query: 'missing', format: BookFormat.pdf), isEmpty);
    expect(filterAndSortLibraryBooks(books, query: '  ').length, 4);
  });

  test('format ordering and saved progress remain stable', () {
    final result = filterAndSortLibraryBooks(books,
        sort: LibrarySortOrder.format);
    expect(result.map((b) => b.id), ['c', 'd', 'a', 'b']);
    expect(result.last.progressOffset, 12);
    expect(books.first.progressOffset, 12);
    expect(filterAndSortLibraryBooks(const <BookRecord>[]), isEmpty);
  });
}
