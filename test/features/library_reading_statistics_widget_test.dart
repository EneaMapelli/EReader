import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-library-stats-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    for (final name in ['Alpha', 'Beta']) {
      final file = File(p.join(root.path, '$name.txt'));
      await file.writeAsString('Distinct content for $name');
      await store.importFile(file.path);
    }
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('statistics show global catalog regardless of view filters',
      (tester) async {
    final ids = {for (final b in store.books) b.title: b.id};
    store.setBookReadingStatus(ids['Alpha']!, BookReadingStatus.finished);
    await store.markBookOpened(ids['Alpha']!);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));

    await tester.enterText(
        find.byKey(const ValueKey('library-search')), 'Alpha');
    await tester.pump();
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-stats-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-stats-sheet')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('stats-total'))).data,
        '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('stats-finished'))).data,
        '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('stats-opened'))).data,
        '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('stats-recent'))).data,
        '1');
    expect(store.books, hasLength(2));
    await tester.tap(find.byTooltip('Close reading statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(store.getBook(ids['Alpha']!)!.readingStatus,
        BookReadingStatus.finished);
  });
  testWidgets('reading goal persists without changing library state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.tap(find.byKey(const ValueKey('library-stats-open')));
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const ValueKey('stats-goal-dropdown'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min').last);
    await tester.pumpAndSettle();
    expect(store.dailyReadingGoalMinutes, 30);
    await tester.tap(find.byTooltip('Close reading statistics'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-stats-open')));
    await tester.pumpAndSettle();
    expect(store.dailyReadingGoalMinutes, 30);
    expect(find.byKey(const ValueKey('stats-goal-summary')), findsOneWidget);
    expect(store.books, hasLength(2));
  });

}
