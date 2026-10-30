import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/library_catalog.dart';
import 'package:ereader/domain/smart_book_collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory home;
  late LibraryStore store;
  late String atlas;
  late String beta;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-smart-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    for (final name in ['Atlas', 'Beta']) {
      final file = File(p.join(home.path, '$name.txt'));
      await file.writeAsString('Unique catalog record $name');
      final id = (await store.importFile(file.path)).id;
      if (name == 'Atlas') {
        atlas = id;
      } else {
        beta = id;
      }
    }
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  test('v26 schema and saved smart filters update as books change', () {
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').single['user_version'], 26);
    db.dispose();

    final manual = store.createCollection('Manual shelf');
    store.setBookCollection(beta, manual.id, true);
    final smart = store.createSmartCollection(
      'Reading favorites',
      const SmartBookCollectionRule(
        favoritesOnly: true,
        readingStatus: BookReadingStatus.reading,
      ),
    );
    expect(store.smartCollectionBookIds(smart.id), isEmpty);
    store.setBookFavorite(atlas, true);
    expect(store.smartCollectionBookIds(smart.id), isEmpty);
    store.setBookReadingStatus(atlas, BookReadingStatus.reading);
    expect(store.smartCollectionBookIds(smart.id), {atlas});
    store.setBookFavorite(atlas, false);
    expect(store.smartCollectionBookIds(smart.id), isEmpty);
    expect(store.collectionBookIds(manual.id), {beta});
    expect(store.listBookCollections(atlas), isEmpty);
  });

  test('title/author/format query matches latest metadata and can be edited',
      () {
    store.updateBookMetadata(
        atlas, title: 'Atlas', author: 'Ada Writer', series: 'North Star');
    final smart = store.createSmartCollection('Science',
        const SmartBookCollectionRule(
          query: 'author:ada title:atlas', format: BookFormat.txt,
        ));
    expect(store.smartCollectionBookIds(smart.id), {atlas});
    store.updateBookMetadata(
        atlas, title: 'Atlas', author: 'Marco Writer', series: 'North Star');
    expect(store.smartCollectionBookIds(smart.id), isEmpty);
    final edited = store.updateSmartCollection(
        smart.id, 'Star shelf',
        const SmartBookCollectionRule(query: 'series:"North Star"'));
    expect(edited.id, smart.id);
    expect(edited.name, 'Star shelf');
    expect(store.smartCollectionBookIds(smart.id), {atlas});
  });

  test('name uniqueness, invalid IDs, no unfiltered rule, delete safety',
      () {
    store.createCollection('Manual');
    expect(() => store.createSmartCollection(
          'manual', const SmartBookCollectionRule(favoritesOnly: true)),
        throwsFormatException);
    final smart = store.createSmartCollection(
      'Dynamic', const SmartBookCollectionRule(favoritesOnly: true));
    expect(() => store.createSmartCollection(
      'DYNAMIC', const SmartBookCollectionRule(favoritesOnly: true)),
      throwsA(isA<SqliteException>()));
    expect(() => store.createCollection('dynamic'), throwsFormatException);
    expect(() => store.createSmartCollection(
        'Empty', const SmartBookCollectionRule()), throwsFormatException);
    expect(() => store.smartCollectionBookIds('not-found'),
        throwsStateError);
    expect(() => store.updateSmartCollection('not-found', 'Nope',
        const SmartBookCollectionRule(favoritesOnly: true)),
        throwsStateError);
    expect(() => store.deleteSmartCollection('not-found'), throwsStateError);
    expect(() => store.updateSmartCollection(smart.id, 'Manual',
        const SmartBookCollectionRule(favoritesOnly: true)),
        throwsFormatException);
    store.deleteSmartCollection(smart.id);
    expect(store.smartCollections, isEmpty);
    expect(store.books, hasLength(2));
    expect(store.collections.single.name, 'Manual');
  });

  test('saved smart definitions survive restart and remain recalculated',
      () async {
    final saved = store.createSmartCollection(
      'To read', const SmartBookCollectionRule(
        readingStatus: BookReadingStatus.toRead,
        activity: LibraryActivityFilter.neverOpened));
    expect(store.smartCollectionBookIds(saved.id), {atlas, beta});
    await store.markBookOpened(beta);
    expect(store.smartCollectionBookIds(saved.id), {atlas});
    store.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.smartCollections.single.name, 'To read');
    expect(store.smartCollectionBookIds(saved.id), {atlas});
    store.setBookReadingStatus(atlas, BookReadingStatus.finished);
    expect(store.smartCollectionBookIds(saved.id), isEmpty);
    expect(store.books, hasLength(2));
  });

  test('v24 database migrates to v25 without changing manual collections',
      () async {
    final manual = store.createCollection('Preexisting');
    store.setBookCollection(atlas, manual.id, true);
    store.setBookFavorite(atlas, true);
    store.dispose();
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    db.execute('DROP TABLE smart_book_collections');
    db.execute('PRAGMA user_version = 24');
    db.dispose();

    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.smartCollections, isEmpty);
    expect(store.collectionBookIds(manual.id), {atlas});
    expect(store.getBook(atlas)!.isFavorite, isTrue);
    final upgraded = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(upgraded.select('PRAGMA user_version').single['user_version'], 26);
    upgraded.dispose();
    expect(store.createSmartCollection('New',
      const SmartBookCollectionRule(favoritesOnly: true)).name, 'New');
  });
}
