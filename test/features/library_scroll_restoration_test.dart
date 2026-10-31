import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late LibraryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ereader-scroll-ui-');
    store = LibraryStore(homeDirectory: directory);
    await store.initialize();
    for (var index = 0; index < 45; index++) {
      final title = 'Volume ' + index.toString().padLeft(3, '0');
      final file = File(p.join(directory.path, title + '.txt'));
      await file.writeAsString('Text of ' + title + ', offline only.');
      await store.importFile(file.path);
    }
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<ScrollController> showLibrary(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    return tester.widget<ListView>(find.byType(ListView)).controller!;
  }

  Future<void> scrollDeeper(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
  }

  testWidgets('deep list offers an accessible back-to-top action',
      (tester) async {
    final controller = await showLibrary(tester);
    expect(find.byKey(const ValueKey('library-scroll-to-top')), findsNothing);
    await scrollDeeper(tester);
    expect(controller.offset, greaterThan(480));
    final toTop = find.byKey(const ValueKey('library-scroll-to-top'));
    expect(toTop, findsOneWidget);
    expect(tester.widget<IconButton>(toTop).tooltip, 'Back to top of library');
    await tester.tap(toTop);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(0, 0.1));
    expect(toTop, findsNothing);
    expect(store.books, hasLength(45));
  });

  testWidgets('search resets offset and clearing a zero-match view starts top',
      (tester) async {
    final controller = await showLibrary(tester);
    await scrollDeeper(tester);
    expect(controller.offset, greaterThan(480));
    final search = find.byKey(const ValueKey('library-search'));
    await tester.enterText(search, 'no-volume-has-this-title');
    await tester.pumpAndSettle();
    expect(find.text('Showing 0 of 45 books'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    await tester.tap(find.byTooltip('Clear library search'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 45 of 45 books'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        closeTo(0, 0.1));
    expect(find.byKey(const ValueKey('library-scroll-to-top')), findsNothing);
    expect(store.books, hasLength(45));
  });

  testWidgets('changing sort and format resets a deep library viewport',
      (tester) async {
    final controller = await showLibrary(tester);
    await scrollDeeper(tester);
    expect(controller.offset, greaterThan(480));
    await tester.tap(find.byKey(const ValueKey('library-compact-filters')));
    await tester.pumpAndSettle();
    final formats = find.byKey(const ValueKey('library-filter-txt'));
    await tester.ensureVisible(formats);
    await tester.tap(formats);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(0, 0.1));
    expect(store.books, hasLength(45));
    await tester.tap(find.byKey(const ValueKey('library-compact-filters')));
    await tester.pumpAndSettle();
  });

  testWidgets('opening and closing a book keeps the current catalog viewport',
      (tester) async {
    final controller = await showLibrary(tester);
    await scrollDeeper(tester);
    final previousOffset = controller.offset;
    expect(previousOffset, greaterThan(480));

    // Select a hit-testable row from the visible slice of the lazy list.
    final visibleRow = find.byType(ListTile).hitTestable().first;
    await tester.tap(visibleRow);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-search')), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-search')), findsOneWidget);
    expect(controller.offset, closeTo(previousOffset, 2),
        reason: 'Reader route changes must not reset library results');
  });
}
