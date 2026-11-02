import 'package:ereader/features/reader/reader_focus_progress_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focus header displays original-source progress and opens Go',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(bottom: ReaderFocusProgressStrip(
          sourceOffset: 310,
          sourceLength: 1000,
          onNavigate: () => opened++,
        )),
      ),
    ));
    expect(find.text('31%'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('reader-focus-progress-track')));
    expect(bar.value, 0.31);
    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus progress clamps source offsets without changing data',
      (tester) async {
    var opened = 0;
    Future<void> show(int offset, int length) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(bottom: ReaderFocusProgressStrip(
            sourceOffset: offset,
            sourceLength: length,
            onNavigate: () => opened++,
          )),
        ),
      ));
    }

    await show(-200, 500);
    expect(find.text('0%'), findsOneWidget);
    await show(900, 500);
    expect(find.text('100%'), findsOneWidget);
    expect(opened, 0,
        reason: 'Rendering never performs a source seek or dialog action');
  });

  testWidgets('unknown source length disables the jump affordance',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(bottom: ReaderFocusProgressStrip(
          sourceOffset: 0,
          sourceLength: 0,
          onNavigate: () => opened++,
        )),
      ),
    ));
    expect(find.text('0%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small mobile viewport and enlarged labels do not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: MaterialApp(home: Scaffold(
        appBar: AppBar(bottom: ReaderFocusProgressStrip(
          sourceOffset: 123456,
          sourceLength: 1000000,
          onNavigate: () {},
        )),
      )),
    ));
    expect(find.text('12%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
