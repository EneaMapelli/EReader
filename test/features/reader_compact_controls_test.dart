import 'package:ereader/features/reader/reader_compact_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required VoidCallback onPrevious,
  required VoidCallback onPlayPause,
  required VoidCallback onNext,
  required VoidCallback onExpand,
  bool playing = false,
  bool sleepTimerActive = false,
  String segment = 'Segment 12 of 300',
  String? sectionLabel,
  int? sectionIndex,
  int? sectionCount,
  int? sectionProgressPercent,
  VoidCallback? onOpenSections,
  VoidCallback? onPreviousSection,
  VoidCallback? onNextSection,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Material(
              child: ReaderCompactControls(
                segmentLabel: segment,
                isPlaying: playing,
                sleepTimerActive: sleepTimerActive,
                sectionLabel: sectionLabel,
                sectionIndex: sectionIndex,
                sectionCount: sectionCount,
                sectionProgressPercent: sectionProgressPercent,
                onOpenSections: onOpenSections,
                onPreviousSection: onPreviousSection,
                onNextSection: onNextSection,
                onPrevious: onPrevious,
                onPlayPause: onPlayPause,
                onNext: onNext,
                onExpand: onExpand,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('compact bar exposes all four controls without invoking audio',
      (tester) async {
    var previous = 0;
    var play = 0;
    var next = 0;
    var expand = 0;
    await tester.pumpWidget(_host(
      onPrevious: () => previous++,
      onPlayPause: () => play++,
      onNext: () => next++,
      onExpand: () => expand++,
    ));
    expect(find.text('Segment 12 of 300'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-compact-previous')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-compact-play-pause')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-compact-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-expand-controls')), findsOneWidget);
    expect([previous, play, next, expand], [0, 0, 0, 0]);
    await tester.tap(find.byKey(const ValueKey('reader-compact-previous')));
    await tester.tap(find.byKey(const ValueKey('reader-compact-play-pause')));
    await tester.tap(find.byKey(const ValueKey('reader-compact-next')));
    await tester.tap(find.byKey(const ValueKey('reader-expand-controls')));
    expect([previous, play, next, expand], [1, 1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible EPUB chapter is a shortcut, not a TTS seek',
      (tester) async {
    var opened = 0;
    var played = 0;
    var skipped = 0;
    await tester.pumpWidget(_host(
      onPrevious: () => skipped++,
      onPlayPause: () => played++,
      onNext: () => skipped++,
      onExpand: () {},
      sectionLabel: 'The Hidden Valley',
      sectionIndex: 4,
      sectionCount: 18,
      onOpenSections: () => opened++,
    ));
    final chapter = find.byKey(
        const ValueKey('reader-compact-current-section'));
    expect(chapter, findsOneWidget);
    expect(find.text('The Hidden Valley (5/18)'), findsOneWidget);
    await tester.tap(chapter);
    expect([opened, played, skipped], [1, 0, 0],
        reason: 'Opening the TOC cannot start or seek speech');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter arrows switch sections without using TTS transport',
      (tester) async {
    var chapterPrevious = 0;
    var chapterNext = 0;
    var audioPrevious = 0;
    var audioNext = 0;
    var directory = 0;
    await tester.pumpWidget(_host(
      onPrevious: () => audioPrevious++,
      onPlayPause: () {},
      onNext: () => audioNext++,
      onExpand: () {},
      sectionLabel: 'Chapter Two',
      sectionIndex: 1,
      sectionCount: 3,
      onOpenSections: () => directory++,
      onPreviousSection: () => chapterPrevious++,
      onNextSection: () => chapterNext++,
    ));
    final prev = find.byKey(
        const ValueKey('reader-compact-previous-section'));
    final next = find.byKey(
        const ValueKey('reader-compact-next-section'));
    expect(prev, findsOneWidget);
    expect(next, findsOneWidget);
    expect(find.byTooltip('Previous EPUB section'), findsOneWidget);
    expect(find.byTooltip('Next EPUB section'), findsOneWidget);
    await tester.tap(prev);
    await tester.tap(next);
    expect([chapterPrevious, chapterNext], [1, 1]);
    expect([audioPrevious, audioNext, directory], [0, 0, 0],
        reason: 'Chapter navigation never sends transport skip callbacks');
    await tester.tap(find.byKey(
        const ValueKey('reader-compact-current-section')));
    expect(directory, 1);
    expect([audioPrevious, audioNext], [0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter arrows disable at source boundaries',
      (tester) async {
    void noop() {}
    Future<void> build(int index, {VoidCallback? previous,
        VoidCallback? next}) => tester.pumpWidget(_host(
      onPrevious: noop, onPlayPause: noop,
      onNext: noop, onExpand: noop,
      sectionLabel: 'Current',
      sectionIndex: index, sectionCount: 2,
      onOpenSections: noop,
      onPreviousSection: previous, onNextSection: next,
    ));
    await build(0, next: noop);
    final previousButton = find.byKey(
        const ValueKey('reader-compact-previous-section'));
    final nextButton = find.byKey(
        const ValueKey('reader-compact-next-section'));
    expect(tester.widget<IconButton>(previousButton).onPressed, isNull);
    expect(tester.widget<IconButton>(nextButton).onPressed, isNotNull);
    await build(1, previous: noop);
    expect(tester.widget<IconButton>(previousButton).onPressed, isNotNull);
    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
    await build(0);
    expect(tester.widget<IconButton>(previousButton).onPressed, isNull);
    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter-local progress shows without changing narration',
      (tester) async {
    var opened = 0;
    void noop() {}
    await tester.pumpWidget(_host(
      onPrevious: noop,
      onPlayPause: noop,
      onNext: noop,
      onExpand: noop,
      sectionLabel: 'Section A',
      sectionIndex: 1,
      sectionCount: 5,
      sectionProgressPercent: 64,
      onOpenSections: () => opened++,
    ));
    expect(find.byKey(const ValueKey('reader-compact-section-progress')),
        findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(opened, 0);
    await tester.tap(find.byKey(
        const ValueKey('reader-compact-current-section')));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown source boundaries hide local progress',
      (tester) async {
    void noop() {}
    await tester.pumpWidget(_host(
      onPrevious: noop, onPlayPause: noop,
      onNext: noop, onExpand: noop,
      sectionLabel: 'Silent illustration',
      sectionIndex: 0, sectionCount: 3,
      onOpenSections: noop,
    ));
    expect(find.byKey(const ValueKey('reader-compact-current-section')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-compact-section-progress')),
        findsNothing,
        reason: 'Silent sections do not imply measurable source progress');
  });

  testWidgets('section context responds to viewport changes without audio',
      (tester) async {
    var opened = 0;
    void noop() {}
    Future<void> display(String title, int index) =>
        tester.pumpWidget(_host(
          onPrevious: noop, onPlayPause: noop, onNext: noop, onExpand: noop,
          sectionLabel: title, sectionIndex: index,
          sectionCount: 3, onOpenSections: () => opened++,
        ));
    await display('Opening', 0);
    expect(find.text('Opening (1/3)'), findsOneWidget);
    await display('Illustrated appendix', 2);
    expect(find.text('Illustrated appendix (3/3)'), findsOneWidget);
    expect(find.text('Opening (1/3)'), findsNothing);
    expect(opened, 0,
        reason: 'Visual position changes only update a label');
  });

  testWidgets('TXT and invalid chapter positions hide section shortcut',
      (tester) async {
    void noop() {}
    await tester.pumpWidget(_host(
      onPrevious: noop, onPlayPause: noop, onNext: noop, onExpand: noop,
    ));
    expect(find.byKey(const ValueKey('reader-compact-current-section')),
        findsNothing);
    await tester.pumpWidget(_host(
      onPrevious: noop, onPlayPause: noop, onNext: noop, onExpand: noop,
      sectionLabel: 'Invalid source index',
      sectionIndex: -1, sectionCount: 7, onOpenSections: noop,
    ));
    expect(find.byKey(const ValueKey('reader-compact-current-section')),
        findsNothing);
    await tester.pumpWidget(_host(
      onPrevious: noop, onPlayPause: noop, onNext: noop, onExpand: noop,
      sectionLabel: 'No action',
      sectionIndex: 0, sectionCount: 7,
    ));
    expect(find.byKey(const ValueKey('reader-compact-current-section')),
        findsNothing);
  });

  testWidgets('playing status updates accessible play/pause hint and icon',
      (tester) async {
    void noop() {}
    await tester.pumpWidget(_host(
      onPrevious: noop,
      onPlayPause: noop,
      onNext: noop,
      onExpand: noop,
      playing: true,
      sleepTimerActive: true,
      segment: 'Reading complete — Play to restart',
    ));
    expect(find.text('Reading complete — Play to restart'), findsOneWidget);
    expect(find.byTooltip('Pause narration (Space)'), findsOneWidget);
    expect(find.byTooltip('More narration controls (sleep timer active)'),
        findsOneWidget);
    final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('reader-compact-play-pause')));
    expect(button.icon, isA<Icon>());
    expect((button.icon as Icon).icon, Icons.pause);
  });

  testWidgets('narrow phone at 200% text wraps controls without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 420));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    void noop() {}
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ReaderCompactControls(
            segmentLabel: 'Segment 999 of 9999',
            sectionLabel: 'A very long illustrated EPUB chapter title that '
                'must fit within the tiny phone viewport',
            sectionIndex: 999,
            sectionCount: 1200,
            onOpenSections: noop,
            onPreviousSection: noop,
            onNextSection: noop,
            isPlaying: false,
            onPrevious: noop,
            onPlayPause: noop,
            onNext: noop,
            onExpand: noop,
          ),
        ),
      ),
    ));
    expect(find.text('Segment 999 of 9999'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-compact-current-section')),
        findsOneWidget);
    expect(find.byTooltip('Play narration (Space)'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-expand-controls')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
