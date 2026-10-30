import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/library_catalog.dart';
import 'package:ereader/domain/smart_book_collection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('criteria are strict, round-trip and do not serialize book content', () {
    const rule = SmartBookCollectionRule(
      query: 'author:"Ada Writer" title:Atlas',
      format: BookFormat.epub,
      favoritesOnly: true,
      readingStatus: BookReadingStatus.reading,
      activity: LibraryActivityFilter.opened,
    );
    final json = rule.toJson();
    final restored = SmartBookCollectionRule.fromJson(json);
    expect(restored.query, rule.query);
    expect(restored.format, BookFormat.epub);
    expect(restored.favoritesOnly, isTrue);
    expect(restored.readingStatus, BookReadingStatus.reading);
    expect(restored.activity, LibraryActivityFilter.opened);
    expect(json.keys.toSet(), {
      'query', 'format', 'favoritesOnly', 'readingStatus', 'activity',
    });
    expect(json.toString(), isNot(contains('sourceText')));
  });

  test('invalid or unbounded rules fail closed', () {
    expect(() => const SmartBookCollectionRule().validate(),
        throwsFormatException);
    expect(() => const SmartBookCollectionRule(query: 'title:').validate(),
        throwsFormatException);
    expect(() => SmartBookCollectionRule(query: 'x' * 257).validate(),
        throwsFormatException);
    expect(() => SmartBookCollectionRule.fromJson({'query': 'book'}),
        throwsFormatException);
    expect(() => SmartBookCollectionRule.fromJson({
      'query': 'book', 'favoritesOnly': false, 'activity': 'unknown',
    }), throwsFormatException);
    expect(() => SmartBookCollectionRule.fromJson({
      'query': 'book', 'favoritesOnly': false, 'activity': 'all',
      'unexpected': 'no',
    }), throwsFormatException);
    expect(() => SmartBookCollectionRule.fromJson({
      'query': 'book', 'favoritesOnly': false, 'activity': 'all',
      'format': 'exe',
    }), throwsFormatException);
  });

  test('boolean-only smart collection is valid and model IDs are validated',
      () {
    const rule = SmartBookCollectionRule(favoritesOnly: true);
    expect(() => rule.validate(), returnsNormally);
    final saved = SmartBookCollection(
      id: 'smart_123_4', name: 'Favorites',
      createdAt: DateTime.utc(2026, 10, 30), rule: rule);
    expect(() => saved.validate(), returnsNormally);
    expect(() => SmartBookCollection(
      id: 'wrong/path', name: 'Favorites',
      createdAt: DateTime.utc(2026, 10, 30), rule: rule).validate(),
      throwsFormatException);
  });
}
