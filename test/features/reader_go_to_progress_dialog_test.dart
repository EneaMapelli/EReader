import 'package:ereader/features/reader/reader_go_to_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('whole percentage validation rejects out-of-range or malformed text',
      () {
    expect(parseReaderProgressPercent('0'), 0);
    expect(parseReaderProgressPercent('100'), 100);
    expect(parseReaderProgressPercent(' 75 '), 75);
    expect(parseReaderProgressPercent('001'), 1);
    for (final invalid in ['-1', '101', '1.5', '', ' ', '999', '1e2', '1%']) {
      expect(parseReaderProgressPercent(invalid), isNull, reason: invalid);
    }
    expect(readerProgressOffsetForPercent(25, 1001), 250);
    expect(readerProgressOffsetForPercent(100, 1001), 1001);
    expect(readerProgressOffsetForPercent(0, 1001), 0);
    expect(() => readerProgressOffsetForPercent(-1, 100), throwsArgumentError);
    expect(() => readerProgressOffsetForPercent(101, 100), throwsArgumentError);
    expect(() => readerProgressOffsetForPercent(10, 0), throwsArgumentError);
  });

  testWidgets('Cancel does not return any seek target', (tester) async {
    int? result = -5;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showReaderGoToProgressDialog(
                context, currentSourceOffset: 250, sourceLength: 1000);
          },
          child: const Text('Open location'),
        )),
      ),
    ));
    await tester.tap(find.text('Open location'));
    await tester.pumpAndSettle();
    expect(find.text('Go to book position'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('quick 100% target is only returned after explicit Go',
      (tester) async {
    int? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showReaderGoToProgressDialog(
                context, currentSourceOffset: 0, sourceLength: 101);
          },
          child: const Text('Open'),
        )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-100')));
    await tester.pump();
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();
    expect(result, 101);
  });

  testWidgets('invalid input disables Go, valid number returns source offset',
      (tester) async {
    int? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showReaderGoToProgressDialog(
                context, currentSourceOffset: 700, sourceLength: 1000);
          },
          child: const Text('Open'),
        )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('reader-progress-percent'));
    await tester.enterText(input, '101');
    await tester.pump();
    final confirm = find.byKey(const ValueKey('reader-progress-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(result, isNull);
    await tester.enterText(input, '63');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, 630);
  });

  testWidgets('reused percentage dialog exposes section-specific labels',
      (tester) async {
    int? result = -1;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await showReaderGoToProgressDialog(
            context,
            currentSourceOffset: 40,
            sourceLength: 200,
            title: 'Go to section position',
            explanation: 'Choose a percentage within this EPUB section.',
            fieldLabel: 'Section position',
          );
        },
        child: const Text('Open section'),
      )),
    )));
    await tester.tap(find.text('Open section'));
    await tester.pumpAndSettle();
    expect(find.text('Go to section position'), findsOneWidget);
    expect(find.text('Choose a percentage within this EPUB section.'),
        findsOneWidget);
    expect(find.text('Section position'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-100')));
    await tester.pump();
    expect(result, -1,
        reason: 'Selecting a chip never issues a source seek');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tester.tap(find.text('Open section'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-75')));
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();
    expect(result, 150,
        reason: 'Caller converts local coordinates to original EPUB offsets');
  });

  testWidgets('dialog remains usable on narrow screens with enlarged text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showReaderGoToProgressDialog(
              context, currentSourceOffset: 50, sourceLength: 500),
          child: const Text('Open'),
        ),
      )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-progress-percent')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-progress-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
