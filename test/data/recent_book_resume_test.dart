import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-resume-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> addBook(String name, String text) async {
    final original = File(p.join(root.path, name));
    await original.writeAsString(text, flush: true);
    final book = await store.importFile(original.path);
    return book.id;
  }

  test('explicit open remembers last book across process restart', () async {
    final first = await addBook('first.txt', 'Part one and part two.');
    final second = await addBook('second.txt', 'A different book.');
    expect(store.lastOpenedBook, isNull);
    await store.markBookOpened(first);
    await store.savePosition(
      first, 9,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 9,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.markBookOpened(second);
    expect(store.lastOpenedBook?.id, second);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.lastOpenedBook?.id, second);
    // Opening another book updates only the resume shortcut, not text data.
    await store.markBookOpened(first);
    expect(store.lastOpenedBook?.id, first);
    expect(store.getBook(first)!.progressOffset, 9);
    expect(store.getBook(first)!.progressAnchor!.localOffset, 9);
  });

  test('deleted and unavailable book files are never resumed', () async {
    final first = await addBook('first.txt', 'One.');
    final second = await addBook('second.txt', 'Two.');
    await store.markBookOpened(first);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.markBookOpened(second);
    final lost = store.getBook(second)!;
    await File(lost.localPath).delete();
    expect(store.lastOpenedBook?.id, first,
      reason: 'Missing private files cannot be opened with the shortcut');
    await store.removeBook(first);
    expect(store.lastOpenedBook, isNull);
  });

  test('unknown IDs are not silently persisted as a resume target', () async {
    await expectLater(store.markBookOpened('missing'), throwsStateError);
    expect(store.lastOpenedBook, isNull);
  });

  test('SQLite v13 migration preserves reading anchors and adds resume field',
      () async {
    final bookId = await addBook('older.txt', 'A source before migration.');
    await store.savePosition(
      bookId, 12,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 12,
      ),
    );
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('ALTER TABLE books DROP COLUMN last_opened_at');
    db.execute('PRAGMA user_version = 13');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.lastOpenedBook, isNull);
    expect(store.getBook(bookId)!.progressOffset, 12);
    expect(store.getBook(bookId)!.progressAnchor!.localOffset, 12);
    await store.markBookOpened(bookId);
    expect(store.lastOpenedBook?.id, bookId);
    final migrated = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(migrated.select('PRAGMA user_version').first['user_version'], 16);
    migrated.dispose();
  });
}
