import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/library_full_text.dart';
import 'package:ereader/features/library/library_full_text_search_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;
  late LibraryStore store;
  late String firstId;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-fts-widget-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    final file = File(p.join(home.path, 'atlas.txt'));
    await file.writeAsString('A green dragon climbed the mountain.');
    firstId = (await store.importFile(file.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  Future<void> openSheet(
      WidgetTester tester, {
        void Function(BookRecord, LibraryFullTextJump?)? onOpenBook}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => LibraryFullTextSearchSheet(
                store: store, onOpenBook: onOpenBook),
          ),
          child: const Text('Search books'),
        )),
      ),
    ));
    await tester.tap(find.text('Search books'));
    await tester.pumpAndSettle();
  }

  testWidgets('opt-in, index, literal search, open existing book',
      (tester) async {
    BookRecord? opened;
    LibraryFullTextJump? destination;
    await openSheet(tester, onOpenBook: (book, jump) {
      opened = book;
      destination = jump;
    });
    expect(store.isFullTextIndexEnabled, isFalse);
    expect(find.textContaining('Enable indexing'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fts-enabled')));
    await tester.pumpAndSettle();
    expect(store.isFullTextIndexEnabled, isTrue);
    expect(store.fullTextIndexedBooks, 0);
    await tester.tap(find.byKey(const ValueKey('fts-index-next')));
    await tester.pumpAndSettle();
    expect(store.fullTextIndexedBooks, 1);

    await tester.enterText(find.byKey(const ValueKey('fts-query')), 'dragon');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('fts-hit-$firstId')), findsOneWidget);
    expect(find.textContaining('green dragon'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('fts-hit-$firstId')));
    await tester.pumpAndSettle();
    expect(opened?.id, firstId);
    expect(destination, isNotNull);
    expect(destination!.sourceOffset, 8);
    expect(destination!.expectedText.toLowerCase(), 'dragon');
    expect(store.getBook(firstId), isNotNull);
  });

  testWidgets('disable confirmation cancels then deletes private index',
      (tester) async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    await openSheet(tester);
    final toggle = find.byKey(const ValueKey('fts-enabled'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Disable full-text indexing?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.isFullTextIndexEnabled, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete index and disable'));
    await tester.pumpAndSettle();
    expect(store.isFullTextIndexEnabled, isFalse);
    expect(store.fullTextIndexedBooks, 0);
    expect(store.books, hasLength(1));
  });

  testWidgets('manual changed-book check updates the pending count',
      (tester) async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    final managed = File(store.getBook(firstId)!.localPath);
    await managed.writeAsString('New book text about a golden owl.');
    await openSheet(tester);
    expect(store.fullTextPendingBooks, 0);
    await tester.tap(find.byKey(const ValueKey('fts-check-changes')));
    await tester.pumpAndSettle();
    expect(store.fullTextPendingBooks, 1);
    expect(store.searchIndexedBookContents('dragon'), isEmpty);
    expect(find.textContaining('1 changed books queued'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fts-index-next')));
    await tester.pumpAndSettle();
    expect(store.searchIndexedBookContents('owl'), hasLength(1));
    expect(store.fullTextPendingBooks, 0);
  });

  testWidgets('reset needs confirmation and permits reindex',
      (tester) async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('fts-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Reset full-text index?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.fullTextIndexedBooks, 1);

    await tester.tap(find.byKey(const ValueKey('fts-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(store.fullTextIndexedBooks, 0);
    expect(store.fullTextPendingBooks, 1);
    expect(store.isFullTextIndexEnabled, isTrue);
  });
}
