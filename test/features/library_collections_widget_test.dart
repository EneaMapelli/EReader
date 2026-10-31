import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_collections_sheet.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;
  late String firstId;
  late String secondId;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-collections-ui-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    for (final name in ['Atlas', 'Beta']) {
      final file = File(p.join(root.path, '$name.txt'));
      await file.writeAsString('Original $name content');
      final id = (await store.importFile(file.path)).id;
      if (name == 'Atlas') {
        firstId = id;
      } else {
        secondId = id;
      }
    }
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> showManager(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => ElevatedButton(
          onPressed: () => showManageBookCollections(
              context: context, store: store),
          child: const Text('Open manager'),
        )),
      ),
    ));
    await tester.tap(find.text('Open manager'));
    await tester.pumpAndSettle();
  }

  testWidgets('create, rename and delete collection without deleting books',
      (tester) async {
    await showManager(tester);
    expect(find.text('No collections yet. Create one to organize your books.'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('collection-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('collection-name-input')), 'Fantasy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.collections.single.name, 'Fantasy');
    await tester.tap(find.byTooltip('Rename collection'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('collection-name-input')), 'Science');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.collections.single.name, 'Science');
    await tester.tap(find.byTooltip('Delete collection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Books will not be deleted.'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.collections, isEmpty);
    expect(store.books, hasLength(2));
  });

  testWidgets('a single book can join and leave multiple collections',
      (tester) async {
    final a = store.createCollection('Poetry');
    final b = store.createCollection('Personal');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () => showBookCollectionMembership(
          context: context, store: store, bookId: firstId),
        child: const Text('Open memberships'),
      )),
    )));
    await tester.tap(find.text('Open memberships'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('book-collection-${a.id}')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('book-collection-${b.id}')));
    await tester.pump();
    expect(store.listBookCollections(firstId), hasLength(2));
    expect(store.listBookCollections(secondId), isEmpty);
    await tester.tap(find.byKey(ValueKey('book-collection-${a.id}')));
    await tester.pump();
    expect(store.listBookCollections(firstId).single.name, 'Personal');
    expect(store.getBook(firstId)!.progressOffset, 0);
  });

  testWidgets('library collection dropdown filters without changing metadata',
      (tester) async {
    final group = store.createCollection('Selected');
    store.setBookCollection(firstId, group.id, true);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(
        find.byKey(const ValueKey('library-collection-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selected').last);
    await tester.pumpAndSettle();
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(store.books, hasLength(2));
    await tester.enterText(
        find.byKey(const ValueKey('library-search')), 'absent');
    await tester.pump();
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(store.listBookCollections(firstId), hasLength(1));
  });

  testWidgets('top-level library tools groups collections and backups',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    expect(find.byKey(const ValueKey('library-import-action')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('library-tools-menu')),
        findsOneWidget);
    expect(find.text('2 books in library'), findsOneWidget);
    expect(find.byTooltip('Export private library backup'), findsNothing,
        reason: 'Rare backup operations should not crowd the AppBar');

    await tester.tap(find.byKey(const ValueKey('library-tools-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Organize'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Data & backups'), findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-backup')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-restore')),
        findsOneWidget);
    expect(store.books, hasLength(2),
        reason: 'Opening the menu must never start a backup or import');
    await tester.tap(
        find.byKey(const ValueKey('organized-action-collections')));
    await tester.pumpAndSettle();
    expect(find.text('No collections yet. Create one to organize your books.'),
        findsOneWidget);
    expect(store.books, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('library More menu exposes collection assignments',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(ValueKey('library-more-$firstId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book collections'));
    await tester.pumpAndSettle();
    expect(find.text('No collections yet.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('book-collection-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('collection-name-input')), 'Study');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.listBookCollections(firstId).single.name, 'Study');
    expect(store.listBookCollections(secondId), isEmpty);
  });
}
