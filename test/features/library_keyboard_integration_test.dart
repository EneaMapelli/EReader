import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-library-keys-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final txt = File(p.join(root.path, 'Quiet Book.txt'));
    await txt.writeAsString('Quiet book for local keyboard navigation.');
    await store.importFile(txt.path);
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('Ctrl+F focuses the existing catalog search without mutation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pump();
    final search = find.byKey(const ValueKey('library-search'));
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);

    await tester.enterText(search, 'does not exist');
    await tester.pump();
    expect(find.text('No books match your filters.'), findsOneWidget);
    expect(store.books, hasLength(1),
        reason: 'Search must not edit or delete catalog entries');
  });

  testWidgets('Ctrl+K opens searchable library tools with immediate focus',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Library tools'), findsOneWidget);
    final filter = find.byKey(const ValueKey('organized-action-filter'));
    expect(filter, findsOneWidget,
        reason: 'Keyboard palette must support even short library menus');
    expect(tester.widget<TextField>(filter).autofocus, isTrue);
    await tester.enterText(filter, 'keyboard');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-keyboard-help')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-backup')),
        findsNothing);
    expect(store.books, hasLength(1));
  });

  testWidgets('toolbar tools remain compact, and shortcut help is discoverable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(const ValueKey('library-tools-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-filter')), findsNothing);
    await tester.tap(find.text('Keyboard shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('Library keyboard shortcuts'), findsOneWidget);
    expect(find.textContaining('Ctrl/Cmd + O'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
