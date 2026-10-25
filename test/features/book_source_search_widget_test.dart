import 'package:ereader/features/reader/reading_tools.dart';
import 'package:ereader/domain/book_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EPUB source search navigates to silent caption source offset',
      (tester) async {
    const text = 'Narrated intro.\n\n'
        'Unspoken caption with 🐉 and diagrams.\n\nNarrated ending.';
    BookSourceMatch? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            selected = await showBookSourceSearch(context, text);
          },
          child: const Text('Open source search'),
        ),
      )),
    ));
    await tester.tap(find.text('Open source search'));
    await tester.pumpAndSettle();

    expect(find.text('Search in EPUB'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'CAPTION');
    await tester.pump(const Duration(milliseconds: 190));
    await tester.pumpAndSettle();
    expect(find.text('Matches: 1'), findsOneWidget);
    expect(find.textContaining('Unspoken caption with'), findsOneWidget);

    await tester.tap(find.textContaining('Unspoken caption with'));
    await tester.pumpAndSettle();
    expect(selected?.start, text.indexOf('caption'));
    expect(selected?.end, text.indexOf('caption') + 7);
  });

  testWidgets('EPUB search begins near reading position before wrapping',
      (tester) async {
    const text = 'echo one.\n\necho two.\n\necho three.';
    final last = text.lastIndexOf('echo');
    BookSourceMatch? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            selected = await showBookSourceSearch(
                context, text, startOffset: last);
          },
          child: const Text('Find near me'),
        ),
      )),
    ));
    await tester.tap(find.text('Find near me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'echo');
    await tester.pump(const Duration(milliseconds: 190));
    await tester.pumpAndSettle();
    expect(find.text('From reading position, then from the beginning'),
        findsOneWidget);
    final firstResult = find.byType(ListTile).first;
    expect(find.descendant(of: firstResult,
        matching: find.text('Source offset $last')), findsOneWidget);
    await tester.tap(firstResult);
    await tester.pumpAndSettle();
    expect(selected?.start, last);
  });

  testWidgets('closed search dialog never navigates or starts playback',
      (tester) async {
    const book = 'Visible text and a quiet illustration.';
    BookSourceMatch? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            selected = await showBookSourceSearch(context, book);
          },
          child: const Text('Search'),
        ),
      )),
    ));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quiet');
    await tester.pump(const Duration(milliseconds: 190));
    await tester.pumpAndSettle();
    expect(find.text('Matches: 1'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Search in EPUB'), findsNothing);
  });
}
