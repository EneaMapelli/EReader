import 'dart:convert';
import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-test-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('imports, deduplicates and restores progress after restart', () async {
    final source = File(p.join(root.path, 'import.txt'));
    await source.writeAsString('Once upon a time...', flush: true);
    final first = await store.importFile(
      source.path, originalName: 'Story.TXT',
    );
    final duplicate = await store.importFile(source.path);
    expect(first.id, duplicate.id);
    expect(store.books, hasLength(1));
    expect(first.title, 'Story');

    await store.savePosition(first.id, 42);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(first.id)!.progressOffset, 42);
    expect(File(store.books.single.localPath).existsSync(), isTrue);
  });

  test('rejects invalid extensions, signature and negative positions', () async {
    final source = File(p.join(root.path, 'fake.epub'));
    await source.writeAsString('Not a ZIP');
    await expectLater(store.importFile(source.path), throwsFormatException);
    expect(store.books, isEmpty);
    await expectLater(store.savePosition('anything', -1), throwsArgumentError);
  });

  test('removing a book leaves the original import file intact', () async {
    final source = File(p.join(root.path, 'book.txt'));
    await source.writeAsString('Book text', flush: true);
    final book = await store.importFile(source.path);
    await store.removeBook(book.id);
    expect(store.books, isEmpty);
    expect(File(book.localPath).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });

  test('legacy JSON migrates and retains progress across multiple starts',
      () async {
    store.dispose();
    await File(p.join(root.path, 'library.sqlite')).delete();
    final managed = Directory(p.join(root.path, 'books'));
    await managed.create(recursive: true);
    final bookPath = p.join(managed.path, 'existing.txt');
    await File(bookPath).writeAsString('Legacy contents');
    await File(p.join(root.path, 'library.json')).writeAsString(jsonEncode([
      {
        'id': 'legacy',
        'title': 'Legacy',
        'localPath': bookPath,
        'format': 'txt',
        'importedAt': '2026-10-21T00:00:00.000Z',
        'progressOffset': 87,
      }
    ]));
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.books, hasLength(1));
    expect(store.getBook('legacy')!.progressOffset, 87);
    expect(File(p.join(root.path, 'library.migrated.json')).existsSync(), true);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.books, hasLength(1));
  });

  test('malformed legacy index is not destroyed', () async {
    store.dispose();
    await File(p.join(root.path, 'library.sqlite')).delete();
    final legacy = File(p.join(root.path, 'library.json'));
    await legacy.writeAsString('{"invalid":true}');
    store = LibraryStore(homeDirectory: root);
    await expectLater(store.initialize(), throwsFormatException);
    expect(legacy.existsSync(), isTrue);
  });
}
