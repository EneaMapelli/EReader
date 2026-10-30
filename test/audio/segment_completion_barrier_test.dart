import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deterministic fake: finishing one utterance simulates the native
/// completion callback; no platform engine or actual audio is required.
class _CompleteSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  final runs = <Completer<void>>[];

  @override
  Future<List<SpeechVoice>> listVoices() async => const [];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    spoken.add(text);
    final run = Completer<void>();
    runs.add(run);
    return run.future;
  }

  void finish(int index) {
    final run = runs[index];
    if (!run.isCompleted) run.complete();
  }

  @override
  Future<void> stop() async {
    for (var index = 0; index < runs.length; index++) {
      finish(index);
    }
  }

  @override
  Future<void> dispose() => stop();
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected speech/checkpoint event never arrived');
}

void main() {
  const segments = [
    SpeechSegment(0, 3, 'One'),
    SpeechSegment(4, 7, 'Two'),
    SpeechSegment(8, 13, 'Three'),
  ];

  test('pause during completed clip acknowledgment never replays it',
      () async {
    final engine = _CompleteSpeechEngine();
    final ack = Completer<void>();
    final confirmed = <int>[];
    final player = ReaderPlayer(
      engine: engine, segments: segments,
      onSegmentStarted: (_) async {},
      onSegmentCompleted: (finished, _) async {
        await ack.future;
        confirmed.add(finished.start);
      },
    );
    final reading = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.finish(0);
    await _until(() => player.isCommittingSpeechSegment);
    final pausing = player.pause();
    await Future<void>.delayed(Duration.zero);
    expect(player.isSettledIdle, isFalse);
    expect(player.currentIndex, 0);
    ack.complete();
    await pausing;
    await reading;
    expect(confirmed, [0]);
    expect(player.isCommittingSpeechSegment, isFalse);
    expect(player.currentIndex, 1);
    expect(player.isSettledIdle, isTrue);
    final resumed = player.play();
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Two']);
    await player.pause();
    await resumed;
    player.dispose();
  });

  test('seek during pending completed clip waits then chooses new target',
      () async {
    final engine = _CompleteSpeechEngine();
    final ack = Completer<void>();
    final player = ReaderPlayer(
      engine: engine, segments: segments,
      onSegmentStarted: (_) async {},
      onSegmentCompleted: (finished, _) => ack.future,
    );
    final first = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.finish(0);
    await _until(() => player.isCommittingSpeechSegment);
    final seeking = player.seekTo(2);
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['One']);
    expect(player.isSettledIdle, isFalse);
    ack.complete();
    await seeking;
    await first;
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Three']);
    expect(player.currentIndex, 2);
    await player.pause();
    player.dispose();
  });

  test('Play during delayed Pause does not overtake checkpoint or Stop',
      () async {
    final engine = _CompleteSpeechEngine();
    final ack = Completer<void>();
    final player = ReaderPlayer(
      engine: engine, segments: segments,
      onSegmentStarted: (_) async {},
      onSegmentCompleted: (finished, _) => ack.future,
    );
    final first = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.finish(0);
    await _until(() => player.isCommittingSpeechSegment);
    final pausing = player.pause();
    final resumed = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['One']);
    ack.complete();
    await pausing;
    await first;
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Two']);
    await player.pause();
    await resumed;
    player.dispose();
  });

  test('rejected completion checkpoint retains last safe replay anchor',
      () async {
    final engine = _CompleteSpeechEngine();
    final ack = Completer<void>();
    final player = ReaderPlayer(
      engine: engine, segments: segments,
      onSegmentStarted: (_) async {},
      onSegmentCompleted: (finished, _) => ack.future,
    );
    final first = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.finish(0);
    await _until(() => player.isCommittingSpeechSegment);
    final pausing = player.pause();
    ack.completeError(StateError('Database commit rejected'));
    await expectLater(first, throwsStateError);
    await pausing;
    expect(player.currentIndex, 0);
    expect(player.isSettledIdle, isTrue);
    // Don't automatically skip a clip if its durable completion failed.
    player.dispose();
  });
}
