import 'package:ereader/features/reader/reading_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required int offset,
  required int length,
  required ValueChanged<int> onSeek,
}) => MaterialApp(
  home: Scaffold(body: Center(
    child: SizedBox(
      width: 400,
      child: ReadingProgressBar(
        sourceOffset: offset,
        sourceLength: length,
        onSeekToOffset: onSeek,
      ),
    ),
  )),
);

void main() {
  testWidgets('percentage reflects canonical book offset without audio timing',
      (tester) async {
    await tester.pumpWidget(_host(
      offset: 250,
      length: 1000,
      onSeek: (_) {},
    ));
    expect(find.text('25%'), findsOneWidget);
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('reader-source-progress')));
    expect(slider.value, .25);
    expect(slider.semanticFormatterCallback!(.5), '50 percent of book text');
  });

  testWidgets('dragging only commits once on release, never during preview',
      (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(_host(
      offset: 200,
      length: 1000,
      onSeek: seeks.add,
    ));
    final key = find.byKey(const ValueKey('reader-source-progress'));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(seeks, isEmpty,
        reason: 'A drag does not trigger a seek or a new TTS segment');
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(seeks, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single, inInclusiveRange(0, 1000));
  });

  testWidgets('empty book disables navigation and reports 0%', (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(_host(
      offset: 100,
      length: 0,
      onSeek: seeks.add,
    ));
    expect(find.text('0%'), findsOneWidget);
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('reader-source-progress')));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);
    expect(seeks, isEmpty);
  });

  testWidgets('external playback updates percentage after user navigation',
      (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(_host(
        offset: 0, length: 200, onSeek: seeks.add));
    expect(find.text('0%'), findsOneWidget);
    await tester.pumpWidget(_host(
        offset: 160, length: 200, onSeek: seeks.add));
    expect(find.text('80%'), findsOneWidget);
    expect(seeks, isEmpty,
        reason: 'A playback update must never trigger a navigation callback');
  });
}
