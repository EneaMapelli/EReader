import 'dart:async';
import 'dart:io';

import 'package:ereader/data/android_picker_recovery.dart';
import 'package:ereader/data/batch_book_import.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-lost-picker-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  BatchPickedBook streamed(String name, String contents, {
    void Function()? onRead,
  }) => BatchPickedBook(
    name: name,
    pickedPath: null,
    readAsByteStream: () {
      onRead?.call();
      return Stream<List<int>>.value(contents.codeUnits);
    },
  );

  testWidgets('Android lost picker selection is imported once and stays in library',
      (tester) async {
    var reads = 0;
    var recoveries = 0;
    final pending = Completer<InterruptedBookSelection?>();
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(
      store: store,
      retrieveInterruptedPick: () {
        recoveries++;
        return pending.future;
      },
    )));
    await tester.pump();
    expect(recoveries, 1);
    pending.complete(InterruptedBookSelection(selections: [
      streamed('Recovered.txt', 'Recovered offline book.', onRead: () => reads++),
    ]));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (store.books.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(store.books, hasLength(1));
    expect(store.books.single.title, 'Recovered');
    expect(await File(store.books.single.localPath).readAsString(),
        'Recovered offline book.');
    expect(reads, 1);
    expect(recoveries, 1);
    expect(find.byType(LibraryScreen), findsOneWidget,
        reason: 'A restored pick must not auto-open the reader');
    expect(find.textContaining('Recovered your interrupted book selection'),
        findsOneWidget);
  });

  testWidgets('recovered native failure shows generic error without importing',
      (tester) async {
    var recoveries = 0;
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(
      store: store,
      retrieveInterruptedPick: () async {
        recoveries++;
        return const InterruptedBookSelection.failure();
      },
    )));
    await tester.pump();
    await tester.pump();
    expect(recoveries, 1);
    expect(store.books, isEmpty);
    expect(find.textContaining('could not be recovered'), findsOneWidget);
  });

  testWidgets('an excessive recovered pick is rejected before any stream read',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(
      store: store,
      retrieveInterruptedPick: () async => InterruptedBookSelection(
        selections: List.generate(
          51,
          (i) => streamed('Book$i.txt', 'Book', onRead: () => reads++),
        ),
      ),
    )));
    await tester.pump();
    await tester.pump();
    expect(reads, 0);
    expect(store.books, isEmpty);
    expect(find.textContaining('at most 50 books'), findsOneWidget);
  });

  testWidgets('empty Android recovery is an ordinary no-op', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(
      store: store,
      retrieveInterruptedPick: () async => null,
    )));
    await tester.pump();
    await tester.pump();
    expect(store.books, isEmpty);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
