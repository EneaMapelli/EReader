import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/pdf_visual_bookmark.dart';
import 'package:ereader/features/reader/pdf_visual_bookmarks_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;
  late LibraryStore store;
  late String bookId;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-pdf-sheet-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    final file = File(p.join(home.path, 'scanned.pdf'));
    await file.writeAsBytes('%PDF-1.4\nscanned fixture\n'.codeUnits);
    bookId = (await store.importFile(file.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  Future<void> openSheet(WidgetTester tester, {
    int currentPage = 7,
    int pageCount = 20,
    ValueChanged<int>? onPageChosen,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => ElevatedButton(
          child: const Text('PDF bookmarks'),
          onPressed: () async {
            final result = await showPdfVisualBookmarks(
              context: context,
              store: store,
              bookId: bookId,
              currentPage: currentPage,
              pageCount: pageCount,
            );
            if (result != null) onPageChosen?.call(result);
          },
        )),
      ),
    ));
    await tester.tap(find.text('PDF bookmarks'));
    await tester.pumpAndSettle();
  }

  testWidgets('save scanned-PDF page with user title and return its page',
      (tester) async {
    final chosen = <int>[];
    await openSheet(tester, onPageChosen: chosen.add);
    expect(find.text('No saved PDF pages yet.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-bookmark-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(
        const ValueKey('pdf-bookmark-title')), 'Map insert');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.listPdfVisualBookmarks(bookId), hasLength(1));
    expect(store.listPdfVisualBookmarks(bookId).single.title, 'Map insert');
    expect(store.listPdfVisualBookmarks(bookId).single.pageNumber, 7);
    expect(store.getBook(bookId)!.progressOffset, 0);
    expect(store.listBookmarks(bookId), isEmpty);

    await tester.tap(find.text('Map insert'));
    await tester.pumpAndSettle();
    expect(chosen, [7]);
  });

  testWidgets('delete a visual bookmark without touching speech progress',
      (tester) async {
    store.addPdfVisualBookmark(PdfVisualBookmark(
      id: 'marked', bookId: bookId, title: 'Chapter diagram',
      pageNumber: 3, createdAt: DateTime.utc(2026, 10, 29),
    ));
    await openSheet(tester);
    expect(find.text('Chapter diagram'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete PDF page bookmark'));
    await tester.pumpAndSettle();
    expect(find.text('No saved PDF pages yet.'), findsOneWidget);
    expect(store.listPdfVisualBookmarks(bookId), isEmpty);
    expect(store.getBook(bookId)!.progressAnchor, isNull);
  });

  testWidgets('bookmark beyond changed document cannot navigate',
      (tester) async {
    final chosen = <int>[];
    store.addPdfVisualBookmark(PdfVisualBookmark(
      id: 'older', bookId: bookId, title: 'Missing page',
      pageNumber: 15, createdAt: DateTime.utc(2026, 10, 29),
    ));
    await openSheet(tester, currentPage: 2,
        pageCount: 2, onPageChosen: chosen.add);
    expect(find.text('Page 15 is not in this PDF'), findsOneWidget);
    final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Missing page'),
            matching: find.byType(ListTile)));
    expect(tile.onTap, isNull);
    expect(chosen, isEmpty);
    await tester.tap(find.byTooltip('Delete PDF page bookmark'));
    await tester.pumpAndSettle();
    expect(store.listPdfVisualBookmarks(bookId), isEmpty);
  });
}
