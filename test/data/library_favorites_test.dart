import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-favorites-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> add(String name) async {
    final source = File(p.join(root.path, '$name.txt'));
    await source.writeAsString('Unique contents from $name.');
    return (await store.importFile(source.path)).id;
  }

  test('fresh v22 library retains v20 favorite column, all unstarred', () async {
    final id = await add('first');
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').single['user_version'], 22);
    expect(db.select('PRAGMA table_info(books)')
        .any((row) => row['name'] == 'is_favorite'), isTrue);
    expect(db.select('SELECT is_favorite FROM books WHERE id = ?', [id])
        .single['is_favorite'], 0);
    db.dispose();
    expect(store.getBook(id)!.isFavorite, isFalse);
  });

  test('favorite survives restart and does not change source position',
      () async {
    final id = await add('saved');
    await store.savePosition(id, 12, anchor: const ReadingAnchor(
      kind: AnchorKind.text, sourceId: 'txt', localOffset: 12,
    ));
    final favorited = store.setBookFavorite(id, true);
    expect(favorited.isFavorite, isTrue);
    expect(favorited.progressOffset, 12);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(id)!.isFavorite, isTrue);
    expect(store.getBook(id)!.progressAnchor!.localOffset, 12);
    expect(store.getBook(id)!.progressOffset, 12);
    expect(store.getBook(id)!.lastOpenedAt, isNull);
    store.setBookFavorite(id, false);
    expect(store.getBook(id)!.isFavorite, isFalse);
    expect(store.getBook(id)!.progressOffset, 12);
  });

  test('favorites are independent by book and deleted with the book',
      () async {
    final a = await add('alpha');
    final b = await add('beta');
    store.setBookFavorite(a, true);
    expect(store.getBook(b)!.isFavorite, isFalse);
    expect(() => store.setBookFavorite('not-a-book', true),
        throwsStateError);
    await store.removeBook(a);
    expect(store.getBook(a), isNull);
    expect(store.getBook(b)!.isFavorite, isFalse);
  });

  test('schema v19 migrates stars without touching existing metadata',
      () async {
    final id = await add('before-upgrade');
    store.updateBookMetadata(id, title: 'Retained title', author: 'Writer');
    await store.savePosition(id, 11);
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('ALTER TABLE books DROP COLUMN is_favorite');
    db.execute('PRAGMA user_version = 19');
    db.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(id)!.title, 'Retained title');
    expect(store.getBook(id)!.author, 'Writer');
    expect(store.getBook(id)!.progressOffset, 11);
    expect(store.getBook(id)!.isFavorite, isFalse);
    store.setBookFavorite(id, true);
    expect(store.getBook(id)!.isFavorite, isTrue);
  });

  test('book JSON keeps favorite while older JSON remains unstarred',
      () async {
    final id = await add('portable');
    final book = store.setBookFavorite(id, true);
    final roundTrip = BookRecord.fromJson(book.toJson());
    expect(roundTrip.isFavorite, isTrue);
    final oldJson = Map<String, dynamic>.from(book.toJson())
      ..remove('favorite');
    expect(BookRecord.fromJson(oldJson).isFavorite, isFalse);
    expect(book.atOffset(3).isFavorite, isTrue);
  });
}
