import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Two navigable, source-distinct OPF sections with real publisher TOC
/// entries. No external files or platform TTS voices are required.
Uint8List _fixture() {
  final longOpening = List<String>.filled(
      24, 'Opening narrative paragraph for reading position. ').join();
  final longSecond = List<String>.filled(
      24, 'Second narrative paragraph for reading position. ').join();
  final archive = Archive()
    ..add(ArchiveFile.noCompress('mimetype',
        'application/epub+zip'.length, utf8.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
        '</rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/book.opf', '''
<package xmlns="http://www.idpf.org/2007/opf"
    xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0"
    unique-identifier="uid">
  <metadata>
    <dc:identifier id="uid">focus-header-fixture</dc:identifier>
    <dc:title>Focus Header Test</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="first" href="first.xhtml"
        media-type="application/xhtml+xml"/>
    <item id="second" href="second.xhtml"
        media-type="application/xhtml+xml"/>
    <item id="toc" href="nav.xhtml" properties="nav"
        media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="first"/><itemref idref="second"/></spine>
</package>
'''))
    ..add(ArchiveFile.string('OPS/first.xhtml',
        '<html><body><h1 id="opening">Opening</h1><p>$longOpening</p>'
        '</body></html>'))
    ..add(ArchiveFile.string('OPS/second.xhtml',
        '<html><body><h1 id="second">Second chapter</h1>'
        '<p>$longSecond</p></body></html>'))
    ..add(ArchiveFile.string('OPS/nav.xhtml',
        '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol>'
        '<li><a href="first.xhtml#opening">Opening</a></li>'
        '<li><a href="second.xhtml#second">Second chapter</a></li>'
        '</ol></nav></body></html>'));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late Directory home;
  late LibraryStore store;
  late String bookId;
  late int nextChapterStart;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-focus-epub-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    final bytes = _fixture();
    final extracted = const EpubTextExtractor().extract(bytes);
    expect(extracted.navigation.map((entry) => entry.label),
        ['Opening', 'Second chapter']);
    nextChapterStart = extracted.navigation[1].offset;
    final source = File(p.join(home.path, 'focus-reader.epub'));
    await source.writeAsBytes(bytes);
    bookId = (await store.importFile(source.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });


  testWidgets('inactive and resumed reader cannot flush a queued '
      'visual scroll over the last durable checkpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    addTearDown(() =>
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));

    final originalOffset = store.getBook(bookId)!.progressOffset;
    final originalRevision = store.manualPositionRevision(bookId);
    final scrollable = find.byType(Scrollable).first;
    // Queue a genuine 450ms viewport save, then switch away before it
    // fires. Background audio/recovery may have its own save path; the
    // visual scroll must not overwrite the exact checkpoint.
    await tester.drag(scrollable, const Offset(0, -170));
    await tester.pump(const Duration(milliseconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 650));
    expect(store.manualPositionRevision(bookId), originalRevision);
    expect(store.getBook(bookId)!.progressOffset, originalOffset);

    // Resuming must not retroactively convert an old scroll into a new
    // bookmark, even if the EPUB viewport relays layout notifications.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    expect(store.manualPositionRevision(bookId), originalRevision);
    expect(store.getBook(bookId)!.progressOffset, originalOffset);

    // Explicit publisher navigation stays operational after resume:
    // it owns a separate source-exact SQLite checkpoint, unaffected by
    // the guarded manual-viewport persistence path.
    await tester.tap(find.byKey(
        const ValueKey('reader-compact-next-section')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(store.manualPositionRevision(bookId), originalRevision + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter seek invalidates a pending visual viewport save',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));

    final startingRevision = store.manualPositionRevision(bookId);
    // A short user scroll may queue a 450ms original-source checkpoint.
    // Do not settle that timer: the chapter choice is a newer explicit
    // source intent and must invalidate even a queued callback.
    final scrollables = find.byType(Scrollable);
    expect(scrollables, findsWidgets);
    await tester.drag(scrollables.first, const Offset(0, -160));
    await tester.pump(const Duration(milliseconds: 30));

    await tester.tap(find.byKey(
        const ValueKey('reader-compact-next-section')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    // Drain the former delayed-save window. It must not coarsen the
    // explicit publisher chapter anchor or write an extra checkpoint.
    await tester.pump(const Duration(milliseconds: 650));
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(store.manualPositionRevision(bookId), startingRevision + 1,
        reason: 'Queued viewport saves must be canceled before native Pause');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid same-destination chapter taps keep one durable origin',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));

    final startingOffset = store.getBook(bookId)!.progressOffset;
    final beforeRevision = store.manualPositionRevision(bookId);
    final next = find.byKey(
        const ValueKey('reader-compact-next-section'));

    // Queue the same visual source intent twice without settling either
    // native/SQLite continuation between taps. Only the winning selection
    // may write a checkpoint and add a chapter return origin.
    await tester.tap(next);
    await tester.tap(next);
    await tester.pumpAndSettle();

    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(store.manualPositionRevision(bookId), beforeRevision + 1,
        reason: 'Superseded duplicate chapter seeks must not double-save');

    final shortcut = find.byKey(
        const ValueKey('reader-chapter-history-shortcut'));
    expect(shortcut, findsOneWidget);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-back')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-recent')),
        findsNothing,
        reason: 'A duplicate command must not fabricate two Back visits');
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-back')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, startingOffset);

    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-forward')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-forward')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid chapter keyboard choices preserve final SQLite and '
      'visual position and Back/Forward', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));

    final start = store.getBook(bookId)!.progressOffset;
    final originalRevision = store.manualPositionRevision(bookId);
    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-compact-transport')),
        findsNothing);

    // Ctrl+End, Ctrl+Home, Ctrl+End exercise the same publisher-TOC
    // selection route while prior async source seeks may still be pending.
    // The *last* intent must win regardless of the completion order.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart),
        reason: 'Final requested destination must own the checkpoint');
    expect(store.manualPositionRevision(bookId),
        greaterThan(originalRevision));
    expect(tester.widget<Text>(find.byKey(
        const ValueKey('reader-focus-section-number'))).data, '2/2',
        reason: 'Visual EPUB section must match the persisted destination');

    // History navigation is independent of publisher-TOC traversal
    // and never invokes speech playback. It must restore both exact
    // durable positions and the focus header after rapid requests.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, start);
    expect(tester.widget<Text>(find.byKey(
        const ValueKey('reader-focus-section-number'))).data, '1/2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(tester.widget<Text>(find.byKey(
        const ValueKey('reader-focus-section-number'))).data, '2/2');
    expect(find.byKey(const ValueKey('reader-compact-transport')),
        findsNothing,
        reason: 'Navigation must not expose TTS controls in focus mode');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard chapter branch invalidates redo without a '
      'phantom SQLite checkpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final beginning = store.getBook(bookId)!.progressOffset;

    // A normal publisher chapter jump, followed by an actual history Back.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, beginning);

    // A new publisher chapter choice discards Forward, unlike a
    // historical Forward command. The old chord must perform no seek.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final newBranch = store.getBook(bookId)!.progressOffset;
    expect(newBranch, greaterThanOrEqualTo(nextChapterStart));
    final savedRevision = store.manualPositionRevision(bookId);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, newBranch);
    expect(store.manualPositionRevision(bookId), savedRevision,
        reason: 'Unavailable history Forward must not write a checkpoint');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent chapter history sheet returns to an older saved visit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final initialOffset = store.getBook(bookId)!.progressOffset;

    final forward = find.byKey(
        const ValueKey('reader-compact-next-section'));
    final back = find.byKey(
        const ValueKey('reader-compact-previous-section'));

    // Three successful, persisted EPUB switches produce three return
    // origins, even if two visits have the same UTF-16 coordinate.
    await tester.tap(forward);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(forward);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));

    Future<void> openQuick() async {
      await tester.tap(find.byKey(
          const ValueKey('reader-quick-navigation')));
      await tester.pumpAndSettle();
    }

    await openQuick();
    final history = find.byKey(
        const ValueKey('organized-action-chapter-history'));
    await tester.scrollUntilVisible(
        history, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.text('Recent chapter positions'), findsOneWidget);
    expect(find.text('3 saved visits in this reading session'),
        findsOneWidget);
    final revisionBeforeCancel = store.manualPositionRevision(bookId);
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-history-close')));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revisionBeforeCancel,
        reason: 'Closing a history sheet does not seek or save');

    await openQuick();
    final openHistory = find.byKey(
        const ValueKey('organized-action-chapter-history'));
    await tester.scrollUntilVisible(
        openHistory, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(openHistory);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-history-entry-2')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, initialOffset,
        reason: 'Older history entries retain the original exact source');
    await openQuick();
    expect(find.byKey(const ValueKey('organized-action-chapter-history')),
        findsNothing,
        reason: 'Returning to the oldest entry moves later visits to Forward');
    expect(find.byKey(const ValueKey('organized-action-return-to-section')),
        findsNothing);
    // The forward path is chronological: first the prior second
    // chapter, then first chapter, then the original current chapter.
    for (final inSecondChapter in [true, false, true]) {
      final nextVisited = find.byKey(
          const ValueKey('organized-action-forward-to-section'));
      await tester.scrollUntilVisible(
          nextVisited, 160, scrollable: find.byType(Scrollable).last);
      await tester.tap(nextVisited);
      await tester.pumpAndSettle();
      final offset = store.getBook(bookId)!.progressOffset;
      if (inSecondChapter) {
        expect(offset, greaterThanOrEqualTo(nextChapterStart));
      } else {
        expect(offset, lessThan(nextChapterStart));
      }
      await openQuick();
    }
    expect(find.byKey(
        const ValueKey('organized-action-forward-to-section')),
        findsNothing,
        reason: 'Every successful Forward consumes one redo destination');
    expect(find.byKey(const ValueKey('organized-action-return-to-section')),
        findsOneWidget,
        reason: 'Forward navigation preserves the backward trail');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter shortcut opens instant Back and Forward in both layouts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final shortcut = find.byKey(
        const ValueKey('reader-chapter-history-shortcut'));
    expect(shortcut, findsNothing,
        reason: 'No history control appears before a committed switch');

    await tester.tap(find.byKey(
        const ValueKey('reader-compact-next-section')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(shortcut, findsOneWidget);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-back')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-forward')),
        findsNothing);
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-back')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        lessThan(nextChapterStart));

    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-forward')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-forward')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));

    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-compact-transport')),
        findsNothing);
    expect(shortcut, findsOneWidget,
        reason: 'Focus AppBar exposes history without narration transport');
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-back')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        lessThan(nextChapterStart));
    expect(find.byKey(const ValueKey('reader-compact-transport')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new chapter branch invalidates forward after Back',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.tap(find.byKey(
        const ValueKey('reader-compact-next-section')));
    await tester.pumpAndSettle();

    Future<void> quick() async {
      await tester.tap(find.byKey(
          const ValueKey('reader-quick-navigation')));
      await tester.pumpAndSettle();
    }

    await quick();
    final back = find.byKey(
        const ValueKey('organized-action-return-to-section'));
    await tester.scrollUntilVisible(
        back, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        lessThan(nextChapterStart));

    await quick();
    expect(find.byKey(
        const ValueKey('organized-action-forward-to-section')),
        findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    // Explicitly choosing a new chapter is a fresh branch, not Forward.
    await tester.tap(find.byKey(
        const ValueKey('reader-compact-next-section')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    await quick();
    expect(find.byKey(
        const ValueKey('organized-action-forward-to-section')),
        findsNothing);
    expect(find.byKey(
        const ValueKey('organized-action-return-to-section')),
        findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter return restores exact pre-switch point without '
      'consuming percentage history', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final start = store.getBook(bookId)!.progressOffset;

    // Enter focus mode; all chapter and percentage actions remain
    // available without exposing TTS transport controls.
    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();

    // First, record a percentage-return point inside chapter one.
    await tester.tap(find.byKey(const ValueKey('reader-focus-section-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-50')));
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();
    final midChapter = store.getBook(bookId)!.progressOffset;
    expect(midChapter, greaterThan(start));
    expect(midChapter, lessThan(nextChapterStart));

    await tester.tap(find.byKey(const ValueKey('reader-focus-next-section')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));

    Future<void> openQuickNavigation() async {
      await tester.tap(find.byKey(
          const ValueKey('reader-quick-navigation')));
      await tester.pumpAndSettle();
    }

    Future<void> tapQuickItem(String action) async {
      final item = find.byKey(ValueKey('organized-action-$action'));
      await tester.scrollUntilVisible(
          item, 160, scrollable: find.byType(Scrollable).last);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    await openQuickNavigation();
    expect(find.byKey(const ValueKey('organized-action-return-to-section')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsOneWidget);
    await tapQuickItem('return-to-section');
    expect(store.getBook(bookId)!.progressOffset, midChapter,
        reason: 'Chapter return restores exact visual origin, not chapter start');

    await openQuickNavigation();
    expect(find.byKey(const ValueKey('organized-action-return-to-section')),
        findsNothing,
        reason: 'A consumed chapter return is one-shot');
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsOneWidget,
        reason: 'Chapter return does not erase percentage return');
    await tapQuickItem('return-to-percent');
    expect(store.getBook(bookId)!.progressOffset, start);
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    expect(tester.takeException(), isNull);

    await openQuickNavigation();
    expect(find.byKey(const ValueKey('organized-action-return-to-section')),
        findsNothing);
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsNothing,
        reason: 'Each one-shot return is consumed only after its own commit');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  });

  testWidgets('directory selection also creates a one-shot chapter return',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final before = store.getBook(bookId)!.progressOffset;

    await tester.tap(find.byKey(const ValueKey('reader-compact-current-section')));
    await tester.pumpAndSettle();
    // Looking at contents does not invent a return point.
    expect(find.byKey(const ValueKey('reader-directory-entry-1')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-directory-entry-1')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));

    await tester.tap(find.byKey(const ValueKey('reader-quick-navigation')));
    await tester.pumpAndSettle();
    final action = find.byKey(
        const ValueKey('organized-action-return-to-section'));
    await tester.scrollUntilVisible(
        action, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter arrows use guarded EPUB positions in focus and compact modes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));

    final original = store.getBook(bookId)!.progressOffset;
    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();

    final previous = find.byKey(
        const ValueKey('reader-focus-previous-section'));
    final next = find.byKey(const ValueKey('reader-focus-next-section'));
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(tester.widget<Text>(find.byKey(
        const ValueKey('reader-focus-section-number'))).data, '2/2');
    expect(tester.widget<IconButton>(previous).onPressed, isNotNull);
    expect(tester.widget<IconButton>(next).onPressed, isNull,
        reason: 'Last EPUB section cannot advance past the book');

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, lessThan(nextChapterStart));
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing,
        reason: 'Section navigation never exits focus mode');

    await tester.tap(find.byKey(const ValueKey('reader-focus-restore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-focus-section')), findsNothing);
    final compactPrevious = find.byKey(
        const ValueKey('reader-compact-previous-section'));
    final compactNext = find.byKey(
        const ValueKey('reader-compact-next-section'));
    expect(tester.widget<IconButton>(compactPrevious).onPressed, isNull);
    expect(tester.widget<IconButton>(compactNext).onPressed, isNotNull);
    await tester.tap(compactNext);
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset,
        greaterThanOrEqualTo(nextChapterStart));
    expect(tester.widget<IconButton>(compactNext).onPressed, isNull);
    expect(tester.widget<IconButton>(compactPrevious).onPressed, isNotNull);
    expect(store.getBook(bookId)!.progressOffset, greaterThan(original));
    expect(tester.takeException(), isNull);
  });

  testWidgets('immersive EPUB header provides independent visual navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final revision = store.manualPositionRevision(bookId);
    final offset = store.getBook(bookId)!.progressOffset;

    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-section')), findsOneWidget);
    expect(find.text('Opening'), findsWidgets,
        reason: 'Publisher TOC and visible EPUB heading may share the label');
    expect(find.byKey(const ValueKey('reader-focus-section-go')), findsOneWidget);
    expect(store.manualPositionRevision(bookId), revision,
        reason: 'Entering focus is presentation-only');

    await tester.tap(find.byKey(const ValueKey('reader-focus-section')));
    await tester.pumpAndSettle();
    expect(find.text('Book table of contents'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-directory-entry-0')), findsOneWidget);
    await tester.tapAt(const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revision,
        reason: 'Opening and dismissing chapter directory does not seek');

    await tester.tap(find.byKey(const ValueKey('reader-focus-section-go')));
    await tester.pumpAndSettle();
    expect(find.text('Go to section position'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revision);
    expect(store.getBook(bookId)!.progressOffset, offset);

    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    await tester.pumpAndSettle();
    expect(find.text('Go to book position'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revision,
        reason: 'Global and section Go dialogs never persist on cancellation');

    await tester.tap(find.byKey(const ValueKey('reader-focus-section-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-75')));
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();
    final persisted = store.getBook(bookId)!.progressOffset;
    expect(persisted, greaterThan(offset));
    expect(persisted, lessThan(nextChapterStart),
        reason: 'Local 75% may not cross into the next EPUB chapter');
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing,
        reason: 'Seeking inside a chapter does not exit immersive mode');
    expect(find.byKey(const ValueKey('reader-focus-section')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
