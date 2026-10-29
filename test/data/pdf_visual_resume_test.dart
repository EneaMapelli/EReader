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
    root = await Directory.systemTemp.createTemp('ereader-pdf-position-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> pdf(String name) async {
    // Import checks signature; no native PDF renderer is used by these tests.
    final file = File(p.join(root.path, name));
    await file.writeAsBytes('%PDF-1.4\nfixture\n'.codeUnits);
    return (await store.importFile(file.path)).id;
  }

  test('page defaults to one and persists across SQLite restart', () async {
    final book = await pdf('book.pdf');
    expect(store.getPdfVisualPage(book), 1);
    store.savePdfVisualPage(book, 9);
    expect(store.getPdfVisualPage(book), 9);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getPdfVisualPage(book), 9);
    expect(store.getBook(book)!.progressOffset, 0);
    expect(store.getBook(book)!.progressAnchor, isNull);
  });

  test('PDF visual and spoken positions never overwrite each other', () async {
    final book = await pdf('separate.pdf');
    await store.savePosition(book, 42,
      anchor: const ReadingAnchor(
        kind: AnchorKind.pdfPage, sourceId: '2', localOffset: 12,
      ),
    );
    store.savePdfVisualPage(book, 16);
    expect(store.getBook(book)!.progressAnchor!.sourceId, '2');
    expect(store.getBook(book)!.progressOffset, 42);

    await store.savePosition(book, 79,
      anchor: const ReadingAnchor(
        kind: AnchorKind.pdfPage, sourceId: '4', localOffset: 9,
      ),
    );
    expect(store.getPdfVisualPage(book), 16);
    expect(store.getBook(book)!.progressAnchor!.sourceId, '4');
  });

  test('unreadable/scanned PDF needs no text to retain its visual page',
      () async {
    final book = await pdf('scan.pdf');
    // A scanned PDF can have no extraction ranges or TTS source anchor.
    store.savePdfVisualPage(book, 32);
    await store.markBookOpened(book);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.lastOpenedBook?.id, book);
    expect(store.getPdfVisualPage(book), 32);
    expect(store.getBook(book)!.progressAnchor, isNull);
  });

  test('invalid pages, unknown IDs and non-PDF records are rejected',
      () async {
    final book = await pdf('valid.pdf');
    final txt = File(p.join(root.path, 'plain.txt'));
    await txt.writeAsString('Plain text only.');
    final other = (await store.importFile(txt.path)).id;

    expect(() => store.savePdfVisualPage(book, 0), throwsRangeError);
    expect(() => store.savePdfVisualPage(book, 100001), throwsRangeError);
    expect(() => store.savePdfVisualPage('absent', 3), throwsStateError);
    expect(() => store.savePdfVisualPage(other, 3), throwsStateError);
    expect(() => store.getPdfVisualPage(other), throwsStateError);
    expect(() => store.getPdfVisualPage('absent'), throwsStateError);
    expect(store.getPdfVisualPage(book), 1);
  });

  test('v14 to v15 migration leaves reading anchor and last open intact',
      () async {
    final book = await pdf('old.pdf');
    await store.markBookOpened(book);
    await store.savePosition(book, 17,
      anchor: const ReadingAnchor(
        kind: AnchorKind.pdfPage, sourceId: '3', localOffset: 2,
      ),
    );
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('ALTER TABLE books DROP COLUMN pdf_visual_page');
    db.execute('PRAGMA user_version = 14');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getPdfVisualPage(book), 1);
    expect(store.getBook(book)!.progressOffset, 17);
    expect(store.getBook(book)!.progressAnchor!.sourceId, '3');
    expect(store.lastOpenedBook?.id, book);
    store.savePdfVisualPage(book, 3);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getPdfVisualPage(book), 3);
  });

  test('v13 upgrades through v14 and v15 without losing legacy anchors',
      () async {
    final book = await pdf('older.pdf');
    await store.savePosition(book, 8);
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('ALTER TABLE books DROP COLUMN pdf_visual_page');
    db.execute('ALTER TABLE books DROP COLUMN last_opened_at');
    db.execute('PRAGMA user_version = 13');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getPdfVisualPage(book), 1);
    expect(store.getBook(book)!.progressOffset, 8);
    expect(store.lastOpenedBook, isNull);
    final dbAfter = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(dbAfter.select('PRAGMA user_version').first['user_version'], 22);
    dbAfter.dispose();
  });

  test('removing a PDF also removes its visual position', () async {
    final book = await pdf('removed.pdf');
    store.savePdfVisualPage(book, 8);
    await store.removeBook(book);
    expect(() => store.getPdfVisualPage(book), throwsStateError);
  });
}
