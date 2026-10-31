import 'package:ereader/features/reader/reader_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyA,
      timeStamp: Duration.zero,
    );

ReaderKeyboardAction? action(
  KeyEvent event, {
  bool ready = true,
  bool routeActive = true,
  bool editing = false,
  bool ctrl = false,
  bool meta = false,
  bool alt = false,
  bool shift = false,
  bool tools = false,
  bool interactive = false,
}) =>
    resolveReaderKeyboardAction(
      event,
      readerReady: ready,
      routeActive: routeActive,
      editingText: editing,
      interactiveControlFocused: interactive,
      toolsAvailable: tools,
      controlPressed: ctrl,
      metaPressed: meta,
      altPressed: alt,
      shiftPressed: shift,
    );

void main() {
  test('Ctrl/Cmd+K opens tools only when explicitly available', () {
    for (final useMeta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.keyK),
              ready: false, tools: true,
              ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.tools);
      expect(action(down(LogicalKeyboardKey.keyK),
          ready: false, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.keyK),
          ready: true, tools: true,
          ctrl: !useMeta, meta: useMeta, shift: true), isNull);
      expect(action(down(LogicalKeyboardKey.keyK),
          ready: true, tools: true, editing: true,
          ctrl: !useMeta, meta: useMeta), isNull);
    }
    expect(action(down(LogicalKeyboardKey.keyK),
        tools: true, routeActive: false, ctrl: true), isNull);
    expect(action(down(LogicalKeyboardKey.keyK),
        tools: true, alt: true, ctrl: true), isNull);
    expect(action(down(LogicalKeyboardKey.keyK),
        tools: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.keyK,
      physicalKey: PhysicalKeyboardKey.keyK,
      timeStamp: Duration.zero,
    ), tools: true, ctrl: true), isNull);
  });

  test('focused interactive controls keep Space and arrow keys', () {
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      expect(action(down(key), interactive: true), isNull);
    }
    expect(action(down(LogicalKeyboardKey.keyK),
        interactive: true, tools: true, ctrl: true),
        ReaderKeyboardAction.tools);
  });

  testWidgets('Ctrl+K exposes tools in PDF page mode, not audio transport',
      (tester) async {
    var opened = 0;
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: false,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onTools: () => opened++,
        child: const Scaffold(body: Text('Visual-only PDF')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(opened, 1);
    expect(played, 0);
  });

  test('unmodified desktop transport keys map to reader commands', () {
    expect(action(down(LogicalKeyboardKey.space)),
        ReaderKeyboardAction.playPause);
    expect(action(down(LogicalKeyboardKey.arrowLeft)),
        ReaderKeyboardAction.previousSegment);
    expect(action(down(LogicalKeyboardKey.arrowRight)),
        ReaderKeyboardAction.nextSegment);
    expect(action(down(LogicalKeyboardKey.f1)),
        ReaderKeyboardAction.help);
    expect(action(down(LogicalKeyboardKey.arrowUp)), isNull);
  });

  test('Ctrl or Cmd opens source search and bookmarks only', () {
    for (final useMeta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.keyF),
              ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.search);
      expect(action(down(LogicalKeyboardKey.keyB),
              ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.bookmarks);
      expect(action(down(LogicalKeyboardKey.arrowLeft),
          ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.space),
          ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.keyF),
          ctrl: !useMeta, meta: useMeta, shift: true), isNull);
    }
  });

  test('editing and hidden routes cannot consume reader keys', () {
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.keyF,
    ]) {
      expect(action(down(key), ready: false, ctrl: true), isNull);
      expect(action(down(key), routeActive: false, ctrl: true), isNull);
      expect(action(down(key), editing: true, ctrl: true), isNull);
    }
  });

  test('Alt, Shift, repeat and key-up never seek or play', () {
    expect(action(down(LogicalKeyboardKey.arrowRight), shift: true), isNull);
    expect(action(down(LogicalKeyboardKey.arrowRight), alt: true), isNull);
    expect(action(down(LogicalKeyboardKey.keyF), alt: true, ctrl: true),
        isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      timeStamp: Duration.zero,
    )), isNull);
    expect(action(KeyUpEvent(
      logicalKey: LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      timeStamp: Duration.zero,
    )), isNull);
  });

  testWidgets('foreground Focus dispatches one command for each key press',
      (tester) async {
    final events = <ReaderKeyboardAction>[];
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => events.add(ReaderKeyboardAction.playPause),
        onPreviousSegment: () =>
            events.add(ReaderKeyboardAction.previousSegment),
        onNextSegment: () => events.add(ReaderKeyboardAction.nextSegment),
        onSearch: () => events.add(ReaderKeyboardAction.search),
        onBookmarks: () => events.add(ReaderKeyboardAction.bookmarks),
        onHelp: () => events.add(ReaderKeyboardAction.help),
        child: const Scaffold(body: Center(child: Text('Reading passage'))),
      ),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    expect(events, [
      ReaderKeyboardAction.playPause,
      ReaderKeyboardAction.nextSegment,
      ReaderKeyboardAction.previousSegment,
      ReaderKeyboardAction.help,
    ]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(events.take(6).toList(), [
      ReaderKeyboardAction.playPause,
      ReaderKeyboardAction.nextSegment,
      ReaderKeyboardAction.previousSegment,
      ReaderKeyboardAction.help,
      ReaderKeyboardAction.search,
      ReaderKeyboardAction.bookmarks,
    ]);
  });

  testWidgets('editing a search text field never triggers transport shortcuts',
      (tester) async {
    var played = 0;
    var searches = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () => searches++,
        onBookmarks: () {},
        onHelp: () {},
        child: const Scaffold(
          body: Column(children: [
            TextField(),
            Text('Book body'),
          ]),
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(played, 0);
    expect(searches, 0);
  });

  testWidgets('modal dialogs take keyboard focus away from the reader',
      (tester) async {
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (screenContext) => ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        child: Scaffold(body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: screenContext,
              builder: (dialogContext) => AlertDialog(
                content: const Text('Edit book details'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            child: const Text('Open dialog'),
          ),
        )),
      )),
    ));
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book details'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(played, 0);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book details'), findsNothing);
  });

  testWidgets('reader disabled during initial load does not dispatch keys',
      (tester) async {
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: false,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        child: const Scaffold(body: Text('Loading...')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(played, 0);
  });

  testWidgets('shortcut help remains scrollable on a small screen',
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
        builder: (context) => ElevatedButton(
          onPressed: () => showReaderKeyboardHelp(context),
          child: const Text('Open help'),
        ),
      )),
    ));
    await tester.tap(find.text('Open help'));
    await tester.pumpAndSettle();
    expect(find.text('Reader keyboard shortcuts'), findsOneWidget);
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcut help is accessible and closes without side effects',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showReaderKeyboardHelp(context),
          child: const Text('Help'),
        ),
      )),
    ));
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('Reader keyboard shortcuts'), findsOneWidget);
    expect(find.textContaining('Space — Play or pause'), findsOneWidget);
    expect(find.textContaining('text field'), findsOneWidget);
    expect(find.textContaining('Ctrl/Cmd + K'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Reader keyboard shortcuts'), findsNothing);
  });
}
