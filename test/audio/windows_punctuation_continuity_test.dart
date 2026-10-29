import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/audio/windows_speech_punctuation.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fully local fake: records planned breaths but never plays device audio.
class _PunctuationContinuationEngine
    implements SpeechEngine, SpeechSessionRestartAware {
  final WindowsSpeechPauseCarry _carry = WindowsSpeechPauseCarry();
  const _planner = WindowsSpeechPunctuation();
  final gaps = <Duration>[];
  final spoken = <String>[];
  int restarts = 0;
  int stops = 0;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    gaps.add(_carry.take());
    spoken.add(text);
    _carry.recordCompleted(_planner.plan(text));
  }

  @override
  Future<void> stop() async {
    stops++;
    _carry.clear();
  }

  @override
  void onNarrationRestart() {
    restarts++;
    _carry.clear();
  }

  @override
  Future<void> dispose() async => stop();
}

void main() {
  test('quoted sentence tail survives a source-aligned dialogue tag split',
      () async {
    final engine = _PunctuationContinuationEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 8, '«Vieni!»'),
        SpeechSegment(9, 20, 'disse Anna.'),
      ],
      onSegmentStarted: (_) async {},
    );
    await player.play();
    expect(engine.spoken, ['«Vieni!»', 'disse Anna.']);
    expect(engine.gaps, [
      Duration.zero, const Duration(milliseconds: 420),
    ]);
    expect(engine.restarts, 0);
    player.dispose();
  });

  test('fresh Play after natural EOF does not inherit preceding last pause',
      () async {
    final engine = _PunctuationContinuationEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 5, 'Fine.'),
      ],
      onSegmentStarted: (_) async {},
    );
    await player.play();
    expect(player.currentIndex, 1);
    expect(engine.restarts, 0);

    await player.play();
    expect(engine.spoken, ['Fine.', 'Fine.']);
    expect(engine.gaps, [Duration.zero, Duration.zero]);
    expect(engine.restarts, 1);
    expect(engine.stops, 0,
        reason: 'Natural EOF replay need not make an extra native Stop');
    player.dispose();
  });

  test('Seek resets finished punctuation before a new source start',
      () async {
    final engine = _PunctuationContinuationEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 5, 'Ciao!'),
        SpeechSegment(6, 10, 'Dopo'),
      ],
      onSegmentStarted: (_) async {},
    );
    await player.play();
    await player.seekTo(0);
    expect(engine.stops, 1);
    await player.play();
    expect(engine.gaps, [
      Duration.zero,
      const Duration(milliseconds: 420),
      Duration.zero,
      const Duration(milliseconds: 420),
    ]);
    // seekTo(0) is not a replay from EOF and must not call the hook.
    expect(engine.restarts, 0);
    player.dispose();
  });
}
