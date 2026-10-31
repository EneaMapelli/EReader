import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;
  late Map<String, String> ids;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-responsive-library-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    ids = {};
    for (final title in ['Alpha', 'Beta', 'Gamma']) {
      final file = File(p.join(root.path, title + '.txt'));
      await file.writeAsString('Book ' + title + ' contents.');
      ids[title] = (await store.importFile(file.path)).id;
    }
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> showNarrow(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
  }

  testWidgets('phone starts with compact filters but visible catalog and search',
      (tester) async {
    await showNarrow(tester);
    expect(find.byKey(const ValueKey('library-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-compact-filters')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-sort')), findsNothing);
    expect(find.byKey(const ValueKey('library-result-count')), findsOneWidget);
    expect(find.text('Showing 3 of 3 books'), findsOneWidget);
    expect(find.byKey(ValueKey('library-book-row-' + ids['Alpha']!)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact filters preserve selections after closing and resetting',
      (tester) async {
    await showNarrow(tester);
    await tester.tap(find.byKey(const ValueKey('library-compact-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-sort')), findsOneWidget);
    final txt = find.byKey(const ValueKey('library-filter-txt'));
    await tester.ensureVisible(txt);
    await tester.tap(txt);
    await tester.pumpAndSettle();
    expect(find.text('Filters & sort (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-compact-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-filter-txt')), findsNothing);
    expect(find.text('Showing 3 of 3 books'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-reset-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Filters & sort'), findsOneWidget);
    expect(store.books, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact book More retains shelf, edit, collections and remove',
      (tester) async {
    await showNarrow(tester);
    final id = ids['Alpha']!;
    expect(find.byKey(ValueKey('library-shelf-' + id)), findsNothing);
    expect(find.byKey(ValueKey('library-favorite-' + id)), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('library-more-' + id)));
    await tester.pumpAndSettle();
    expect(find.text('Shelf: To read'), findsOneWidget);
    expect(find.text('Shelf: Reading'), findsOneWidget);
    expect(find.text('Shelf: Finished'), findsOneWidget);
    final selectedShelf = tester.widget<CheckedPopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Shelf: To read'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    expect(selectedShelf.checked, isTrue,
        reason: 'Screen readers must expose the current shelf choice');
    expect(find.text('Book collections'), findsOneWidget);
    expect(find.text('Edit book details'), findsOneWidget);
    expect(find.text('Remove book'), findsOneWidget);
    await tester.tap(find.text('Shelf: Reading'));
    await tester.pumpAndSettle();
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.reading);
    expect(store.getBook(id)!.progressOffset, 0);
    await tester.tap(find.byKey(ValueKey('library-favorite-' + id)));
    await tester.pump();
    expect(store.getBook(id)!.isFavorite, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact catalog search preserves full records on clear',
      (tester) async {
    await showNarrow(tester);
    final search = find.byKey(const ValueKey('library-search'));
    await tester.enterText(search, 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 3 books'), findsOneWidget);
    expect(find.byKey(ValueKey('library-book-row-' + ids['Alpha']!)),
        findsOneWidget);
    expect(find.byKey(ValueKey('library-book-row-' + ids['Beta']!)),
        findsNothing);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.text('Showing 3 of 3 books'), findsOneWidget);
    expect(store.books, hasLength(3));
  });

  testWidgets('short phone retains an independently scrollable filter panel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 480));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(const ValueKey('library-compact-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-compact-filter-scroll')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('library-result-count')), findsOneWidget);
    expect(find.byType(ListView), findsWidgets,
        reason: 'Book list must remain separately scrollable');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide catalog keeps direct shelf controls without compact toggle',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    expect(find.byKey(const ValueKey('library-compact-filters')), findsNothing);
    expect(find.byKey(const ValueKey('library-sort')), findsOneWidget);
    expect(find.byKey(ValueKey('library-shelf-' + ids['Beta']!)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('200 percent text keeps title legible and favorite in More',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: LibraryScreen(store: store),
    ));
    await tester.pumpAndSettle();
    final id = ids['Alpha']!;
    final row = find.byKey(ValueKey('library-book-row-' + id));
    final tile = tester.widget<ListTile>(row);
    expect(tile.isThreeLine, isTrue);
    expect((tile.title! as Text).maxLines, 2);
    expect(find.byKey(ValueKey('library-favorite-' + id)), findsNothing);
    expect(find.byKey(ValueKey('library-more-' + id)), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(ValueKey('library-more-' + id)));
    await tester.pumpAndSettle();
    expect(find.text('Add to favorites'), findsOneWidget);
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();
    expect(store.getBook(id)!.isFavorite, isTrue);
    expect(store.getBook(id)!.readingStatus, BookReadingStatus.toRead);
    await tester.tap(find.byKey(ValueKey('library-more-' + id)));
    await tester.pumpAndSettle();
    final checked = tester.widget<CheckedPopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Remove from favorites'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    expect(checked.checked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift+F10 opens row actions without opening the book',
      (tester) async {
    await showNarrow(tester);
    final id = ids['Alpha']!;
    final row = find.byKey(ValueKey('library-book-row-' + id));
    final focus = tester.widget<ListTile>(row).focusNode!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Book collections'), findsOneWidget);
    expect(store.getBook(id)!.lastOpenedAt, isNull,
        reason: 'Context menu must not open the reader or begin narration');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Book collections'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press offers the same safe row context menu',
      (tester) async {
    await showNarrow(tester);
    final id = ids['Beta']!;
    await tester.longPress(
        find.byKey(ValueKey('library-book-row-' + id)));
    await tester.pumpAndSettle();
    expect(find.text('Shelf: Reading'), findsOneWidget);
    expect(find.text('Book collections'), findsOneWidget);
    expect(store.getBook(id)!.lastOpenedAt, isNull);
  });

  testWidgets('narrow screen with larger accessibility text does not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.5),
        ),
        child: child!,
      ),
      home: LibraryScreen(store: store),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-compact-filters')), findsOneWidget);
    expect(find.byKey(ValueKey('library-book-row-' + ids['Alpha']!)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
