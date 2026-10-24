import 'package:ereader/data/epub_embedded_content.dart';
import 'package:ereader/features/reader/epub_note_preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('closing a footnote peek returns false without navigation',
      (tester) async {
    bool? decision;
    const note = EpubFootnotePreview(
        42, 'A local note with 📖 Unicode text.');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            decision = await showEpubFootnotePreview(context, note);
          },
          child: const Text('Read note'),
        ),
      )),
    ));
    await tester.tap(find.text('Read note'));
    await tester.pumpAndSettle();
    expect(find.text('Footnote'), findsOneWidget);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.data, note.text);
    expect(find.text('Open in book'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(decision, isFalse);
    expect(find.text('Read note'), findsOneWidget);
    expect(find.text('Footnote'), findsNothing);
  });

  testWidgets('opening in book requires a distinct positive user action',
      (tester) async {
    bool? decision;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) =>
        FilledButton(
          onPressed: () async {
            decision = await showEpubFootnotePreview(
                context, const EpubFootnotePreview(7, 'Source-exact note.'));
          },
          child: const Text('Peek'),
        ),
      )),
    ));
    await tester.tap(find.text('Peek'));
    await tester.pumpAndSettle();
    expect(decision, isNull);
    await tester.tap(find.text('Open in book'));
    await tester.pumpAndSettle();
    expect(decision, isTrue);
  });

  testWidgets('dismissed peek never implies open-in-book permission',
      (tester) async {
    bool? decision;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            decision = await showEpubFootnotePreview(
                context, const EpubFootnotePreview(9, 'Unchanged text.'));
          },
          child: const Text('Peek'),
        ),
      )),
    ));
    await tester.tap(find.text('Peek'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(3, 3)); // modal barrier
    await tester.pumpAndSettle();
    expect(find.text('Footnote'), findsNothing);
    expect(decision, isNull);
  });

  testWidgets('long preview scrolls while retaining its two action buttons',
      (tester) async {
    final noteText = List.filled(180, 'Note detail.').join(' ');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            showEpubFootnotePreview(
                context, EpubFootnotePreview(0, noteText));
          },
          child: const Text('Peek'),
        ),
      )),
    ));
    await tester.tap(find.text('Peek'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Open in book'), findsOneWidget);
  });
}
