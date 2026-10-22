import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? waiting;

  @override
  Future<void> speak(String text,
      {required String language, required double rate}) {
    spoken.add(text);
    waiting = Completer<void>();
    return waiting!.future;
  }

  @override
  Future<void> stop() async {
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
}
