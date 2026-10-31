import 'package:ereader/features/reader/reader_focus_restore_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('restore button exposes a predictable keyboard and touch action',
      (tester) async {
    var restored = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const Center(child: Text('Page content')),
        floatingActionButton: ReaderFocusRestoreButton(
          onRestore: () => restored++,
        ),
      ),
    ));
    final restore = find.byKey(const ValueKey('reader-focus-restore'));
    expect(restore, findsOneWidget);
    expect(find.byTooltip('Show narration controls'), findsOneWidget);
    expect(find.text('Page content'), findsOneWidget);
    expect(restored, 0,
        reason: 'Displaying focus mode must never start playback');
    await tester.tap(restore);
    await tester.pump();
    expect(restored, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restore stays visible on a small phone with enlarged text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 420));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    var restoreCount = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Book')),
        body: const Center(child: Text('Long book chapter')),
        floatingActionButton: ReaderFocusRestoreButton(
          onRestore: () => restoreCount++,
        ),
      ),
    ));
    final restore = find.byKey(const ValueKey('reader-focus-restore'));
    expect(restore, findsOneWidget);
    expect(tester.getRect(restore).isEmpty, isFalse);
    await tester.tap(restore);
    await tester.pump();
    expect(restoreCount, 1);
    expect(tester.takeException(), isNull);
  });
}
