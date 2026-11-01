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
  bool progress = false,
  bool progressReturn = false,
  bool narrationReturn = false,
  bool textSize = false,
  bool sections = false,
  bool interactive = false,
}) =>
    resolveReaderKeyboardAction(
      event,
      readerReady: ready,
      routeActive: routeActive,
      editingText: editing,
      interactiveControlFocused: interactive,
      toolsAvailable: tools,
      progressAvailable: progress,
      progressReturnAvailable: progressReturn,
      returnToNarrationAvailable: narrationReturn,
      textSizeAvailable: textSize,
      sectionNavigationAvailable: sections,
      controlPressed: ctrl,
      metaPressed: meta,
      altPressed: alt,
      shiftPressed: shift,
    );

void main() {
  test('font stepping clamps at reading preference limits', () {
    expect(steppedReaderFontSize(18, 2), 20);
    expect(steppedReaderFontSize(18, -2), 16);
    expect(steppedReaderFontSize(31, 2), 32);
    expect(steppedReaderFontSize(32, 2), 32);
    expect(steppedReaderFontSize(15, -2), 14);
    expect(steppedReaderFontSize(14, -2), 14);
    expect(steppedReaderFontSize(20, 0), 20);
  });

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

  test('Ctrl/Cmd+= and - adjust reading text only when available', () {
    for (final meta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.equal), textSize: true,
          ready: false, ctrl: !meta, meta: meta),
          ReaderKeyboardAction.increaseTextSize);
      expect(action(down(LogicalKeyboardKey.equal), textSize: true,
          ctrl: !meta, meta: meta, shift: true),
          ReaderKeyboardAction.increaseTextSize);
      expect(action(down(LogicalKeyboardKey.minus), textSize: true,
          ctrl: !meta, meta: meta),
          ReaderKeyboardAction.decreaseTextSize);
      expect(action(down(LogicalKeyboardKey.equal),
          ctrl: !meta, meta: meta), isNull);
      expect(action(down(LogicalKeyboardKey.minus),
          ctrl: !meta, meta: meta), isNull);
      expect(action(down(LogicalKeyboardKey.minus), textSize: true,
          ctrl: !meta, meta: meta, shift: true), isNull);
      expect(action(down(LogicalKeyboardKey.equal), textSize: true,
          ctrl: !meta, meta: meta, alt: true), isNull);
      expect(action(down(LogicalKeyboardKey.equal), textSize: true,
          ctrl: !meta, meta: meta, editing: true), isNull);
      expect(action(down(LogicalKeyboardKey.minus), textSize: true,
          ctrl: !meta, meta: meta, routeActive: false), isNull);
    }
    expect(action(down(LogicalKeyboardKey.equal), textSize: true), isNull);
    expect(action(down(LogicalKeyboardKey.minus), textSize: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.equal,
      physicalKey: PhysicalKeyboardKey.equal,
      timeStamp: Duration.zero,
    ), ctrl: true, textSize: true), isNull);
  });

  testWidgets('font-size callbacks run once without starting transport',
      (tester) async {
    var increased = 0;
    var decreased = 0;
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: false, // PDF text mode can have no TTS player.
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onIncreaseTextSize: () => increased++,
        onDecreaseTextSize: () => decreased++,
        child: const Scaffold(body: Text('Reading text')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect([increased, decreased, played], [1, 1, 0]);
  });

  test('EPUB directory shortcuts require Ctrl/Cmd and an active reader',
      () {
    for (final useMeta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.pageUp), sections: true,
          ready: false, ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.previousSection);
      expect(action(down(LogicalKeyboardKey.pageDown), sections: true,
          ready: false, ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.nextSection);
      expect(action(down(LogicalKeyboardKey.home), sections: true,
          ready: false, ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.firstSection);
      expect(action(down(LogicalKeyboardKey.end), sections: true,
          ready: false, ctrl: !useMeta, meta: useMeta),
          ReaderKeyboardAction.lastSection);
      expect(action(down(LogicalKeyboardKey.pageDown),
          ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.pageDown), sections: true,
          editing: true, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.pageDown), sections: true,
          routeActive: false, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.pageUp), sections: true,
          alt: true, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.pageUp), sections: true,
          shift: true, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.pageUp), sections: true,
          interactive: true, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.end), sections: true,
          interactive: true, ctrl: !useMeta, meta: useMeta), isNull);
      expect(action(down(LogicalKeyboardKey.home), sections: true,
          editing: true, ctrl: !useMeta, meta: useMeta), isNull);
    }
    expect(action(down(LogicalKeyboardKey.pageDown), sections: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.pageDown,
      physicalKey: PhysicalKeyboardKey.pageDown,
      timeStamp: Duration.zero,
    ), ctrl: true, sections: true), isNull);
    expect(action(KeyUpEvent(
      logicalKey: LogicalKeyboardKey.pageDown,
      physicalKey: PhysicalKeyboardKey.pageDown,
      timeStamp: Duration.zero,
    ), ctrl: true, sections: true), isNull);
  });

  test('EPUB section stepping clamps and never wraps at the ends', () {
    expect(adjacentReaderSectionIndex(
        current: -1, count: 8, forward: true), 0);
    expect(adjacentReaderSectionIndex(
        current: -1, count: 8, forward: false), isNull);
    expect(adjacentReaderSectionIndex(
        current: 0, count: 8, forward: false), isNull);
    expect(adjacentReaderSectionIndex(
        current: 7, count: 8, forward: true), isNull);
    expect(adjacentReaderSectionIndex(
        current: 2, count: 8, forward: true), 3);
    expect(adjacentReaderSectionIndex(
        current: 3, count: 8, forward: false), 2);
    expect(adjacentReaderSectionIndex(
        current: 0, count: 0, forward: true), isNull);
    expect(adjacentReaderSectionIndex(
        current: -1, count: 0, forward: false), isNull);
    expect(boundaryReaderSectionIndex(count: 0, last: false), isNull);
    expect(boundaryReaderSectionIndex(count: 0, last: true), isNull);
    expect(boundaryReaderSectionIndex(count: 1, last: false), 0);
    expect(boundaryReaderSectionIndex(count: 1, last: true), 0);
    expect(boundaryReaderSectionIndex(count: 1000, last: false), 0);
    expect(boundaryReaderSectionIndex(count: 1000, last: true), 999);
  });

  testWidgets('chapter shortcuts dispatch without starting narration',
      (tester) async {
    var previous = 0;
    var next = 0;
    var first = 0;
    var last = 0;
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
        onPreviousSection: () => previous++,
        onNextSection: () => next++,
        onFirstSection: () => first++,
        onLastSection: () => last++,
        child: const Scaffold(body: Text('Silent EPUB section')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect([previous, next, first, last, played], [1, 1, 1, 1, 0]);
  });

  testWidgets('real keyboard scroll signals do not consume scrolling keys',
      (tester) async {
    var scrolls = 0;
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onViewportScrollKey: () => scrolls++,
        child: const Scaffold(body: Text('Reading passage')),
      ),
    ));
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(scrolls, 6);
    expect(played, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(scrolls, 6,
        reason: 'Modified chapter shortcuts are not visual scrolling');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(played, 1);
  });

  testWidgets('typing in text inputs does not reopen viewport bookmark gate',
      (tester) async {
    var scrolls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () {},
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onViewportScrollKey: () => scrolls++,
        child: const Scaffold(body: TextField()),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(scrolls, 0);
  });

  test('Ctrl/Cmd+G is guarded from editors, dialogs and PDF page mode',
      () {
    for (final meta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.keyG),
              ctrl: !meta, meta: meta, progress: true),
          ReaderKeyboardAction.goToProgress);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta, progress: true, ready: false), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta, progress: true,
          routeActive: false), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta, progress: true, editing: true), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta, progress: true, interactive: true), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta, progress: true, shift: true), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !meta, meta: meta, progress: true, alt: true), isNull);
    }
    expect(action(down(LogicalKeyboardKey.keyG), progress: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.keyG,
      physicalKey: PhysicalKeyboardKey.keyG,
      timeStamp: Duration.zero,
    ), ctrl: true, progress: true), isNull);
  });

  test('Ctrl/Cmd+Shift+G only returns after a confirmed progress jump', () {
    for (final useMeta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progress: true), isNull,
          reason: 'The book has no session return point yet');
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progressReturn: true),
          ReaderKeyboardAction.returnToProgress);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          progressReturn: true), isNull,
          reason: 'Return availability must not enable the Go dialog');
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progressReturn: true,
          ready: false), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progressReturn: true,
          routeActive: false), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progressReturn: true,
          editing: true), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progressReturn: true,
          interactive: true), isNull);
      expect(action(down(LogicalKeyboardKey.keyG),
          ctrl: !useMeta, meta: useMeta,
          shift: true, progressReturn: true,
          alt: true), isNull);
    }
    expect(action(down(LogicalKeyboardKey.keyG),
        shift: true, progressReturn: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.keyG,
      physicalKey: PhysicalKeyboardKey.keyG,
      timeStamp: Duration.zero,
    ), ctrl: true, shift: true, progressReturn: true), isNull);
  });

  testWidgets('Ctrl+Shift+G dispatches return only, never starts audio',
      (tester) async {
    var go = 0;
    var returned = 0;
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onGoToProgress: () => go++,
        onReturnToProgress: () => returned++,
        child: const Scaffold(body: Text('EReader source position')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(returned, 1);
    expect(go, 1);
    expect(played, 0);
  });

  test('Ctrl/Cmd+Shift+J only rejoins narration while detached', () {
    for (final useMeta in [false, true]) {
      expect(action(down(LogicalKeyboardKey.keyJ),
          ctrl: !useMeta, meta: useMeta, shift: true,
          narrationReturn: true), ReaderKeyboardAction.returnToNarration);
      for (final variant in [
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta, shift: true),
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta,
            narrationReturn: true),
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta, shift: true,
            narrationReturn: true, ready: false),
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta, shift: true,
            narrationReturn: true, editing: true),
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta, shift: true,
            narrationReturn: true, interactive: true),
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta, shift: true,
            narrationReturn: true, alt: true),
        action(down(LogicalKeyboardKey.keyJ),
            ctrl: !useMeta, meta: useMeta, shift: true,
            narrationReturn: true, routeActive: false),
      ]) {
        expect(variant, isNull);
      }
    }
    expect(action(down(LogicalKeyboardKey.keyJ),
        shift: true, narrationReturn: true), isNull);
    expect(action(KeyRepeatEvent(
      logicalKey: LogicalKeyboardKey.keyJ,
      physicalKey: PhysicalKeyboardKey.keyJ,
      timeStamp: Duration.zero,
    ), ctrl: true, shift: true, narrationReturn: true), isNull);
  });

  testWidgets('return-to-narration shortcut never starts or seeks speech',
      (tester) async {
    var returns = 0;
    var played = 0;
    var skipped = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => played++,
        onPreviousSegment: () => skipped++,
        onNextSegment: () => skipped++,
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onReturnToNarration: () => returns++,
        child: const Scaffold(body: Text('Detached reader viewport')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(returns, 1);
    expect(played, 0);
    expect(skipped, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+G opens percentage dialog callback but never plays audio',
      (tester) async {
    var opened = 0;
    var played = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderKeyboardShortcuts(
        enabled: true,
        onPlayPause: () => played++,
        onPreviousSegment: () {},
        onNextSegment: () {},
        onSearch: () {},
        onBookmarks: () {},
        onHelp: () {},
        onGoToProgress: () => opened++,
        child: const Scaffold(body: Text('A readable book')),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(opened, 1);
    expect(played, 0);
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
    expect(find.textContaining('Increase reading text size'), findsOneWidget);
    expect(find.textContaining('Previous EPUB section'), findsOneWidget);
    expect(find.textContaining('Next EPUB section'), findsOneWidget);
    expect(find.textContaining('First EPUB section'), findsOneWidget);
    expect(find.textContaining('Last EPUB section'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Reader keyboard shortcuts'), findsNothing);
  });
}
