import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late LibraryStore store;
  late String bookId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ereader-quick-nav-');
    store = LibraryStore(homeDirectory: directory);
    await store.initialize();
    final file = File(p.join(directory.path, 'Quick navigation.txt'));
    await file.writeAsString(List<String>.generate(
      80, (index) => 'Section ${index + 1}. Local reader text used to '
          'exercise mobile shortcuts and source-only navigation.\n\n',
    ).join());
    bookId = (await store.importFile(file.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  testWidgets('compact AppBar exposes navigation without hiding full tools',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 660));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final originalRevision = store.manualPositionRevision(bookId);

    expect(find.byKey(const ValueKey('reader-quick-navigation')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-tools-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-search-action')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reader-quick-navigation')));
    await tester.pumpAndSettle();
    expect(find.text('Quick navigation'), findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-search')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-bookmarks')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-go-to-percent')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-speech')), findsNothing);
    expect(find.byKey(const ValueKey('organized-action-auto-follow')),
        findsNothing);
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Opening mobile navigation does not move a bookmark');

    await tester.tap(find.byKey(const ValueKey('organized-action-go-to-percent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-progress-confirm')),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Closing a quick Go dialog is not a source seek');
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact navigation survives enlarged text and narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-quick-navigation')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-tools-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-quick-navigation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-bookmarks')),
        findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'Large fonts must not overflow AppBar or the small sheet');
  });

  testWidgets('wide AppBar keeps direct search rather than duplicate nav',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(740, 680));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-quick-navigation')), findsNothing);
    expect(find.byKey(const ValueKey('reader-search-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-tools-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile quick navigation works in immersive reading mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final originalRevision = store.manualPositionRevision(bookId);
    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-quick-navigation')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-quick-navigation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-bookmarks')),
        findsOneWidget);
    expect(store.manualPositionRevision(bookId), originalRevision);
    expect(tester.takeException(), isNull);
  });
}
