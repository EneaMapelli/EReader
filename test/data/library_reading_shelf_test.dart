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
    root = await Directory.systemTemp.createTemp('ereader-shelves-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> add(String name) async {
    final file = File(p.join(root.path, '$name.txt'));
    await file.writeAsString('Unique book contents of $name.');
    return (await store.importFile(file.path)).id;
  }

  test('fresh library defaults to To read with valid v23 schema', () async {
    final id = await add('initial');
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').single['user_version'], 23);
    expect(db.select('SELECT reading_status FROM books WHERE id = ?',
        [id]).single['reading_status'], 'toRead');
    db.dispose();
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.toRead);
  });

  test('marking Reading and Finished never rewrites TTS source checkpoint',
      () async {
    final id = await add('manual');
    await store.savePosition(id, 18, anchor: const ReadingAnchor(
      kind: AnchorKind.text, sourceId: 'txt', localOffset: 18,
    ));
    store.setBookReadingStatus(id, BookReadingStatus.reading);
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.reading);
    final marked = store.setBookReadingStatus(id, BookReadingStatus.finished);
    expect(marked.readingStatus, BookReadingStatus.finished);
    expect(marked.progressOffset, 18);
    expect(marked.progressAnchor!.localOffset, 18);
    expect(marked.lastOpenedAt, isNull);
    expect(marked.isFavorite, isFalse);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.finished);
    expect(store.getBook(id)!.progressOffset, 18);
    store.setBookReadingStatus(id, BookReadingStatus.toRead);
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.toRead);
    expect(store.getBook(id)!.progressOffset, 18);
  });

  test('statuses are independent per book, and unknown book is rejected',
      () async {
    final one = await add('one');
    final two = await add('two');
    store.setBookReadingStatus(one, BookReadingStatus.finished);
    store.setBookFavorite(two, true);
    expect(store.getBook(two)!.readingStatus, BookReadingStatus.toRead);
    expect(store.getBook(one)!.isFavorite, isFalse);
    expect(() => store.setBookReadingStatus(
      'unknown', BookReadingStatus.reading), throwsStateError);
    await store.removeBook(one);
    expect(store.getBook(one), isNull);
    expect(store.getBook(two)!.isFavorite, isTrue);
  });

  test('existing v20 library migrates to v21 preserving metadata and stars',
      () async {
    final id = await add('old');
    store.setBookFavorite(id, true);
    store.updateBookMetadata(id, title: 'Preserved title', author: 'Author');
    await store.savePosition(id, 9);
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('ALTER TABLE books DROP COLUMN reading_status');
    db.execute('PRAGMA user_version = 20');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final book = store.getBook(id)!;
    expect(book.readingStatus, BookReadingStatus.toRead);
    expect(book.isFavorite, isTrue);
    expect(book.title, 'Preserved title');
    expect(book.author, 'Author');
    expect(book.progressOffset, 9);
    store.setBookReadingStatus(id, BookReadingStatus.reading);
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.reading);
  });

  test('portable BookRecord JSON preserves shelf and defaults legacy data',
      () async {
    final id = await add('portable');
    final book = store.setBookReadingStatus(id, BookReadingStatus.finished);
    expect(BookRecord.fromJson(book.toJson()).readingStatus,
        BookReadingStatus.finished);
    final legacy = Map<String, dynamic>.from(book.toJson())
      ..remove('readingStatus');
    expect(BookRecord.fromJson(legacy).readingStatus, BookReadingStatus.toRead);
    expect(book.atOffset(42).readingStatus, BookReadingStatus.finished);
    final broken = Map<String, dynamic>.from(book.toJson())
      ..['readingStatus'] = 'not-a-shelf';
    expect(() => BookRecord.fromJson(broken), throwsArgumentError);
  });
}
