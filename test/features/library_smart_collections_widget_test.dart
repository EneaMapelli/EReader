import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/features/library/library_collections_sheet.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;
  late String atlas;
  late String beta;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-smart-widget-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    for (final name in ['Atlas', 'Beta']) {
      final file = File(p.join(root.path, '$name.txt'));
      await file.writeAsString('Original manuscript $name');
      final id = (await store.importFile(file.path)).id;
      if (name == 'Atlas') {
        atlas = id;
      } else {
        beta = id;
      }
    }
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> openManager(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () => showManageBookCollections(
              context: context, store: store),
          child: const Text('Manage'),
        )),
      ),
    ));
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
  }

  testWidgets('create, edit and delete smart collection; no books deleted',
      (tester) async {
    await openManager(tester);
    await tester.tap(find.byKey(const ValueKey('collection-smart-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('smart-name')), 'Stars');
    final favorites = find.byKey(const ValueKey('smart-favorites'));
    await tester.ensureVisible(favorites);
    await tester.tap(favorites);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pumpAndSettle();

    final saved = store.smartCollections.single;
    expect(saved.name, 'Stars');
    expect(saved.rule.favoritesOnly, isTrue);
    expect(find.byKey(ValueKey('smart-row-${saved.id}')), findsOneWidget);
    expect(store.smartCollectionBookIds(saved.id), isEmpty);

    await tester.tap(find.byTooltip('Edit smart collection'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('smart-name')),
        'New Stars');
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pumpAndSettle();
    expect(store.smartCollections.single.name, 'New Stars');

    await tester.tap(find.byTooltip('Delete smart collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.smartCollections, hasLength(1));
    await tester.tap(find.byTooltip('Delete smart collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.smartCollections, isEmpty);
    expect(store.books, hasLength(2));
  });

  testWidgets('saved smart filter follows favorite changes without membership',
      (tester) async {
    final manual = store.createCollection('Pinned');
    store.setBookCollection(beta, manual.id, true);
    final smart = store.createSmartCollection('Stars',
        const SmartBookCollectionRule(favoritesOnly: true));
    store.setBookFavorite(atlas, true);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(const ValueKey('library-collection-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stars').last);
    await tester.pumpAndSettle();
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.byKey(ValueKey('library-favorite-$atlas')));
    await tester.pump();
    expect(store.smartCollectionBookIds(smart.id), isEmpty);
    expect(find.text('No books match your filters.'), findsOneWidget);
    expect(store.collectionBookIds(manual.id), {beta});
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('invalid empty rules stay in editor until corrected',
      (tester) async {
    await openManager(tester);
    await tester.tap(find.byKey(const ValueKey('collection-smart-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('smart-name')),
        'No criteria');
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('smart-error')), findsOneWidget);
    expect(store.smartCollections, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('smart-query')),
        'title:Atlas');
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pumpAndSettle();
    expect(store.smartCollections.single.rule.query, 'title:Atlas');
    expect(store.smartCollectionBookIds(store.smartCollections.single.id),
        {atlas});
  });
}
