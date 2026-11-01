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
    directory = await Directory.systemTemp.createTemp('reader-return-progress-');
    store = LibraryStore(homeDirectory: directory);
    await store.initialize();
    final file = File(p.join(directory.path, 'Reading return sample.txt'));
    await file.writeAsString(
      List<String>.generate(100, (i) =>
        'Paragraph ${i + 1}. A clear, offline text passage for progress '
        'navigation and checkpoint recovery integration.').join('\n\n'),
    );
    bookId = (await store.importFile(file.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> openReaderTools(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
  }

  Future<void> chooseTool(WidgetTester tester, String id) async {
    final choice = find.byKey(ValueKey('organized-action-' + id));
    await tester.scrollUntilVisible(
      choice, 180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(choice);
    await tester.pumpAndSettle();
  }

  testWidgets('confirmed Go adds a one-shot return to previous text position',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 780));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    final original = store.getBook(bookId)!.progressOffset;

    await openReaderTools(tester);
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsNothing);
    await chooseTool(tester, 'go-to-percent');
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-75')));
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();

    final jumped = store.getBook(bookId)!.progressOffset;
    expect(jumped, greaterThan(original));
    await openReaderTools(tester);
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsOneWidget);
    await chooseTool(tester, 'return-to-percent');
    expect(store.getBook(bookId)!.progressOffset, original);

    await openReaderTools(tester);
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling the percentage dialog never creates a return',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    final before = store.manualPositionRevision(bookId);
    await openReaderTools(tester);
    await chooseTool(tester, 'go-to-percent');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), before);
    await openReaderTools(tester);
    expect(find.byKey(const ValueKey('organized-action-return-to-percent')),
        findsNothing);
  });
}
