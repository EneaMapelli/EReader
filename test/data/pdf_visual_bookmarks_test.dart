import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/pdf_visual_bookmark.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory home;
  late LibraryStore store;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-pdf-marks-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  Future<String> importPdf(String name, String suffix) async {
    final file = File(p.join(home.path, name));
    await file.writeAsBytes('%PDF-1.4\n$suffix\n'.codeUnits);
    return (await store.importFile(file.path)).id;
  }

  PdfVisualBookmark mark(String id, String bookId, int page,
          {String title = 'My page'}) =>
      PdfVisualBookmark(
        id: id,
        bookId: bookId,
        title: title,
        pageNumber: page,
        createdAt: DateTime.utc(2026, 10, 29),
      );

  test('fresh v21 libraries retain the v19 PDF visual page bookmark table',
      () {
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').first['user_version'], 21);
    expect(db.select(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name = 'pdf_visual_bookmarks'",
    ), hasLength(1));
    db.dispose();
  });

  test('scanned PDF page marks survive restart without text-layer anchors',
      () async {
    final id = await importPdf('scanned.pdf', 'no text layer');
    store.savePdfVisualPage(id, 32);
    store.addPdfVisualBookmark(mark('one', id, 4, title: 'Figure 4'));
    store.addPdfVisualBookmark(mark('two', id, 32, title: 'Page to return'));
    expect(store.listPdfVisualBookmarks(id).map((e) => e.pageNumber),
        [4, 32]);
    store.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.listPdfVisualBookmarks(id).map((e) => e.title),
        ['Figure 4', 'Page to return']);
    expect(store.getPdfVisualPage(id), 32);
    expect(store.getBook(id)!.progressAnchor, isNull);
    expect(store.getBook(id)!.progressOffset, 0);
  });

  test('PDF page bookmarks remain separate from TTS source bookmarks',
      () async {
    final id = await importPdf('mixed.pdf', 'both channels');
    await store.savePosition(id, 42, anchor: const ReadingAnchor(
      kind: AnchorKind.pdfPage,
      sourceId: '2',
      localOffset: 12,
    ));
    store.addPdfVisualBookmark(mark('visual', id, 15));
    expect(store.listPdfVisualBookmarks(id), hasLength(1));
    expect(store.listBookmarks(id), isEmpty);
    expect(store.getPdfVisualPage(id), 1);
    expect(store.getBook(id)!.progressOffset, 42);
    expect(store.getBook(id)!.progressAnchor!.sourceId, '2');
    store.deletePdfVisualBookmark(id, 'visual');
    expect(store.listPdfVisualBookmarks(id), isEmpty);
    expect(store.getBook(id)!.progressOffset, 42);
  });

  test('visual bookmark is bound to its book and deleted with the PDF',
      () async {
    final a = await importPdf('a.pdf', 'document a');
    final b = await importPdf('b.pdf', 'document b');
    store.addPdfVisualBookmark(mark('a1', a, 3));
    store.addPdfVisualBookmark(mark('b1', b, 7));
    store.deletePdfVisualBookmark(b, 'a1');
    expect(store.listPdfVisualBookmarks(a), hasLength(1));
    await store.removeBook(a);
    expect(store.listPdfVisualBookmarks(b).single.pageNumber, 7);
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(db.select('SELECT * FROM pdf_visual_bookmarks WHERE book_id = ?',
        [a]), isEmpty);
    db.dispose();
  });

  test('bookmark validation and non-PDF books fail closed', () async {
    final pdfId = await importPdf('pdf.pdf', 'source');
    final textFile = File(p.join(home.path, 'plain.txt'));
    await textFile.writeAsString('Plain text');
    final txtId = (await store.importFile(textFile.path)).id;
    expect(() => store.addPdfVisualBookmark(mark('invalid', pdfId, 0)),
        throwsFormatException);
    expect(() => store.addPdfVisualBookmark(mark('invalid', pdfId, 100001)),
        throwsFormatException);
    expect(() => store.addPdfVisualBookmark(
        mark('invalid', pdfId, 4, title: '')), throwsFormatException);
    expect(() => store.addPdfVisualBookmark(mark('text', txtId, 5)),
        throwsStateError);
    expect(() => store.listPdfVisualBookmarks(txtId), throwsStateError);
    expect(() => store.addPdfVisualBookmark(mark('unknown', 'missing', 5)),
        throwsStateError);
    expect(store.listPdfVisualBookmarks(pdfId), isEmpty);
  });

  test('v18 upgrades without losing earlier PDF visual position', () async {
    final id = await importPdf('upgrade.pdf', 'old installation');
    store.savePdfVisualPage(id, 11);
    store.dispose();
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    db.execute('DROP TABLE pdf_visual_bookmarks');
    db.execute('PRAGMA user_version = 18');
    db.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.getPdfVisualPage(id), 11);
    expect(store.listPdfVisualBookmarks(id), isEmpty);
    store.addPdfVisualBookmark(mark('after-migration', id, 11));
    expect(store.listPdfVisualBookmarks(id), hasLength(1));
  });
}
