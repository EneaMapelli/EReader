import 'package:ereader/domain/book.dart';
import 'package:ereader/features/library/library_quick_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookRecord _book(String id, String title, {String? author, String? series}) =>
    BookRecord(
      id: id,
      title: title,
      author: author,
      series: series,
      localPath: '/virtual/' + id + '.txt',
      format: BookFormat.txt,
      importedAt: DateTime.utc(2024),
    );

Future<ValueNotifier<BookRecord?>> _launch(
  WidgetTester tester,
  List<BookRecord> books,
) async {
  final chosen = ValueNotifier<BookRecord?>(null);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async {
        chosen.value = await showQuickOpenBookDialog(context, books: books);
      },
      child: const Text('Launch quick open'),
    ))),
  ));
  await tester.tap(find.text('Launch quick open'));
  await tester.pumpAndSettle();
  return chosen;
}

void main() {
  testWidgets('dialog autofocus, search fields, choose a book and close',
      (tester) async {
    final chosen = await _launch(tester, [
      _book('alpha', 'Atlas of Stars', author: 'Ada', series: 'Sky'),
      _book('beta', 'Ocean History', author: 'Maria'),
    ]);
    addTearDown(chosen.dispose);
    final query = find.byKey(const ValueKey('quick-open-query'));
    expect(tester.widget<TextField>(query).autofocus, isTrue);
    expect(find.text('2 books found'), findsOneWidget);
    await tester.enterText(query, 'ada sky');
    await tester.pumpAndSettle();
    expect(find.text('1 book found'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-open-book-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-open-book-beta')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quick-open-book-alpha')));
    await tester.pumpAndSettle();
    expect(chosen.value?.id, 'alpha');
    expect(find.text('Quick open book'), findsNothing);
  });

  testWidgets('cancel and empty search do not select a book', (tester) async {
    final chosen = await _launch(tester, [
      _book('first', 'First'), _book('second', 'Second'),
    ]);
    addTearDown(chosen.dispose);
    final query = find.byKey(const ValueKey('quick-open-query'));
    await tester.enterText(query, 'not-a-title');
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching books'), findsOneWidget);
    expect(find.text('0 books found'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chosen.value, isNull);
  });

  testWidgets('all 1000 titles are counted but visible result set capped at 40',
      (tester) async {
    final books = [
      for (var i = 0; i < 1000; i++)
        _book('item-' + i.toString(), 'Book ' + i.toString()),
    ];
    final chosen = await _launch(tester, books);
    addTearDown(chosen.dispose);
    expect(find.text('Showing 40 of 1000 books'), findsOneWidget);
    final list = tester.widget<ListView>(
        find.byKey(const ValueKey('quick-open-results')));
    expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount, 40);
    expect(find.byKey(const ValueKey('quick-open-book-item-0')),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('quick-open-query')), 'Book 777');
    await tester.pumpAndSettle();
    expect(find.text('1 book found'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-open-book-item-777')));
    await tester.pumpAndSettle();
    expect(chosen.value?.id, 'item-777');
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen and enlarged font retain a dismissible dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final chosen = ValueNotifier<BookRecord?>(null);
    addTearDown(chosen.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.7),
        ),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          chosen.value = await showQuickOpenBookDialog(context, books: [
            _book('alpha', 'A much longer first title for accessibility'),
          ]);
        },
        child: const Text('Open books'),
      ))),
    ));
    await tester.tap(find.text('Open books'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-open-query')), findsOneWidget);
    expect(find.text('Quick open book'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chosen.value, isNull);
    expect(tester.takeException(), isNull);
  });
}
