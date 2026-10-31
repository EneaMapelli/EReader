import 'package:ereader/domain/book.dart';
import 'package:ereader/features/library/library_quick_open.dart';
import 'package:flutter_test/flutter_test.dart';

BookRecord book(
  String id,
  String title, {
  String? author,
  String? series,
  DateTime? opened,
}) => BookRecord(
  id: id,
  title: title,
  author: author,
  series: series,
  format: BookFormat.txt,
  localPath: '/virtual/' + id + '.txt',
  importedAt: DateTime.utc(2024),
  lastOpenedAt: opened,
);

void main() {
  test('quick-open search matches any metadata field and all query terms', () {
    final books = [
      book('a', 'Northern Lights', author: 'Ada Writer', series: 'Starlight'),
      book('b', 'South Seas', author: 'Ada Writer', series: 'Ocean'),
      book('c', 'Northern Star', author: 'Marco', series: 'Ocean'),
    ];
    final matches = findQuickOpenBooks(books, '  ADA   STARLIGHT ');
    expect(matches.books.map((item) => item.id), ['a']);
    expect(findQuickOpenBooks(books, 'northern marco')
        .books.single.id, 'c');
    expect(findQuickOpenBooks(books, 'absent').total, 0);
    expect(books.length, 3, reason: 'Pure searches must not mutate the list');
  });

  test('exact title prefix outranks substring and author matches', () {
    final books = [
      book('author', 'Far Away', author: 'Northern Lights'),
      book('inside', 'The Northern Lights'),
      book('prefix', 'Northern Lights'),
      book('prefix-2', 'Northern Story'),
    ];
    final matches = findQuickOpenBooks(books, 'north');
    expect(matches.books.map((item) => item.id),
        ['prefix', 'prefix-2', 'inside', 'author']);
  });

  test('search is case-insensitive and stable for same-title editions', () {
    final result = findQuickOpenBooks([
      book('z', 'Atlas', author: 'Person'),
      book('a', 'ATLAS', author: 'Person'),
    ], 'AtLaS');
    expect(result.total, 2);
    expect(result.books.map((item) => item.id), ['a', 'z']);
  });

  test('empty query ranks recently opened first, then alphabetically', () {
    final results = findQuickOpenBooks([
      book('z', 'Zulu'),
      book('b', 'Beta', opened: DateTime.utc(2026, 3)),
      book('a', 'Alpha'),
      book('x', 'Xenon', opened: DateTime.utc(2026, 5)),
    ], '');
    expect(results.books.map((item) => item.id), ['x', 'b', 'a', 'z']);
  });

  test('large catalogs are fully counted, but UI results are bounded', () {
    final all = [
      for (var i = 0; i < 1000; i++)
        book('id-' + i.toString(), 'Book ' + i.toString()),
    ];
    final results = findQuickOpenBooks(all, 'book', limit: 40);
    expect(results.total, 1000);
    expect(results.books, hasLength(40));
    expect(results.truncated, isTrue);
    expect(results.books.first.title, 'Book 0');
    expect(results.books.last.title, 'Book 133');
    expect(findQuickOpenBooks(all, 'not present').books, isEmpty);
    expect(all, hasLength(1000));
  });

  test('late high-relevance matches displace lower-ranked top-40 results', () {
    final many = [
      for (var i = 0; i < 200; i++)
        book('generic-' + i.toString(), 'The Atlas Volume ' + i.toString()),
      book('precise', 'Atlas Prime', author: 'The last import'),
    ];
    final results = findQuickOpenBooks(many, 'atlas');
    expect(results.total, 201);
    expect(results.books, hasLength(40));
    expect(results.books.first.id, 'precise',
        reason: 'A late title prefix must outrank earlier substrings');
    expect(results.truncated, isTrue);
    expect(many, hasLength(201));
  });

  test('arrow selection clamps at boundaries and never selects empty results', () {
    expect(moveQuickOpenSelection(current: 0, count: 0, down: true), isNull);
    expect(moveQuickOpenSelection(current: 0, count: 0, down: false), isNull);
    expect(moveQuickOpenSelection(current: 0, count: 3, down: false), 0);
    expect(moveQuickOpenSelection(current: 0, count: 3, down: true), 1);
    expect(moveQuickOpenSelection(current: 1, count: 3, down: true), 2);
    expect(moveQuickOpenSelection(current: 2, count: 3, down: true), 2);
    expect(moveQuickOpenSelection(current: 2, count: 3, down: false), 1);
    expect(moveQuickOpenSelection(current: 0, count: 1, down: true), 0);
    expect(moveQuickOpenSelection(current: 0, count: 1, down: false), 0);
  });

  test('rejects invalid cap rather than hiding all results silently', () {
    expect(() => findQuickOpenBooks([], 'anything', limit: 0),
        throwsRangeError);
  });
}
