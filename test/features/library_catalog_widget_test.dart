import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-catalog-ui-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    for (final title in ['Zulu', 'Alpha', 'Beta']) {
      final source = File(p.join(root.path, '$title.txt'));
      await source.writeAsString('Book $title text');
      await store.importFile(source.path);
    }
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('library search filters the view without deleting books',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    expect(find.byType(ListTile), findsNWidgets(3));
    await tester.enterText(find.byKey(const ValueKey('library-search')), 'aLp');
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Zulu'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(store.books, hasLength(3));

    await tester.enterText(find.byKey(const ValueKey('library-search')),
        'not in the library');
    await tester.pump();
    expect(find.text('No books match your filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('sorting and format chips preserve the stored catalog',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(const ValueKey('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z').last);
    await tester.pumpAndSettle();
    final titles = tester.widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data).toList();
    expect(titles, ['Alpha', 'Beta', 'Zulu']);

    await tester.tap(find.byKey(const ValueKey('library-filter-epub')));
    await tester.pump();
    expect(find.text('No books match your filters.'), findsOneWidget);
    expect(store.books, hasLength(3));

    await tester.tap(find.byKey(const ValueKey('library-filter-txt')));
    await tester.pump();
    expect(find.byType(ListTile), findsNWidgets(3));
  });
}
