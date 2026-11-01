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
