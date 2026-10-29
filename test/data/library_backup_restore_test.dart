import 'dart:convert';
import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/data/library_backup_restore.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/book_bookmark.dart';
import 'package:ereader/domain/pdf_visual_bookmark.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory exports;
  late Directory targetHome;
  late LibraryStore source;
  late LibraryStore target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-restore-');
    exports = Directory(p.join(root.path, 'exports'));
    targetHome = Directory(p.join(root.path, 'target'));
    await exports.create();
    source = LibraryStore(homeDirectory: Directory(
        p.join(root.path, 'source')));
    target = LibraryStore(homeDirectory: targetHome);
    await source.initialize();
    await target.initialize();
  });

  tearDown(() async {
    source.dispose();
    target.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> add(LibraryStore store, String fileName,
      String contents) async {
    final file = File(p.join(root.path, fileName));
    await file.writeAsString(contents);
    return (await store.importFile(file.path)).id;
  }

  test('preview is read-only; new books restore title, anchors and bookmarks',
      () async {
    final id = await add(source, 'novel.txt', 'Hello original ebook.');
    final anchor = const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'txt', localOffset: 6);
    await source.savePosition(id, 6, anchor: anchor);
    source.updateBookMetadata(id, title: 'My revised book',
        author: 'Writer', series: 'Saga', language: 'it-IT');
    await source.addBookmark(BookBookmark(
      id: 'user-bookmark-1', bookId: id, title: 'Start',
      globalOffset: 6, anchor: anchor,
      createdAt: DateTime.utc(2026, 10, 26),
    ));
    final exported = await source.exportLibraryBackup(exports);
    final before = await target.previewLibraryRestore(exported.directory);
    expect(before.total, 1);
    expect(before.availableToImport, 1);
    expect(before.alreadyPresent, 0);
    expect(before.bookmarksToImport, 1);
    expect(target.books, isEmpty,
        reason: 'Read-only backup preview must not touch the target');

    final result = await target.restoreLibraryBackup(exported.directory);
    expect(result.added, 1);
    expect(result.skipped, 0);
    expect(result.bookmarksImported, 1);
    final restored = target.getBook(id)!;
    expect(restored.title, 'My revised book');
    expect(restored.author, 'Writer');
    expect(restored.series, 'Saga');
    expect(restored.language, 'it-IT');
    expect(restored.progressOffset, 6);
    expect(restored.progressAnchor!.sourceId, 'txt');
    expect(restored.progressAnchor!.localOffset, 6);
    expect(restored.localPath,
        p.join(targetHome.path, 'books', '$id.txt'));
    expect(await File(restored.localPath).readAsString(),
        'Hello original ebook.');
    final marks = target.listBookmarks(id);
    expect(marks, hasLength(1));
    expect(marks.single.title, 'Start');
    expect(marks.single.globalOffset, 6);
    expect(marks.single.anchor!.localOffset, 6);
    expect(marks.single.id, startsWith('$id:'));
    expect(marks.single.id.length, lessThanOrEqualTo(128));

    final again = await target.restoreLibraryBackup(exported.directory);
    expect(again.added, 0);
    expect(again.skipped, 1);
    expect(target.listBookmarks(id), hasLength(1));
  });

  test('existing local books, positions and bookmarks are never overwritten',
      () async {
    final id = await add(source, 'shared.txt', 'Identical source bytes');
    await source.savePosition(id, 3);
    final original = await source.exportLibraryBackup(exports);
    await add(target, 'shared.txt', 'Identical source bytes');
    await target.savePosition(id, 17);
    target.updateBookMetadata(id, title: 'My local version');
    await target.addBookmark(BookBookmark(
      id: 'local-marker', bookId: id, title: 'Local',
      globalOffset: 17, createdAt: DateTime.utc(2026, 10, 27),
    ));
    final report = await target.previewLibraryRestore(original.directory);
    expect(report.availableToImport, 0);
    expect(report.alreadyPresent, 1);
    final restored = await target.restoreLibraryBackup(original.directory);
    expect(restored.added, 0);
    expect(restored.skipped, 1);
    expect(target.getBook(id)!.progressOffset, 17);
    expect(target.getBook(id)!.title, 'My local version');
    expect(target.listBookmarks(id).single.id, 'local-marker');
  });

  test('a corrupted backup fails before importing any otherwise valid book',
      () async {
    await add(source, 'a.txt', 'Good untouched source.');
    final badId = await add(source, 'b.txt', 'Corrupted file later.');
    final exported = await source.exportLibraryBackup(exports);
    await File(p.join(exported.directory.path, 'books', '$badId.txt'))
        .writeAsString('Tampered source');
    await expectLater(target.restoreLibraryBackup(exported.directory),
        throwsFormatException);
    expect(target.books, isEmpty);
    expect(await Directory(p.join(targetHome.path, 'books')).list().toList(),
        isEmpty);
  });

  test('manifest traversal and rewritten source identities are rejected',
      () async {
    await add(source, 'one.txt', 'Protected source bytes');
    final exported = await source.exportLibraryBackup(exports);
    final file = File(p.join(exported.directory.path, 'manifest.json'));
    final manifest = jsonDecode(await file.readAsString()) as Map;
    final first = (manifest['books'] as List).single as Map;
    first['file'] = '../outside.txt';
    await file.writeAsString(jsonEncode(manifest));
    await expectLater(inspectLibraryBackup(exported.directory),
        throwsFormatException);
    expect(target.books, isEmpty);
  });

  test('missing backup book cannot partially restore catalog', () async {
    final id = await add(source, 'gone.txt', 'Stored private book');
    final exported = await source.exportLibraryBackup(exports);
    await File(p.join(exported.directory.path, 'books', '$id.txt')).delete();
    await expectLater(target.restoreLibraryBackup(exported.directory),
        throwsFormatException);
    expect(target.books, isEmpty);
  });

  test('restoration excludes past cloud consent and per-book TTS state',
      () async {
    final id = await add(source, 'cloud.txt', 'A book with history');
    // Deliberately include a cloud consent row in the exported database.
    await source.configureCloudConsent(id, 'openai-speech',
      allowed: true, maxCharacters: 2000);
    final exported = await source.exportLibraryBackup(exports);
    await target.restoreLibraryBackup(exported.directory);
    final consent = target.getConsent(id, 'openai-speech');
    expect(consent.allowed, isFalse);
    expect(consent.maxCharacters, 0);
  });

  test('PDF page restores without changing narrated source position',
      () async {
    final pdf = File(p.join(root.path, 'sample.pdf'));
    await pdf.writeAsBytes('%PDF-1.4\nsample static test fixture'
        .codeUnits);
    final saved = await source.importFile(pdf.path);
    await source.savePosition(saved.id, 5);
    source.savePdfVisualPage(saved.id, 7);
    final exported = await source.exportLibraryBackup(exports);
    final restored = await target.restoreLibraryBackup(exported.directory);
    expect(restored.added, 1);
    expect(target.getBook(saved.id)!.progressOffset, 5);
    expect(target.getPdfVisualPage(saved.id), 7);
  });

  test('v22 export/restore preserves scanned PDF visual bookmarks',
      () async {
    final pdf = File(p.join(root.path, 'scanned.pdf'));
    await pdf.writeAsBytes('%PDF-1.4\\nimage-only fixture'.codeUnits);
    final saved = await source.importFile(pdf.path);
    source.savePdfVisualPage(saved.id, 18);
    source.addPdfVisualBookmark(PdfVisualBookmark(
      id: 'original-page-mark',
      bookId: saved.id, title: 'Illustrated appendix',
      pageNumber: 18, createdAt: DateTime.utc(2026, 10, 29),
    ));
    source.addPdfVisualBookmark(PdfVisualBookmark(
      id: 'cover-page',
      bookId: saved.id, title: 'Cover',
      pageNumber: 1, createdAt: DateTime.utc(2026, 10, 29),
    ));
    final exported = await source.exportLibraryBackup(exports);
    final preview = await target.previewLibraryRestore(exported.directory);
    expect(preview.bookmarksToImport, 2);
    expect(target.books, isEmpty);
    final result = await target.restoreLibraryBackup(exported.directory);
    expect(result.added, 1);
    expect(result.bookmarksImported, 2);
    expect(target.getPdfVisualPage(saved.id), 18);
    final marks = target.listPdfVisualBookmarks(saved.id);
    expect(marks.map((m) => m.pageNumber), [1, 18]);
    expect(marks.map((m) => m.title),
        ['Cover', 'Illustrated appendix']);
    expect(marks.every((m) => m.id != 'original-page-mark'), isTrue);
    expect(target.listBookmarks(saved.id), isEmpty);
    expect(target.getBook(saved.id)!.progressAnchor, isNull);
    expect(target.getBook(saved.id)!.progressOffset, 0);

    final duplicate = await target.restoreLibraryBackup(exported.directory);
    expect(duplicate.added, 0);
    expect(duplicate.skipped, 1);
    expect(target.listPdfVisualBookmarks(saved.id), hasLength(2));
  });

  test('portable restore also accepts legacy v17 and v18 database backups',
      () async {
    final id = await add(source, 'older.txt',
        'Portable source bytes survive a schema upgrade');
    for (final version in [17, 18]) {
      final exported = await source.exportLibraryBackup(exports);
      final db = sqlite3.open(
          p.join(exported.directory.path, 'library.sqlite'));
      db.execute('DROP TABLE book_collection_members');
      db.execute('DROP TABLE book_collections');
      db.execute('ALTER TABLE books DROP COLUMN reading_status');
      db.execute('ALTER TABLE books DROP COLUMN is_favorite');
      db.execute('DROP TABLE pdf_visual_bookmarks');
      if (version == 17) {
        db.execute('DROP TABLE reading_preferences');
      }
      db.execute('PRAGMA user_version = $version');
      db.dispose();
      final inspected = await inspectLibraryBackup(exported.directory);
      expect(inspected.books.single.id, id);
      final preview = await target.previewLibraryRestore(exported.directory);
      expect(preview.total, 1);
      final result = await target.restoreLibraryBackup(exported.directory);
      if (version == 17) {
        expect(result.added, 1);
      } else {
        expect(result.skipped, 1);
      }
    }
    expect(target.getBook(id), isNotNull);
  });

  test('v22 backup preserves starred books but never overwrites local stars',
      () async {
    final a = await add(source, 'liked.txt', 'A favorite manuscript.');
    final b = await add(source, 'other.txt', 'Another manuscript.');
    source.setBookFavorite(a, true);
    expect(source.getBook(b)!.isFavorite, isFalse);
    final exported = await source.exportLibraryBackup(exports);

    final preview = await target.previewLibraryRestore(exported.directory);
    expect(preview.availableToImport, 2);
    final restored = await target.restoreLibraryBackup(exported.directory);
    expect(restored.added, 2);
    expect(target.getBook(a)!.isFavorite, isTrue);
    expect(target.getBook(b)!.isFavorite, isFalse);

    target.setBookFavorite(a, false);
    target.setBookFavorite(b, true);
    final repeat = await target.restoreLibraryBackup(exported.directory);
    expect(repeat.added, 0);
    expect(repeat.skipped, 2);
    expect(target.getBook(a)!.isFavorite, isFalse);
    expect(target.getBook(b)!.isFavorite, isTrue);
  });

  test('mismatched manifest star and SQLite star fail before import',
      () async {
    final id = await add(source, 'tampered.txt', 'Source file unchanged.');
    source.setBookFavorite(id, true);
    final exported = await source.exportLibraryBackup(exports);
    final manifestFile =
        File(p.join(exported.directory.path, 'manifest.json'));
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    final entry = (manifest['books'] as List).single as Map;
    expect(entry['favorite'], isTrue);
    entry['favorite'] = false;
    await manifestFile.writeAsString(jsonEncode(manifest));
    await expectLater(target.previewLibraryRestore(exported.directory),
        throwsFormatException);
    await expectLater(target.restoreLibraryBackup(exported.directory),
        throwsFormatException);
    expect(target.books, isEmpty);
  });

  test('v19 backup without favorite field restores books as unstarred',
      () async {
    final id = await add(source, 'old.txt', 'Source text from old snapshot.');
    final exported = await source.exportLibraryBackup(exports);
    final db = sqlite3.open(
        p.join(exported.directory.path, 'library.sqlite'));
    db.execute('DROP TABLE book_collection_members');
    db.execute('DROP TABLE book_collections');
    db.execute('ALTER TABLE books DROP COLUMN reading_status');
    db.execute('ALTER TABLE books DROP COLUMN is_favorite');
    db.execute('PRAGMA user_version = 19');
    db.dispose();
    final manifestFile =
        File(p.join(exported.directory.path, 'manifest.json'));
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    final entry = (manifest['books'] as List).single as Map;
    entry.remove('favorite');
    entry.remove('readingStatus');
    entry.remove('collections');
    await manifestFile.writeAsString(jsonEncode(manifest));
    final inspected = await inspectLibraryBackup(exported.directory);
    expect(inspected.books.single.isFavorite, isFalse);
    expect(inspected.books.single.readingStatus, BookReadingStatus.toRead);
    await target.restoreLibraryBackup(exported.directory);
    expect(target.getBook(id)!.isFavorite, isFalse);
  });

  test('portable v22 backup restores explicit shelves but preserves local choices',
      () async {
    final reading = await add(source, 'current.txt', 'Reading shelf source.');
    final finished = await add(source, 'done.txt', 'Finished shelf source.');
    source.setBookReadingStatus(reading, BookReadingStatus.reading);
    source.setBookReadingStatus(finished, BookReadingStatus.finished);
    final exported = await source.exportLibraryBackup(exports);
    final preview = await target.previewLibraryRestore(exported.directory);
    expect(preview.availableToImport, 2);
    final restored = await target.restoreLibraryBackup(exported.directory);
    expect(restored.added, 2);
    expect(target.getBook(reading)!.readingStatus,
        BookReadingStatus.reading);
    expect(target.getBook(finished)!.readingStatus,
        BookReadingStatus.finished);
    expect(target.getBook(finished)!.progressOffset, 0);
    expect(target.getBook(finished)!.lastOpenedAt, isNull);

    target.setBookReadingStatus(finished, BookReadingStatus.toRead);
    final again = await target.restoreLibraryBackup(exported.directory);
    expect(again.skipped, 2);
    expect(target.getBook(finished)!.readingStatus,
        BookReadingStatus.toRead,
        reason: 'Existing book shelf selection must not be overwritten');
  });

  test('tampered v22 reading shelf manifest is rejected before import',
      () async {
    final id = await add(source, 'protected.txt', 'Immutable source.');
    source.setBookReadingStatus(id, BookReadingStatus.finished);
    final exported = await source.exportLibraryBackup(exports);
    final manifestFile =
        File(p.join(exported.directory.path, 'manifest.json'));
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    final entry = (manifest['books'] as List).single as Map;
    expect(entry['readingStatus'], 'finished');
    entry['readingStatus'] = 'reading';
    await manifestFile.writeAsString(jsonEncode(manifest));
    await expectLater(target.previewLibraryRestore(exported.directory),
        throwsFormatException);
    expect(target.books, isEmpty);
  });

  test('v20 backup has no shelf metadata and imports To read by default',
      () async {
    final id = await add(source, 'legacy20.txt', 'Legacy shelf state.');
    final exported = await source.exportLibraryBackup(exports);
    final snapshot = sqlite3.open(
        p.join(exported.directory.path, 'library.sqlite'));
    snapshot.execute('DROP TABLE book_collection_members');
    snapshot.execute('DROP TABLE book_collections');
    snapshot.execute('ALTER TABLE books DROP COLUMN reading_status');
    snapshot.execute('PRAGMA user_version = 20');
    snapshot.dispose();
    final manifestFile =
        File(p.join(exported.directory.path, 'manifest.json'));
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    final entry = (manifest['books'] as List).single as Map;
    entry.remove('readingStatus');
    entry.remove('collections');
    await manifestFile.writeAsString(jsonEncode(manifest));
    final verified = await inspectLibraryBackup(exported.directory);
    expect(verified.books.single.readingStatus, BookReadingStatus.toRead);
    final restored = await target.restoreLibraryBackup(exported.directory);
    expect(restored.added, 1);
    expect(target.getBook(id)!.readingStatus, BookReadingStatus.toRead);
  });

  test('malformed PDF page bookmark in v22 backup fails closed', () async {
    final pdf = File(p.join(root.path, 'guard.pdf'));
    await pdf.writeAsBytes('%PDF-1.4\\ntamper test'.codeUnits);
    final id = (await source.importFile(pdf.path)).id;
    source.addPdfVisualBookmark(PdfVisualBookmark(
      id: 'good-mark', bookId: id,
      title: 'Sample', pageNumber: 3,
      createdAt: DateTime.utc(2026, 10, 29),
    ));
    final exported = await source.exportLibraryBackup(exports);
    final db = sqlite3.open(
        p.join(exported.directory.path, 'library.sqlite'));
    db.execute('UPDATE pdf_visual_bookmarks SET title = ?', ['\n']);
    db.dispose();
    await expectLater(inspectLibraryBackup(exported.directory),
        throwsFormatException);
    expect(target.books, isEmpty);
  });

  test('corrupted SQLite backup fails closed before copying books',
      () async {
    await add(source, 'book.txt', 'One unchanged ebook');
    final exported = await source.exportLibraryBackup(exports);
    final db = File(p.join(exported.directory.path, 'library.sqlite'));
    await db.writeAsString('Corrupt database contents', flush: true);
    await expectLater(target.restoreLibraryBackup(exported.directory),
        throwsA(anything));
    expect(target.books, isEmpty);
  });

  test('existing unrelated managed file cannot be silently overwritten',
      () async {
    final id = await add(source, 'book.txt', 'Original backup bytes');
    final exported = await source.exportLibraryBackup(exports);
    final conflicting = File(p.join(targetHome.path, 'books', '$id.txt'));
    await conflicting.writeAsString('Different private data');
    await expectLater(target.restoreLibraryBackup(exported.directory),
        throwsFormatException);
    expect(await conflicting.readAsString(), 'Different private data');
    expect(target.books, isEmpty);
  });

  test('backup folder inside the active library is forbidden', () async {
    await add(source, 'novel.txt', 'Local library original');
    final exported = await source.exportLibraryBackup(exports);
    // A valid export is accepted only from another independent folder.
    expect(await target.previewLibraryRestore(exported.directory),
        isA<LibraryRestorePreview>());
    await expectLater(target.restoreLibraryBackup(targetHome),
        throwsFormatException);
    expect(target.books, isEmpty);
  });
}
