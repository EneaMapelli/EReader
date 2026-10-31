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
    expect(find.byTooltip('Play narration (Space)'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-expand-controls')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
