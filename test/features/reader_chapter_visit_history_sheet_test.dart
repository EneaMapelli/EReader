import 'package:ereader/features/reader/reader_chapter_visit_history.dart';
import 'package:ereader/features/reader/reader_chapter_visit_history_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ReaderChapterVisitHistory sample({int count = 3}) {
  final history = ReaderChapterVisitHistory();
  for (var i = 0; i < count; i++) {
    history.recordCommittedJump(
      fromOffset: i * 100, toOffset: i * 100 + 70,
      sourceLength: 5000,
      sectionTitle: 'Chapter ${i + 1}',
      sectionNumber: i + 1, sectionCount: count,
    );
  }
  return history;
}

Widget launcher(ReaderChapterVisitHistory history,
    ValueChanged<ReaderChapterVisit?> onSelected) => MaterialApp(
  home: Scaffold(body: Builder(
    builder: (context) => ElevatedButton(
      onPressed: () async {
        final result = await showReaderChapterVisitHistory(context,
          visits: history.recent, sourceLength: 5000);
        onSelected(result);
      },
      child: const Text('Open chapter history'),
    ),
  )),
);

void main() {
  testWidgets('history shows newest first and selects exact visit identity',
      (tester) async {
    final history = sample();
    ReaderChapterVisit? selected;
    await tester.pumpWidget(launcher(history, (visit) => selected = visit));
    await tester.tap(find.text('Open chapter history'));
    await tester.pumpAndSettle();
    expect(find.text('Recent chapter positions'), findsOneWidget);
    expect(find.text('3 saved visits in this reading session'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-history-list')),
        findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.text('Section 3 of 3 · 4% of book'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(selected, isNull, reason: 'Opening history never performs a seek');
    await tester.tap(find.byKey(const ValueKey('reader-chapter-history-entry-1')));
    await tester.pumpAndSettle();
    expect(selected, same(history.recent[1]),
        reason: 'List index is a display position, not a source offset');
    expect(history.length, 3,
        reason: 'The sheet cannot consume history; only reader seek can');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismiss and close do not change any history',
      (tester) async {
    final history = sample(count: 2);
    ReaderChapterVisit? selected;
    await tester.pumpWidget(launcher(history, (visit) => selected = visit));
    await tester.tap(find.text('Open chapter history'));
    await tester.pumpAndSettle();
    final beforeRevision = history.revision;
    await tester.tap(find.byKey(const ValueKey('reader-chapter-history-close')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(history.revision, beforeRevision);
    await tester.tap(find.text('Open chapter history'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(history.length, 2);
  });

  testWidgets('history stays scrollable on a 320px phone with 200% text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 550));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final history = sample(count: 20);
    ReaderChapterVisit? selected;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ), child: child!,
      ),
      home: Scaffold(body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            selected = await showReaderChapterVisitHistory(context,
              visits: history.recent, sourceLength: 5000);
          },
          child: const Text('Open chapter history'),
        ),
      )),
    ));
    await tester.tap(find.text('Open chapter history'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-history-entry-0')),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('reader-chapter-history-entry-19')),
      250, scrollable: find.byKey(const ValueKey('reader-chapter-history-list')),
    );
    await tester.tap(find.byKey(const ValueKey('reader-chapter-history-entry-19')));
    await tester.pumpAndSettle();
    expect(selected, same(history.recent.last));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history returns null without opening any sheet',
      (tester) async {
    final history = ReaderChapterVisitHistory();
    ReaderChapterVisit? selected;
    await tester.pumpWidget(launcher(history, (visit) => selected = visit));
    await tester.tap(find.text('Open chapter history'));
    await tester.pumpAndSettle();
    expect(find.text('Recent chapter positions'), findsNothing);
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });
}
