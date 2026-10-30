import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book_collection.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-collections-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> add(String name) async {
    final file = File(p.join(root.path, '$name.txt'));
    await file.writeAsString('Unique private book: $name.');
    return (await store.importFile(file.path)).id;
  }

  test('new SQLite v26 library has separate collection/membership tables',
      () async {
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').single['user_version'], 26);
    expect(db.select("SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'book_collections'"), hasLength(1));
    expect(db.select("SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'book_collection_members'"), hasLength(1));
    db.dispose();
    expect(store.collections, isEmpty);
  });

  test('collection names trim and stay unique case-insensitively', () {
    final collection = store.createCollection('  Space Opera  ');
    expect(collection.name, 'Space Opera');
    expect(store.collections.single.id, collection.id);
    expect(() => store.createCollection('space opera'),
        throwsA(isA<SqliteException>()));
    expect(() => store.createCollection('  '), throwsFormatException);
    expect(() => store.createCollection(List.filled(81, 'a').join()), throwsFormatException);
    expect(() => store.createCollection('Line\nBreak'), throwsFormatException);
    final other = store.createCollection('Classics');
    expect(() => store.renameCollection(other.id, 'SPACE OPERA'),
        throwsA(isA<SqliteException>()));
    expect(store.collections.map((x) => x.name), ['Classics', 'Space Opera']);
  });

  test('books can belong to many collections and survive SQLite restart',
      () async {
    final book = await add('novel');
    final a = store.createCollection('Fantasy');
    final b = store.createCollection('Reading club');
    store.setBookCollection(book, a.id, true);
    store.setBookCollection(book, b.id, true);
    store.setBookCollection(book, a.id, true); // idempotent
    expect(store.listBookCollections(book).map((e) => e.name),
        ['Fantasy', 'Reading club']);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.collectionBookIds(a.id), {book});
    expect(store.listBookCollections(book), hasLength(2));
    store.setBookCollection(book, a.id, false);
    store.setBookCollection(book, a.id, false);
    expect(store.listBookCollections(book).map((e) => e.name),
        ['Reading club']);
    expect(store.getBook(book)!.progressOffset, 0);
  });

  test('renaming preserves membership and deleting folder never deletes book',
      () async {
    final book = await add('retained');
    await store.savePosition(book, 13, anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'txt', localOffset: 13));
    final folder = store.createCollection('Old name');
    store.setBookCollection(book, folder.id, true);
    final renamed = store.renameCollection(folder.id, 'New name');
    expect(renamed.id, folder.id);
    expect(store.listBookCollections(book).single.name, 'New name');
    store.deleteCollection(folder.id);
    expect(store.collections, isEmpty);
    expect(store.listBookCollections(book), isEmpty);
    expect(store.getBook(book)!.progressOffset, 13);
    expect(store.getBook(book)!.progressAnchor!.localOffset, 13);
  });

  test('deleting book cascades only its membership, not collection', () async {
    final a = await add('delete-me');
    final b = await add('stay');
    final group = store.createCollection('Shared');
    store.setBookCollection(a, group.id, true);
    store.setBookCollection(b, group.id, true);
    await store.removeBook(a);
    expect(store.collectionBookIds(group.id), {b});
    expect(store.collections, hasLength(1));
    expect(store.getBook(b), isNotNull);
  });

  test('unknown IDs and invalid models fail closed', () async {
    final book = await add('book');
    final category = store.createCollection('First');
    expect(() => store.listBookCollections('unknown'), throwsStateError);
    expect(() => store.collectionBookIds('unknown'), throwsStateError);
    expect(() => store.setBookCollection(book, 'unknown', true),
        throwsStateError);
    expect(() => store.setBookCollection('unknown', category.id, true),
        throwsStateError);
    expect(() => store.renameCollection('unknown', 'Updated'),
        throwsStateError);
    expect(() => store.deleteCollection('unknown'), throwsStateError);
    expect(() => BookCollection(
      id: 'unsafe/id', name: 'Valid', createdAt: DateTime.utc(2026),
    ).validate(), throwsFormatException);
  });

  test('v21 to v22 migration retains favorites, shelves and source offsets',
      () async {
    final book = await add('previous');
    store.setBookFavorite(book, true);
    await store.savePosition(book, 22);
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE book_collection_members');
    db.execute('DROP TABLE book_collections');
    db.execute('PRAGMA user_version = 21');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book)!.isFavorite, isTrue);
    expect(store.getBook(book)!.progressOffset, 22);
    expect(store.collections, isEmpty);
    final col = store.createCollection('After upgrade');
    store.setBookCollection(book, col.id, true);
    expect(store.collectionBookIds(col.id), {book});
  });
}
