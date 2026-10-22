import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? waiting;
  Completer<void>? stopGate;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [
        SpeechVoice(name: 'Sample', locale: 'en-US'),
      ];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    spoken.add(text);
    waiting = Completer<void>();
    return waiting!.future;
  }

  @override
  Future<void> stop() async {
    if (stopGate != null) await stopGate!.future;
    if (waiting != null && !waiting!.isCompleted) waiting!.complete();
  }

  @override
  Future<void> dispose() => stop();

  void finish() {
    if (waiting != null && !waiting!.isCompleted) waiting!.complete();
  }
}

void main() {
  test('pause stops speech; resume starts same segment', () async {
    final engine = FakeSpeechEngine();
    final positions = <int>[];
    final player = ReaderPlayer(
      engine: engine,
      segments: [
        const SpeechSegment(0, 5, 'Hello'),
        const SpeechSegment(6, 11, 'world'),
      ],
      onSegmentStarted: (segment) async => positions.add(segment.start),
    );
    final first = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Hello']);
    expect(positions, [0]);
    await player.pause();
    await first;
    expect(player.currentIndex, 0);

    final second = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Hello', 'Hello']);
    engine.finish();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken.last, 'world');
    engine.finish();
    await second;
    expect(player.currentIndex, 2);
    expect(player.isPlaying, false);
    player.dispose();
  });
  test('rapid pause and play waits for native stop before speaking again', () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: [const SpeechSegment(0, 5, 'Hello')],
      onSegmentStarted: (_) async {},
    );
    final first = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Hello']);

    engine.stopGate = Completer<void>();
    final pausing = player.pause();
    final restarted = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Hello'],
        reason: 'A new utterance must wait for the previous native stop');

    engine.stopGate!.complete();
    await pausing;
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Hello', 'Hello']);
    engine.finish();
    await first;
    await restarted;
    player.dispose();
  });

  test('seek while playing returns before full book playback completes', () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: [
        const SpeechSegment(0, 4, 'One.'),
        const SpeechSegment(5, 9, 'Two.'),
      ],
      onSegmentStarted: (_) async {},
    );
    final first = player.play();
    await Future<void>.delayed(Duration.zero);
    await player.seekTo(1);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 1);
    expect(engine.spoken.last, 'Two.');
    expect(player.isPlaying, isTrue);
    engine.finish();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    player.dispose();
  });

}
