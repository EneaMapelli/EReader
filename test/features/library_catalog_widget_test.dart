import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
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
  testWidgets('star toggle, favorites filter and clear filters compose',
      (tester) async {
    final ids = {for (final book in store.books) book.title: book.id};
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    final alphaStar = find.byKey(ValueKey('library-favorite-${ids['Alpha']}'));
    expect(tester.widget<IconButton>(alphaStar).tooltip, 'Add to favorites');
    await tester.tap(alphaStar);
    await tester.pump();
    expect(store.getBook(ids['Alpha']!)!.isFavorite, isTrue);
    expect(tester.widget<IconButton>(alphaStar).tooltip,
        'Remove from favorites');
    expect(store.books, hasLength(3));

    await tester.tap(find.byKey(const ValueKey('library-favorites-only')));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Zulu'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('library-search')), 'zzz');
    await tester.pump();
    expect(find.text('No books match your filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Zulu'), findsOneWidget);
    expect(store.getBook(ids['Alpha']!)!.isFavorite, isTrue,
        reason: 'Clearing view-only filters may never unstar books');
  });

  testWidgets('favorites-first sort prioritizes saved stars and can unstar',
      (tester) async {
    final ids = {for (final book in store.books) book.title: book.id};
    store.setBookFavorite(ids['Zulu']!, true);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(const ValueKey('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites first').last);
    await tester.pumpAndSettle();
    final titles = tester.widgetList<ListTile>(find.byType(ListTile))
        .where((tile) => tile.title is Text &&
            ['Alpha', 'Beta', 'Zulu'].contains((tile.title! as Text).data))
        .map((tile) => (tile.title! as Text).data).toList();
    expect(titles.first, 'Zulu');
    await tester.tap(find.byKey(ValueKey('library-favorite-${ids['Zulu']}')));
    await tester.pump();
    expect(store.getBook(ids['Zulu']!)!.isFavorite, isFalse);
    expect(store.books, hasLength(3));
  });

  testWidgets('shelf menu sets reading status and filter is reversible',
      (tester) async {
    final ids = {for (final book in store.books) book.title: book.id};
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    final alphaShelf = find.byKey(ValueKey('library-shelf-${ids['Alpha']}'));
    await tester.tap(alphaShelf);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(store.getBook(ids['Alpha']!)!.readingStatus,
        BookReadingStatus.reading);
    expect(store.getBook(ids['Alpha']!)!.progressOffset, 0);

    await tester.tap(
        find.byKey(const ValueKey('library-reading-shelf-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Zulu'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('library-search')), 'no match');
    await tester.pump();
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Zulu'), findsOneWidget);
    expect(store.getBook(ids['Alpha']!)!.readingStatus,
        BookReadingStatus.reading,
        reason: 'Clear filters cannot reset saved shelf status');
  });

  testWidgets('manual finished status does not start player or change progress',
      (tester) async {
    final ids = {for (final book in store.books) book.title: book.id};
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(
        find.byKey(ValueKey('library-shelf-${ids['Beta']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finished').last);
    await tester.pumpAndSettle();
    final book = store.getBook(ids['Beta']!)!;
    expect(book.readingStatus, BookReadingStatus.finished);
    expect(book.progressOffset, 0);
    expect(book.progressAnchor, isNull);
    expect(book.lastOpenedAt, isNull);
    expect(store.books, hasLength(3));
    expect(find.byKey(ValueKey('library-more-${ids['Beta']}')),
        findsOneWidget);
  });

  testWidgets('compact More menu retains edit and remove commands',
      (tester) async {
    final id = store.books.first.id;
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(ValueKey('library-more-$id')));
    await tester.pumpAndSettle();
    expect(find.text('Edit book details'), findsOneWidget);
    expect(find.text('Remove book'), findsOneWidget);
    await tester.tap(find.text('Edit book details'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book details'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.books, hasLength(3));
  });

  testWidgets('activity filters and last-open sort use persisted history',
      (tester) async {
    final ids = {for (final book in store.books) book.title: book.id};
    await store.markBookOpened(ids['Zulu']!);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await store.markBookOpened(ids['Beta']!);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));

    await tester.tap(find.byKey(const ValueKey('library-activity-neverOpened')));
    await tester.pump();
    expect(find.byKey(ValueKey('cover-tile-${ids['Alpha']}')), findsOneWidget);
    expect(find.byKey(ValueKey('cover-tile-${ids['Zulu']}')), findsNothing);
    expect(find.byKey(ValueKey('cover-tile-${ids['Beta']}')), findsNothing);
    expect(store.books, hasLength(3));

    await tester.tap(find.byKey(const ValueKey('library-activity-opened')));
    await tester.pump();
    expect(find.byKey(ValueKey('cover-tile-${ids['Alpha']}')), findsNothing);
    expect(find.byKey(ValueKey('cover-tile-${ids['Zulu']}')), findsOneWidget);
    expect(find.byKey(ValueKey('cover-tile-${ids['Beta']}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently opened').last);
    await tester.pumpAndSettle();
    final visible = tester.widgetList<ListTile>(
        find.byType(ListTile)).where((tile) => tile.title is Text &&
        ['Alpha', 'Beta', 'Zulu'].contains((tile.title! as Text).data))
        .map((tile) => (tile.title! as Text).data).toList();
    expect(visible, ['Beta', 'Zulu']);

    await tester.enterText(find.byKey(const ValueKey('library-search')), 'none');
    await tester.pump();
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.byKey(ValueKey('cover-tile-${ids['Alpha']}')), findsOneWidget);
    expect(find.byKey(ValueKey('cover-tile-${ids['Beta']}')), findsOneWidget);
    expect(find.byKey(ValueKey('cover-tile-${ids['Zulu']}')), findsOneWidget);
    expect(store.books, hasLength(3));
  });

  testWidgets('advanced field search combines AND terms and existing filters',
      (tester) async {
    final ids = {for (final book in store.books) book.title: book.id};
    store.updateBookMetadata(ids['Alpha']!,
        title: 'Alpha', author: 'Ada Writer', series: 'North Star');
    store.updateBookMetadata(ids['Beta']!,
        title: 'Beta', author: 'Ada Writer', series: 'Southern Sky');
    store.updateBookMetadata(ids['Zulu']!,
        title: 'Zulu', author: 'Marco Rossi', series: 'North Star');
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));

    final search = find.byKey(const ValueKey('library-search'));
    await tester.enterText(search, 'author:"Ada Writer" series:"North Star"');
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Zulu'), findsNothing);

    await tester.enterText(search, 'north writer');
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Zulu'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-favorites-only')));
    await tester.pump();
    expect(find.text('No books match your filters.'), findsOneWidget);
    expect(store.books, hasLength(3));
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Zulu'), findsOneWidget);
  });

  testWidgets('search syntax help, malformed query and clear are safe',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byTooltip('Library search help'));
    await tester.pumpAndSettle();
    final help = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect((help.content! as Text).data, contains('text inside books'));
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('library-search'));
    await tester.enterText(search, 'title:');
    await tester.pump();
    final field = tester.widget<TextField>(search);
    expect(field.decoration!.errorText, 'Enter text after a search field');
    expect(find.text('No books match your filters.'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear library search'));
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(store.books, hasLength(3));
    expect(find.text('Zulu'), findsOneWidget);
  });

}
