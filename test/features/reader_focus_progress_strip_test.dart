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
    final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('reader-focus-progress-semantics')));
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.onTap, isNotNull,
        reason: 'TalkBack must be able to open Go from the status strip');
    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EPUB focus header exposes separate book, TOC and section Go',
      (tester) async {
    var bookGo = 0;
    var openedToc = 0;
    var sectionGo = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      appBar: AppBar(bottom: ReaderFocusProgressStrip(
        sourceOffset: 310,
        sourceLength: 1000,
        onNavigate: () => bookGo++,
        sectionTitle: 'The Hidden Valley',
        sectionIndex: 4,
        sectionCount: 18,
        sectionProgressPercent: 64,
        onOpenSections: () => openedToc++,
        onNavigateWithinSection: () => sectionGo++,
      )),
    )));
    final strip = tester.widget<ReaderFocusProgressStrip>(
      find.byType(ReaderFocusProgressStrip));
    expect(strip.preferredSize.height, 92);
    expect(find.text('31%'), findsOneWidget,
        reason: 'Global position is not the section fraction');
    expect(find.text('The Hidden Valley'), findsOneWidget);
    expect(find.text('5/18'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    final chapterSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('reader-focus-section-semantics')));
    expect(chapterSemantics.properties.onTap, isNotNull);
    expect(chapterSemantics.properties.label,
        contains('Current EPUB section'));
    final percentSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('reader-focus-section-progress-semantics')));
    expect(percentSemantics.properties.onTap, isNotNull);
    expect(percentSemantics.properties.label,
        contains('Section text position: 64 percent'));

    await tester.tap(find.byKey(const ValueKey('reader-focus-section')));
    expect([bookGo, openedToc, sectionGo], [0, 1, 0]);
    await tester.tap(find.byKey(const ValueKey('reader-focus-section-go')));
    expect([bookGo, openedToc, sectionGo], [0, 1, 1]);
    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    expect([bookGo, openedToc, sectionGo], [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('silent or ambiguous EPUB section still opens TOC, not local Go',
      (tester) async {
    var openedToc = 0;
    var sectionGo = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      appBar: AppBar(bottom: ReaderFocusProgressStrip(
        sourceOffset: 100,
        sourceLength: 1000,
        onNavigate: () {},
        sectionTitle: 'Illustrated appendix',
        sectionIndex: 8,
        sectionCount: 9,
        onOpenSections: () => openedToc++,
        onNavigateWithinSection: () => sectionGo++,
      )),
    )));
    expect(find.text('Illustrated appendix'), findsOneWidget);
    expect(find.text('9/9'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-section-go')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reader-focus-section')));
    expect([openedToc, sectionGo], [1, 0]);
  });

  testWidgets('TXT or invalid EPUB directory index adds no contextual row',
      (tester) async {
    Future<void> show({String? title, int? index, int? count}) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(
          appBar: AppBar(bottom: ReaderFocusProgressStrip(
            sourceOffset: 20,
            sourceLength: 200,
            onNavigate: () {},
            sectionTitle: title,
            sectionIndex: index,
            sectionCount: count,
            onOpenSections: () {},
          )),
        )));
    await show();
    expect(find.byKey(const ValueKey('reader-focus-section')), findsNothing);
    await show(title: 'Bad entry', index: -1, count: 3);
    expect(find.byKey(const ValueKey('reader-focus-section')), findsNothing);
    await show(title: 'Past last', index: 3, count: 3);
    expect(find.byKey(const ValueKey('reader-focus-section')), findsNothing);
    await show(title: 'Valid', index: 1, count: 3);
    expect(find.byKey(const ValueKey('reader-focus-section')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px focus section row truncates long titles at 200 percent',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(appBar: AppBar(bottom: ReaderFocusProgressStrip(
        sourceOffset: 900,
        sourceLength: 1000,
        onNavigate: () {},
        sectionTitle: 'A very long illustrated chapter with a translated '
            'title that should not extend past the right edge of the phone',
        sectionIndex: 1999,
        sectionCount: 2000,
        sectionProgressPercent: 99,
        onOpenSections: () {},
        onNavigateWithinSection: () {},
      ))),
    ));
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-section-go')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section percent updates visually without firing navigation',
      (tester) async {
    var seeks = 0;
    Future<void> show(int offset, int localPercent) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(
          appBar: AppBar(bottom: ReaderFocusProgressStrip(
            sourceOffset: offset,
            sourceLength: 1000,
            onNavigate: () => seeks++,
            sectionTitle: 'Chapter B',
            sectionIndex: 1,
            sectionCount: 3,
            sectionProgressPercent: localPercent,
            onOpenSections: () {},
            onNavigateWithinSection: () => seeks++,
          )),
        )));
    await show(120, 10);
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    await show(450, 70);
    expect(find.text('45%'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(seeks, 0);
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
    final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('reader-focus-progress-semantics')));
    expect(semantics.properties.onTap, isNull);
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
