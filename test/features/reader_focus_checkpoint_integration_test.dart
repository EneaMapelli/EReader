import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late LibraryStore store;
  late String bookId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader-focus-checkpoint-');
    store = LibraryStore(homeDirectory: directory);
    await store.initialize();
    final file = File(p.join(directory.path, 'Long sample.txt'));
    await file.writeAsString(
      List<String>.generate(90, (i) =>
        'Chapter ${i + 1}. This is offline reading text for testing ' +
        'visual reader viewport and narration controls.').join('\n\n'),
    );
    final imported = await store.importFile(file.path);
    bookId = imported.id;
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('rotation and split-screen viewport changes do not save '
      'new reading position', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final initialRevision = store.manualPositionRevision(bookId);
    final initialOffset = store.getBook(bookId)!.progressOffset;

    // Neither a wider split window nor a shorter rotated viewport is
    // evidence that the user deliberately moved to another paragraph.
    await tester.binding.setSurfaceSize(const Size(610, 690));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    expect(store.manualPositionRevision(bookId), initialRevision);
    expect(store.getBook(bookId)!.progressOffset, initialOffset);

    await tester.binding.setSurfaceSize(const Size(780, 390));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    expect(store.manualPositionRevision(bookId), initialRevision);
    expect(store.getBook(bookId)!.progressOffset, initialOffset);

    await tester.binding.setSurfaceSize(const Size(390, 780));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    expect(store.manualPositionRevision(bookId), initialRevision,
        reason: 'Reflow cannot overwrite a persistent bookmark');
    expect(store.getBook(bookId)!.progressOffset, initialOffset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F11 toggles focus progress without changing saved position',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final original = store.manualPositionRevision(bookId);

    expect(find.byKey(const ValueKey('reader-focus-progress')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    expect(store.manualPositionRevision(bookId), original);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsNothing);
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsOneWidget);
    expect(store.manualPositionRevision(bookId), original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus mode retains an accessible position and explicit Go',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    final originalOffset = store.getBook(bookId)!.progressOffset;
    final originalRevision = store.manualPositionRevision(bookId);

    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        toggle, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-restore')), findsOneWidget);
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Opening immersion mode is never an implicit source seek');

    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-progress-confirm')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Opening and canceling Go does not save a bookmark');
    expect(store.getBook(bookId)!.progressOffset, originalOffset);

    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-75')));
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();
    expect(store.getBook(bookId)!.progressOffset, greaterThan(originalOffset),
        reason: 'Confirmed Go reuses the exact-source navigation pipeline');
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing,
        reason: 'Go does not exit focus mode or start narration');
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus and advanced panels never persist an idle relayout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    final originalRevision = store.manualPositionRevision(bookId);

    await tester.tap(find.byKey(const ValueKey('reader-expand-controls')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-advanced-controls-scroll')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Expanding voice settings is not a reading seek');

    await tester.tap(find.byKey(const ValueKey('reader-collapse-controls')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Collapsing settings must not move the saved checkpoint');

    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
      toggle, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    final restore = find.byKey(const ValueKey('reader-focus-restore'));
    expect(restore, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Changing the viewport height must not write a bookmark');

    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsOneWidget);
    expect(store.manualPositionRevision(bookId), originalRevision,
        reason: 'Restoring transport must not overwrite book progress');
    expect(tester.takeException(), isNull);
  });
}
