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

  test('author and series are searchable and can be sorted', () {
    final withDetails = <BookRecord>[
      BookRecord(id: 'one', title: 'Hidden', localPath: '/one',
        format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 1),
        author: 'Zora Author', series: 'Amber Trilogy'),
      BookRecord(id: 'two', title: 'Secret', localPath: '/two',
        format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 2),
        author: 'Ada Writer', series: 'Zephyr Series'),
    ];
    expect(filterAndSortLibraryBooks(withDetails, query: 'ZORA')
        .map((book) => book.id), ['one']);
    expect(filterAndSortLibraryBooks(withDetails, query: 'zephyr')
        .map((book) => book.id), ['two']);
    expect(filterAndSortLibraryBooks(withDetails,
        sort: LibrarySortOrder.authorAscending).map((book) => book.id),
        ['two', 'one']);
    expect(filterAndSortLibraryBooks(withDetails,
        sort: LibrarySortOrder.seriesAscending).map((book) => book.id),
        ['one', 'two']);
  });

  test('format ordering and saved progress remain stable', () {
    final result = filterAndSortLibraryBooks(books,
        sort: LibrarySortOrder.format);
    expect(result.map((b) => b.id), ['c', 'd', 'a', 'b']);
    expect(result.last.progressOffset, 12);
    expect(books.first.progressOffset, 12);
    expect(filterAndSortLibraryBooks(const <BookRecord>[]), isEmpty);
  });
  test('recently opened sorts actual reader activity above new imports', () {
    final entries = <BookRecord>[
      BookRecord(id: 'new', title: 'New', localPath: '/new',
          format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 28)),
      BookRecord(id: 'old', title: 'Old', localPath: '/old',
          format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 1),
          lastOpenedAt: DateTime.utc(2026, 10, 27)),
      BookRecord(id: 'latest', title: 'Latest', localPath: '/latest',
          format: BookFormat.pdf, importedAt: DateTime.utc(2026, 10, 2),
          lastOpenedAt: DateTime.utc(2026, 10, 28)),
    ];
    expect(filterAndSortLibraryBooks(entries,
        sort: LibrarySortOrder.recentlyOpened).map((e) => e.id),
        ['latest', 'old', 'new']);
    expect(filterAndSortLibraryBooks(entries,
        sort: LibrarySortOrder.recentlyImported).map((e) => e.id),
        ['new', 'latest', 'old']);
  });

  test('activity filters combine with title and format without changing books', () {
    final entries = <BookRecord>[
      BookRecord(id: 'read', title: 'Atlas', localPath: '/read',
          format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 20),
          lastOpenedAt: DateTime.utc(2026, 10, 26)),
      BookRecord(id: 'unread', title: 'Atlas Two', localPath: '/unread',
          format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 21)),
      BookRecord(id: 'other', title: 'Other', localPath: '/other',
          format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 22),
          lastOpenedAt: DateTime.utc(2026, 10, 25)),
    ];
    expect(filterAndSortLibraryBooks(entries, query: 'atlas',
        format: BookFormat.epub, activity: LibraryActivityFilter.opened)
        .map((b) => b.id), ['read']);
    expect(filterAndSortLibraryBooks(entries, query: 'atlas',
        activity: LibraryActivityFilter.neverOpened)
        .map((b) => b.id), ['unread']);
    expect(filterAndSortLibraryBooks(entries,
        activity: LibraryActivityFilter.neverOpened,
        sort: LibrarySortOrder.recentlyOpened).map((b) => b.id), ['unread']);
    expect(entries, hasLength(3));
  });

  test('favorites-only composes with search, file format and activity',
      () {
    final entries = <BookRecord>[
      BookRecord(id: 'star', title: 'Atlas One', localPath: '/a',
          format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 1),
          lastOpenedAt: DateTime.utc(2026, 10, 2), isFavorite: true),
      BookRecord(id: 'other', title: 'Atlas Two', localPath: '/b',
          format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 2)),
      BookRecord(id: 'pdf', title: 'Atlas Manual', localPath: '/p',
          format: BookFormat.pdf, importedAt: DateTime.utc(2026, 10, 3),
          isFavorite: true),
    ];
    expect(filterAndSortLibraryBooks(entries,
        favoritesOnly: true).map((b) => b.id), ['pdf', 'star']);
    expect(filterAndSortLibraryBooks(entries, query: 'atlas',
        format: BookFormat.epub, favoritesOnly: true,
        activity: LibraryActivityFilter.opened).map((b) => b.id), ['star']);
    expect(filterAndSortLibraryBooks(entries,
        favoritesOnly: true,
        activity: LibraryActivityFilter.neverOpened).map((b) => b.id),
        ['pdf']);
    expect(entries, hasLength(3));
  });

  test('favorites-first ordering is deterministic without modifying books',
      () {
    final entries = <BookRecord>[
      BookRecord(id: 'one', title: 'Zulu', localPath: '/one',
          format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 1)),
      BookRecord(id: 'two', title: 'Beta', localPath: '/two',
          format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 2),
          isFavorite: true),
      BookRecord(id: 'three', title: 'Alpha', localPath: '/three',
          format: BookFormat.pdf, importedAt: DateTime.utc(2026, 10, 3),
          isFavorite: true),
      BookRecord(id: 'four', title: 'Aardvark', localPath: '/four',
          format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 4)),
    ];
    expect(filterAndSortLibraryBooks(entries,
        sort: LibrarySortOrder.favoritesFirst).map((b) => b.id),
        ['three', 'two', 'four', 'one']);
    expect(entries.first.id, 'one');
    expect(entries.last.id, 'four');
  });

  test('manual reading shelf filters combine with favorites, format and search',
      () {
    final entries = [
      BookRecord(id: 'read', title: 'Atlas', localPath: '/a',
        format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 20),
        isFavorite: true, readingStatus: BookReadingStatus.reading),
      BookRecord(id: 'done', title: 'Atlas Two', localPath: '/b',
        format: BookFormat.epub, importedAt: DateTime.utc(2026, 10, 21),
        isFavorite: true, readingStatus: BookReadingStatus.finished),
      BookRecord(id: 'queue', title: 'Manual', localPath: '/c',
        format: BookFormat.pdf, importedAt: DateTime.utc(2026, 10, 22)),
    ];
    expect(filterAndSortLibraryBooks(entries,
      readingStatus: BookReadingStatus.reading,
      favoritesOnly: true, query: 'ATLAS', format: BookFormat.epub)
      .map((b) => b.id), ['read']);
    expect(filterAndSortLibraryBooks(entries,
      readingStatus: BookReadingStatus.finished,
      favoritesOnly: true).map((b) => b.id), ['done']);
    expect(filterAndSortLibraryBooks(entries,
      readingStatus: BookReadingStatus.toRead).map((b) => b.id), ['queue']);
    expect(entries.length, 3);
  });

  test('manual shelf sorting is reading, queued, finished then title', () {
    final day = DateTime.utc(2026, 10, 29);
    final entries = [
      BookRecord(id: 'a', title: 'A finished', localPath: '/a',
        format: BookFormat.txt, importedAt: day,
        readingStatus: BookReadingStatus.finished),
      BookRecord(id: 'q', title: 'Queued', localPath: '/q',
        format: BookFormat.txt, importedAt: day),
      BookRecord(id: 'r2', title: 'Zulu active', localPath: '/r2',
        format: BookFormat.txt, importedAt: day,
        readingStatus: BookReadingStatus.reading),
      BookRecord(id: 'r1', title: 'Alpha active', localPath: '/r1',
        format: BookFormat.txt, importedAt: day,
        readingStatus: BookReadingStatus.reading),
    ];
    expect(filterAndSortLibraryBooks(entries,
      sort: LibrarySortOrder.readingStatus).map((b) => b.id),
      ['r1', 'r2', 'q', 'a']);
    expect(entries.first.id, 'a');
  });

  test('equal open dates and never opened fallback are stable', () {
    final date = DateTime.utc(2026, 10, 27);
    final entries = <BookRecord>[
      BookRecord(id: 'b', title: 'Same', localPath: '/b',
          format: BookFormat.txt, importedAt: date, lastOpenedAt: date),
      BookRecord(id: 'a', title: 'Same', localPath: '/a',
          format: BookFormat.txt, importedAt: date, lastOpenedAt: date),
      BookRecord(id: 'unopened', title: 'New', localPath: '/u',
          format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 28)),
    ];
    expect(filterAndSortLibraryBooks(entries,
        sort: LibrarySortOrder.recentlyOpened).map((b) => b.id),
        ['a', 'b', 'unopened']);
  });

}
