import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/reading_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory home;
  late LibraryStore store;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-appearance-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  Future<String> importBook(String name) async {
    final input = File(p.join(home.path, name));
    await input.writeAsString('A sample private text for this book.');
    return (await store.importFile(input.path)).id;
  }

  test('fresh library has v18 visual preferences table and defaults', () {
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').single['user_version'], 18);
    expect(db.select(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='reading_preferences'",
    ), hasLength(1));
    db.dispose();
    expect(store.getReadingPreferences().palette, 'system');
    expect(store.getReadingPreferences().fontSize, 19);
  });

  test('global font, spacing and palette survive closing and reopening',
      () async {
    const profile = ReadingPreferences(
      fontSize: 25, lineHeight: 2.1,
      fontFamily: 'sans-serif', palette: 'sepia',
    );
    store.saveReadingPreferences(profile);
    store.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.getReadingPreferences().toJson(), profile.toJson());
  });

  test('book overrides global without mutating another book', () async {
    final a = await importBook('a.txt');
    final b = await importBook('b.txt');
    // Different content produces distinct digests.
    expect(a, isNot(b));
    const global = ReadingPreferences(
      fontSize: 20, palette: 'night',
    );
    const special = ReadingPreferences(
      fontSize: 30, lineHeight: 2.4, fontFamily: 'monospace',
    );
    store.saveReadingPreferences(global);
    store.saveReadingPreferences(special, bookId: a);
    expect(store.getReadingPreferences(bookId: a).toJson(),
        special.toJson());
    expect(store.getReadingPreferences(bookId: b).toJson(), global.toJson());
    store.clearBookReadingPreferences(a);
    expect(store.getReadingPreferences(bookId: a).toJson(), global.toJson());
  });

  test('reopened per-book style has no effect on last-read source position',
      () async {
    final book = await importBook('progress.txt');
    await store.savePosition(book, 15);
    store.saveReadingPreferences(const ReadingPreferences(
      fontSize: 23, lineHeight: 1.45, palette: 'night',
    ), bookId: book);
    store.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.getBook(book)!.progressOffset, 15);
    expect(store.getReadingPreferences(bookId: book).fontSize, 23);
    expect(store.getSpeechPreferences(bookId: book).providerId, 'system');
  });

  test('visual profile refuses unknown books and invalid ranges', () {
    expect(() => store.saveReadingPreferences(
      const ReadingPreferences(fontSize: 60)), throwsFormatException);
    expect(() => store.saveReadingPreferences(
      const ReadingPreferences(), bookId: 'missing'), throwsStateError);
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(db.select('SELECT * FROM reading_preferences'), isEmpty);
    db.dispose();
  });

  test('deleting a book deletes only its visual settings', () async {
    final a = await importBook('first.txt');
    final b = await importBook('second.txt');
    store.saveReadingPreferences(
        const ReadingPreferences(fontSize: 22), bookId: a);
    store.saveReadingPreferences(
        const ReadingPreferences(fontSize: 28), bookId: b);
    store.saveReadingPreferences(
        const ReadingPreferences(palette: 'sepia'));
    await store.removeBook(a);
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(db.select(
        'SELECT * FROM reading_preferences WHERE scope_id = ?', ['book:$a']),
        isEmpty);
    expect(store.getReadingPreferences(bookId: b).fontSize, 28);
    expect(store.getReadingPreferences().palette, 'sepia');
    db.dispose();
  });
}
