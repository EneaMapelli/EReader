import 'dart:async';
import 'dart:io';

import 'package:ereader/data/android_shared_book_inbox.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeShareInbox implements AndroidSharedBookInbox {
  final books = <AndroidSharedBook>[];
  final released = <String>[];
  final content = <String, List<int>>{};
  void Function()? notify;

  @override
  Future<List<AndroidSharedBook>> pending() async =>
      List.unmodifiable(books.where((book) => !released.contains(book.id)));
  @override
  Stream<List<int>> read(String id) => content.containsKey(id)
      ? Stream.value(content[id]!)
      : Stream.error(const FileSystemException('Provider denied access'));
  @override
  Future<void> finish(List<String> ids) async => released.addAll(ids);
  @override
  void listen(void Function() onAvailable) => notify = onAvailable;
  @override
  void dispose() => notify = null;
}

void main() {
  late Directory root;
  late LibraryStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-shared-books-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('cold share imports book without opening player',
      (tester) async {
    final fake = FakeShareInbox()
      ..books.add(const AndroidSharedBook(id: 'first', name: 'Shared.txt'))
      ..content['first'] = 'A book shared from Android'.codeUnits;
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(
      store: store, sharedBookInbox: fake,
    )));
    await tester.runAsync(() async {
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (fake.released.isEmpty && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(fake.released, ['first']);
    expect(store.books.single.title, 'Shared');
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.textContaining('Narration will not start automatically'),
        findsOneWidget);
  });

  testWidgets('warm batch imports good item, isolates failure and releases both',
      (tester) async {
    final fake = FakeShareInbox();
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(
      store: store, sharedBookInbox: fake,
    )));
    await tester.pump();
    fake.books.addAll(const [
      AndroidSharedBook(id: 'good', name: 'Good.txt'),
      AndroidSharedBook(id: 'invalid', name: 'Broken.epub'),
    ]);
    fake.content['good'] = 'This chapter is readable'.codeUnits;
    fake.content['invalid'] = [1, 2, 3];
    fake.notify?.call();
    await tester.runAsync(() async {
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (fake.released.length < 2 && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(fake.released, ['good', 'invalid']);
    expect(store.books.map((book) => book.title), ['Good']);
    expect(find.text('Book import summary'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
