import 'package:ereader/features/reader/reader_chapter_history_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host({
  VoidCallback? back,
  VoidCallback? forward,
  VoidCallback? recent,
}) => MaterialApp(
  home: Scaffold(
    body: Center(child: ReaderChapterHistoryShortcut(
      onBack: back, onForward: forward, onRecent: recent,
    )),
  ),
);

void main() {
  testWidgets('empty history renders no inactive shortcut',
      (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(
        const ValueKey('reader-chapter-history-shortcut')),
        findsNothing);
    expect(find.byTooltip(
        'Chapter visit history: back, forward and recent positions'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one icon opens three separately named history actions',
      (tester) async {
    var backs = 0;
    var forwards = 0;
    var recents = 0;
    await tester.pumpWidget(host(
      back: () => backs++,
      forward: () => forwards++,
      recent: () => recents++,
    ));
    final trigger = find.byKey(
        const ValueKey('reader-chapter-history-shortcut'));
    expect(trigger, findsOneWidget);
    expect(find.byTooltip(
        'Chapter visit history: back, forward and recent positions'),
        findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-back')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-forward')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-recent')),
        findsOneWidget);
    expect([backs, forwards, recents], [0, 0, 0],
        reason: 'Opening the popup must never seek');
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-back')));
    await tester.pumpAndSettle();
    expect([backs, forwards, recents], [1, 0, 0]);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-forward')));
    await tester.pumpAndSettle();
    expect([backs, forwards, recents], [1, 1, 0]);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-recent')));
    await tester.pumpAndSettle();
    expect([backs, forwards, recents], [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back only and Forward only expose no invalid actions',
      (tester) async {
    var backs = 0;
    var forwards = 0;
    await tester.pumpWidget(host(back: () => backs++));
    final trigger = find.byKey(
        const ValueKey('reader-chapter-history-shortcut'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('Back to previous visited position'), findsOneWidget);
    expect(find.text('Forward to next visited position'), findsNothing);
    expect(find.text('Recent chapter positions'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(backs, 0, reason: 'Canceling an action does not seek');

    await tester.pumpWidget(host(forward: () => forwards++));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('Back to previous visited position'), findsNothing);
    expect(find.text('Forward to next visited position'), findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-forward')));
    await tester.pumpAndSettle();
    expect([backs, forwards], [0, 1]);
  });

  testWidgets('recent positions can be the only available popup action',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(host(recent: () => opened++));
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-history-shortcut')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-back')),
        findsNothing);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-forward')),
        findsNothing);
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-shortcut-recent')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('320px 200 percent text shows accessible history menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: Center(
        child: ReaderChapterHistoryShortcut(
          onBack: () {}, onForward: () {}, onRecent: () {},
        ),
      )),
    ));
    await tester.tap(find.byKey(
        const ValueKey('reader-chapter-history-shortcut')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-back')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-forward')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-chapter-shortcut-recent')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
