import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/library_catalog.dart';
import 'package:ereader/domain/library_search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final books = [
    BookRecord(
      id: 'one', title: 'Atlas of Space Opera',
      author: 'Ada Writer', series: 'North Star',
      format: BookFormat.epub, localPath: '/one',
      importedAt: DateTime.utc(2026, 10, 1),
      isFavorite: true, readingStatus: BookReadingStatus.reading,
    ),
    BookRecord(
      id: 'two', title: 'Space Atlas', author: 'Marco Rossi',
      series: 'Ada Chronicles', format: BookFormat.pdf,
      localPath: '/two', importedAt: DateTime.utc(2026, 10, 2),
    ),
    BookRecord(
      id: 'three', title: 'Una storia', author: 'Émile Zola',
      series: 'Séries célèbres', format: BookFormat.txt,
      localPath: '/three', importedAt: DateTime.utc(2026, 10, 3),
    ),
  ];

  List<String> ids(String query, {
    BookFormat? format, bool favoritesOnly = false,
  }) => filterAndSortLibraryBooks(
    books, query: query, format: format,
    favoritesOnly: favoritesOnly,
  ).map((book) => book.id).toList();

  test('legacy substring search and empty catalog query still work', () {
    expect(ids('atlas'), ['two', 'one']);
    expect(ids('  ATLAS  '), ['two', 'one']);
    expect(ids(''), ['three', 'two', 'one']);
    expect(ids('   '), ['three', 'two', 'one']);
    expect(LibrarySearchQuery.parse('').terms, isEmpty);
  });

  test('multiple words are AND across fields, order independent', () {
    expect(ids('atlas ada'), ['two', 'one']);
    expect(ids('ada atlas'), ['two', 'one']);
    expect(ids('north writer'), ['one']);
    expect(ids('atlas missing'), isEmpty);
    expect(ids('atlas ada', format: BookFormat.epub), ['one']);
    expect(ids('atlas ada', favoritesOnly: true), ['one']);
  });

  test('quoted phrases require contiguous text in one field', () {
    expect(ids('"Space Opera"'), ['one']);
    expect(ids('"space atlas"'), ['two']);
    expect(ids('"atlas space"'), isEmpty);
    expect(ids('"Ada Writer"'), ['one']);
    expect(ids('"ada" "north star"'), ['one']);
  });

  test('field qualifiers constrain results and ignore prefix case', () {
    expect(ids('title:atlas'), ['two', 'one']);
    expect(ids('author:ada'), ['one']);
    expect(ids('series:ada'), ['two']);
    expect(ids('AUTHOR:"Ada Writer" series:"North Star"'), ['one']);
    expect(ids('title:"Space Opera" author:marco'), isEmpty);
    expect(ids('series:"Séries célèbres"'), ['three']);
  });

  test('unrecognized field name is searched literally, not treated as SQL', () {
    expect(ids('publisher:ada'), isEmpty);
    expect(ids("title:atlas' OR 1=1"), isEmpty);
    expect(ids('title:atlas'), ['two', 'one']);
    expect(books, hasLength(3));
  });

  test('unfinished or malformed search is visible and fails closed', () {
    for (final query in [
      'title:', 'author: ', 'series:', '"unfinished',
      'title:"unfinished', '""', 'title:"one"bad',
      List.filled(17, 'word').join(' '),
      'x' * 257,
    ]) {
      final parsed = LibrarySearchQuery.parse(query);
      expect(parsed.isValid, isFalse, reason: query);
      expect(parsed.error, isNotNull);
      expect(ids(query), isEmpty);
    }
  });

  test('unicode catalog search and source metadata stay untouched', () {
    expect(ids('author:ÉMILE'), ['three']);
    expect(ids('series:"séries célèbres"'), ['three']);
    expect(LibrarySearchQuery.parse('atlas').isValid, isTrue);
    expect(books.first.title, 'Atlas of Space Opera');
    expect(books.first.author, 'Ada Writer');
    expect(books.first.progressOffset, 0);
  });

  test('token budget boundary and immutable parsed terms', () {
    final query = List.filled(16, 'atlas').join(' ');
    final parsed = LibrarySearchQuery.parse(query);
    expect(parsed.isValid, isTrue);
    expect(parsed.terms, hasLength(16));
    expect(() => parsed.terms.clear(), throwsUnsupportedError);
    expect(parsed.matches(books.first), isTrue);
  });
}
