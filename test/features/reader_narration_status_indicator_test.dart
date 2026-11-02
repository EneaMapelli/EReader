import 'package:ereader/features/reader/reader_narration_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('position labels do not confuse text location with speech progress',
      () {
    expect(readerNarrationPositionLabel(
        currentIndex: 0, segmentCount: 23), 'TTS 1/23');
    expect(readerNarrationPositionLabel(
        currentIndex: 11, segmentCount: 23), 'TTS 12/23');
    expect(readerNarrationPositionLabel(
        currentIndex: 23, segmentCount: 23), 'TTS complete');
    expect(readerNarrationPositionLabel(
        currentIndex: 0, segmentCount: 0), 'TTS unavailable');
    expect(readerNarrationPositionLabel(
        currentIndex: -1, segmentCount: 10), 'TTS 1/10');
    expect(readerNarrationPositionSemantics(
        currentIndex: 11, segmentCount: 23, isPlaying: true),
        'Narration playing, segment 12 of 23; viewing elsewhere');
    expect(readerNarrationPositionSemantics(
        currentIndex: 11, segmentCount: 23, isPlaying: false),
        'Narration paused, segment 12 of 23; viewing elsewhere');
    expect(readerNarrationPositionSemantics(
        currentIndex: 23, segmentCount: 23, isPlaying: false),
        'Narration complete; viewing elsewhere');
  });

  testWidgets('detached narrator status updates without audio actions',
      (tester) async {
    Future<void> paint(int index, bool playing) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReaderNarrationStatusIndicator(
            currentIndex: index,
            segmentCount: 30,
            isPlaying: playing,
          ),
        ),
      ));
      await tester.pump();
    }

    await paint(2, true);
    expect(find.text('TTS 3/30'), findsOneWidget);
    final statusKey = const ValueKey('reader-detached-narration-status');
    var status = tester.widget<Semantics>(find.byKey(statusKey));
    expect(status.properties.label,
        'Narration playing, segment 3 of 30; viewing elsewhere');
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(Chip), findsOneWidget);

    await paint(9, true);
    expect(find.text('TTS 10/30'), findsOneWidget);
    expect(find.text('TTS 3/30'), findsNothing);
    await paint(9, false);
    status = tester.widget<Semantics>(find.byKey(statusKey));
    expect(status.properties.label,
        'Narration paused, segment 10 of 30; viewing elsewhere');
    expect(tester.takeException(), isNull);
  });
}
