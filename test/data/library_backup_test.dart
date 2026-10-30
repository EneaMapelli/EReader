import 'dart:convert';
import 'dart:io';

import 'package:ereader/data/library_backup.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/smart_book_collection.dart';
import 'package:ereader/domain/reading_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late Directory appHome;
  late Directory backups;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-export-test-');
    appHome = Directory(p.join(root.path, 'app'));
    backups = Directory(p.join(root.path, 'export'));
    await backups.create();
    store = LibraryStore(homeDirectory: appHome);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<BookRecord> addBook(String fileName, String text) async {
    final source = File(p.join(root.path, fileName));
    await source.writeAsString(text);
    return store.importFile(source.path);
  }

  test('v25 private SQLite export includes opted-out state and old totals',
      () async {
    final book = await addBook('tracking.txt', 'Original private story.');
    store.recordReadingActivity(book.id, ReadingActivityMode.visual, 13);
    store.saveDailyReadingGoalMinutes(45);
    store.saveReadingActivityTrackingEnabled(false);
    store.recordReadingActivity(book.id, ReadingActivityMode.tts, 20);

    final backup = await store.exportLibraryBackup(backups);
    final snapshot = sqlite3.open(
        p.join(backup.directory.path, 'library.sqlite'));
    try {
      expect(snapshot.select('PRAGMA user_version').single['user_version'], 26);
      final settings = snapshot.select(
          'SELECT tracking_enabled, goal_minutes '
          'FROM reading_activity_settings WHERE slot = 1').single;
      expect(settings['tracking_enabled'], 0);
      expect(settings['goal_minutes'], 45);
      final activity = snapshot.select(
          'SELECT mode, seconds FROM reading_activity_daily '
          'WHERE book_id = ?', [book.id]);
      expect(activity, hasLength(1));
      expect(activity.single['mode'], 'visual');
      expect(activity.single['seconds'], 13);
    } finally {
      snapshot.dispose();
    }
    expect(store.isReadingActivityTrackingEnabled, isFalse);
    expect(store.bookReadingLifetimeTotals(book.id).totalSeconds, 13);
  });

  test('v26 snapshot preserves local smart definitions, add-only restore does not',
      () async {
    await addBook('story.txt', 'Local archive story');
    final smart = store.createSmartCollection('Smart Stars',
        const SmartBookCollectionRule(favoritesOnly: true));
    final backup = await store.exportLibraryBackup(backups);
    final sqlite = sqlite3.open(
        p.join(backup.directory.path, 'library.sqlite'));
    try {
      expect(sqlite.select('PRAGMA user_version').single['user_version'], 26);
      final rules = sqlite.select('''
        SELECT id, name, rule_json FROM smart_book_collections
        WHERE id = ?
      ''', [smart.id]);
      expect(rules, hasLength(1));
      expect(rules.single['name'], 'Smart Stars');
      expect(rules.single['rule_json'], contains('favoritesOnly'));
    } finally {
      sqlite.dispose();
    }
    final destination = LibraryStore(
        homeDirectory: Directory(p.join(root.path, 'restore-dest')));
    try {
      await destination.initialize();
      final preview = await destination.previewLibraryRestore(backup.directory);
      expect(preview.availableToImport, 1);
      final restored = await destination.restoreLibraryBackup(backup.directory);
      expect(restored.added, 1);
      expect(destination.books, hasLength(1));
      expect(destination.smartCollections, isEmpty,
          reason: 'Portable add-only restore does not implicitly install rules');
    } finally {
      destination.dispose();
    }
    expect(store.smartCollections.single.id, smart.id);
  });

  test('v26 opted-in FTS content is private backup data, not portable consent',
      () async {
    final book = await addBook('search-private.txt',
        'This private manuscript mentions a violet phoenix.');
    store.setFullTextIndexEnabled(true);
    expect((await store.indexNextFullTextBatch()).indexed, 1);
    final backup = await store.exportLibraryBackup(backups);
    final db = sqlite3.open(
        p.join(backup.directory.path, 'library.sqlite'));
    try {
      expect(db.select('PRAGMA user_version').single['user_version'], 26);
      expect(db.select(
        'SELECT body FROM library_fulltext_fts WHERE book_id = ?',
        [book.id]).single['body'], contains('violet phoenix'));
    } finally {
      db.dispose();
    }

    final destination = LibraryStore(
        homeDirectory: Directory(p.join(root.path, 'restore-fts-dest')));
    try {
      await destination.initialize();
      final preview = await destination.previewLibraryRestore(backup.directory);
      expect(preview.availableToImport, 1);
      final result = await destination.restoreLibraryBackup(backup.directory);
      expect(result.added, 1);
      expect(destination.getBook(book.id), isNotNull);
      expect(destination.isFullTextIndexEnabled, isFalse);
      expect(destination.searchIndexedBookContents('phoenix'), isEmpty);
      final targetDb = sqlite3.open(
          p.join(root.path, 'restore-fts-dest', 'library.sqlite'));
      try {
        expect(targetDb.select(
          "SELECT name FROM sqlite_master WHERE name = "
          "'library_fulltext_fts'",
        ), isEmpty);
      } finally {
        targetDb.dispose();
      }
    } finally {
      destination.dispose();
    }
    expect(store.isFullTextIndexEnabled, isTrue);
  });

  test('backups contain hashed books, standalone SQLite and metadata',
      () async {
    final a = await addBook('one.txt', 'First original manuscript.');
    final b = await addBook('two.txt', 'Second unrelated document.');
    await store.savePosition(a.id, 13);
    store.updateBookMetadata(a.id, title: 'Renamed title',
        author: 'Writer', series: 'Cycle', language: 'it-IT');
    // Native OS secret storage and untrusted user files are NEVER exported.
    await File(p.join(appHome.path, 'fake-credential-vault.txt'))
        .writeAsString('DO-NOT-BACK-UP');
    final progress = <String>[];
    final result = await store.exportLibraryBackup(
      backups,
      onProgress: (done, total) => progress.add('$done/$total'),
    );
    expect(result.bookCount, 2);
    expect(result.bookBytes, greaterThan(0));
    expect(progress, ['1/2', '2/2']);
    expect(p.basename(result.directory.path), startsWith('EReader-backup-'));
    final items = await result.directory.list().map(
        (e) => p.basename(e.path)).toList();
    expect(items.toSet(), {'books', 'library.sqlite', 'manifest.json'});
    final manifest = jsonDecode(await File(
        p.join(result.directory.path, 'manifest.json')).readAsString())
        as Map<String, dynamic>;
    expect(manifest['version'], 1);
    expect(manifest['type'], 'ereader-library-backup');
    expect(manifest['bookCount'], 2);
    expect(manifest['containsNativeCredentialVaultSecrets'], isFalse);
    expect(manifest['restoreRequiresPathRelinking'], isTrue);
    final entries = manifest['books'] as List;
    expect(entries, hasLength(2));
    expect(entries.every((item) =>
        (item['file'] as String).startsWith('books/')), isTrue);
    final fileA = File(p.join(result.directory.path,
        'books', '${a.id}.txt'));
    final fileB = File(p.join(result.directory.path,
        'books', '${b.id}.txt'));
    expect(await fileA.readAsString(), 'First original manuscript.');
    expect(await fileB.readAsString(), 'Second unrelated document.');
    final snapshot = sqlite3.open(
        p.join(result.directory.path, 'library.sqlite'));
    try {
      expect(snapshot.select('PRAGMA integrity_check').first['integrity_check'],
          'ok');
      final row = snapshot.select('SELECT title, author, series, language, '
          'progress_offset FROM books WHERE id = ?', [a.id]).first;
      expect(row['title'], 'Renamed title');
      expect(row['author'], 'Writer');
      expect(row['series'], 'Cycle');
      expect(row['language'], 'it-IT');
      expect(row['progress_offset'], 13);
    } finally {
      snapshot.dispose();
    }
    expect(store.getBook(a.id)!.progressOffset, 13);
    expect(store.books, hasLength(2));
  });

  test('portable manifest and SQLite snapshot both contain favorite state',
      () async {
    final starred = await addBook('fav.txt', 'A favorite story');
    final plain = await addBook('plain.txt', 'An ordinary book');
    store.setBookFavorite(starred.id, true);
    store.setBookReadingStatus(starred.id, BookReadingStatus.reading);
    store.setBookReadingStatus(plain.id, BookReadingStatus.finished);
    final exported = await store.exportLibraryBackup(backups);
    final manifest = jsonDecode(await File(p.join(
        exported.directory.path, 'manifest.json')).readAsString()) as Map;
    final entries = manifest['books'] as List;
    final saved = {
      for (final entry in entries)
        (entry as Map)['sha256'] as String: entry['favorite'] as bool,
    };
    expect(saved[starred.id], isTrue);
    expect(saved[plain.id], isFalse);
    final states = {
      for (final entry in entries)
        (entry as Map)['sha256'] as String: entry['readingStatus'] as String,
    };
    expect(states[starred.id], 'reading');
    expect(states[plain.id], 'finished');
    final db = sqlite3.open(
        p.join(exported.directory.path, 'library.sqlite'));
    try {
      expect(db.select('PRAGMA user_version').first['user_version'], 26);
      expect(db.select('SELECT reading_status FROM books WHERE id = ?',
          [starred.id]).single['reading_status'], 'reading');
      expect(db.select('SELECT reading_status FROM books WHERE id = ?',
          [plain.id]).single['reading_status'], 'finished');
      expect(db.select('SELECT is_favorite FROM books WHERE id = ?',
          [starred.id]).single['is_favorite'], 1);
      expect(db.select('SELECT is_favorite FROM books WHERE id = ?',
          [plain.id]).single['is_favorite'], 0);
    } finally {
      db.dispose();
    }
  });

  test('v26 backup snapshots book collection memberships and manifest',
      () async {
    final a = await addBook('assigned.txt', 'Grouped source content');
    final b = await addBook('other.txt', 'Ungrouped source content');
    final group = store.createCollection('Travel');
    store.createCollection('Unused group');
    store.setBookCollection(a.id, group.id, true);
    final exported = await store.exportLibraryBackup(backups);
    final manifest = jsonDecode(await File(
        p.join(exported.directory.path, 'manifest.json')).readAsString())
        as Map;
    final entries = manifest['books'] as List;
    final memberships = {
      for (final entry in entries)
        (entry as Map)['sha256'] as String: entry['collections'] as List,
    };
    expect(memberships[a.id], ['Travel']);
    expect(memberships[b.id], isEmpty);
    final db = sqlite3.open(
        p.join(exported.directory.path, 'library.sqlite'));
    try {
      expect(db.select('PRAGMA user_version').first['user_version'], 26);
      expect(db.select('SELECT * FROM book_collections'), hasLength(2));
      expect(db.select('SELECT * FROM book_collection_members'), hasLength(1));
    } finally {
      db.dispose();
    }
  });

  test('corrupted content fails closed and leaves no complete backup',
      () async {
    final book = await addBook('original.txt', 'Untouched text');
    await File(book.localPath).writeAsString('Tampered but same identity');
    await expectLater(store.exportLibraryBackup(backups),
        throwsFormatException);
    expect(await backups.list().toList(), isEmpty);
    expect(store.getBook(book.id), isNotNull);
  });

  test('missing source refuses export before writing SQLite files', () async {
    final book = await addBook('missing.txt', 'Stored book');
    await File(book.localPath).delete();
    await expectLater(store.exportLibraryBackup(backups),
        throwsFormatException);
    expect(await backups.list().toList(), isEmpty);
  });

  test('backup cannot be written inside live application folder', () async {
    await expectLater(store.exportLibraryBackup(appHome),
        throwsFormatException);
    final nested = Directory(p.join(appHome.path, 'backups'));
    await nested.create();
    await expectLater(store.exportLibraryBackup(nested),
        throwsFormatException);
    expect(await nested.list().toList(), isEmpty);
  });

  test('bad snapshot cannot be published as a valid backup', () async {
    final book = await addBook('snapshot.txt', 'Source');
    await expectLater(exportPortableLibraryBackup(
      sourceHome: appHome,
      destinationParent: backups,
      books: [book],
      writeSqliteSnapshot: (dest) =>
          File(dest).writeAsStringSync('This is NOT a SQLite database'),
    ), throwsFormatException);
    expect(await backups.list().toList(), isEmpty);
  });

  test('batch size limits validated before creating temp directories',
      () async {
    await expectLater(exportPortableLibraryBackup(
      sourceHome: appHome,
      destinationParent: backups,
      books: const [],
      maxBooks: 10001,
      writeSqliteSnapshot: (_) =>
          fail('The snapshot writer must not run'),
    ), throwsArgumentError);
    expect(await backups.list().toList(), isEmpty);
  });

  test('exports are independent and never overwrite an earlier backup',
      () async {
    await addBook('one.txt', 'An ebook.');
    final first = await store.exportLibraryBackup(backups);
    final second = await store.exportLibraryBackup(backups);
    expect(first.directory.path, isNot(second.directory.path));
    expect(await first.directory.exists(), isTrue);
    expect(await second.directory.exists(), isTrue);
    expect(await backups.list().length, 2);
  });
}
