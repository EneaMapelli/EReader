import 'package:ereader/features/library/library_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.keyA,
  timeStamp: Duration.zero,
);

LibraryKeyboardAction? action(
  KeyEvent event, {
  bool route = true,
  bool editing = false,
  bool ctrl = false,
  bool meta = false,
  bool alt = false,
  bool shift = false,
  bool search = true,
  bool tools = true,
  bool importBooks = true,
}) => resolveLibraryKeyboardAction(
  event,
  routeActive: route,
  editingText: editing,
  controlPressed: ctrl,
  metaPressed: meta,
  altPressed: alt,
  shiftPressed: shift,
  searchAvailable: search,
  toolsAvailable: tools,
  importAvailable: importBooks,
);

void main() {
  test('Ctrl/Cmd+F, K, O and F1 are deterministic', () {
    for (final useMeta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.keyF),
          ctrl: !useMeta, meta: useMeta), LibraryKeyboardAction.search);
      expect(action(down(LogicalKeyboardKey.keyK),
          ctrl: !useMeta, meta: useMeta), LibraryKeyboardAction.tools);
      expect(action(down(LogicalKeyboardKey.keyO),
          ctrl: !useMeta, meta: useMeta),
          LibraryKeyboardAction.importBooks);
    }
    expect(action(down(LogicalKeyboardKey.f1)), LibraryKeyboardAction.help);
    expect(action(down(LogicalKeyboardKey.space)), isNull);
  });

  test('editing, dialogs, unavailable operations and modified keys are safe',
      () {
    for (final key in [
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyO,
    ]) {
      expect(action(down(key), editing: true, ctrl: true), isNull);
      expect(action(down(key), route: false, ctrl: true), isNull);
      expect(action(down(key), alt: true, ctrl: true), isNull);
      expect(action(down(key), shift: true, ctrl: true), isNull);
      expect(action(down(key)), isNull);
    }
    expect(action(down(LogicalKeyboardKey.keyF),
        search: false, ctrl: true), isNull);
    expect(action(down(LogicalKeyboardKey.keyK),
        tools: false, ctrl: true), isNull);
    expect(action(down(LogicalKeyboardKey.keyO),
        importBooks: false, ctrl: true), isNull);
    expect(action(down(LogicalKeyboardKey.f1), editing: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.keyO,
      physicalKey: PhysicalKeyboardKey.keyO,
      timeStamp: Duration.zero,
    ), ctrl: true), isNull);
    expect(action(KeyUpEvent(
      logicalKey: LogicalKeyboardKey.keyK,
      physicalKey: PhysicalKeyboardKey.keyK,
      timeStamp: Duration.zero,
    ), ctrl: true), isNull);
  });

  testWidgets('focused library route dispatches commands once', (tester) async {
    var searched = 0;
    var opened = 0;
    var imported = 0;
    var helped = 0;
    await tester.pumpWidget(MaterialApp(
      home: LibraryKeyboardShortcuts(
        onSearch: () => searched++,
        onTools: () => opened++,
        onImport: () => imported++,
        onHelp: () => helped++,
        child: const Scaffold(body: Center(child: Text('Library'))),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    expect([searched, opened, imported, helped], [1, 1, 1, 1]);
  });

  testWidgets('typing does not open menus or native file pickers',
      (tester) async {
    var tools = 0;
    var imports = 0;
    var searches = 0;
    await tester.pumpWidget(MaterialApp(
      home: LibraryKeyboardShortcuts(
        onSearch: () => searches++,
        onTools: () => tools++,
        onImport: () => imports++,
        onHelp: () {},
        child: const Scaffold(body: TextField()),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect([searches, tools, imports], [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open dialogs and inactive routes cannot dispatch commands',
      (tester) async {
    var imported = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (screen) => LibraryKeyboardShortcuts(
        onImport: () => imported++,
        onHelp: () {},
        child: Scaffold(body: TextButton(
          onPressed: () => showDialog<void>(
            context: screen,
            builder: (dialog) => AlertDialog(
              title: const Text('Confirm'),
              actions: [TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Close'),
              )],
            ),
          ),
          child: const Text('Open dialog'),
        )),
      )),
    ));
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(imported, 0);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('help dialog fits enlarged text on narrow display',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 420));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.8),
        ),
        child: child!,
      ),
      home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showLibraryKeyboardHelp(context),
          child: const Text('Help'),
        ),
      )),
    ));
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
        isTrue);
    expect(find.textContaining('Ctrl/Cmd + F'), findsOneWidget);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
