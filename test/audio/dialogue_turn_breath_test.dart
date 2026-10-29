import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrator = SpeechVoice(name: 'Narrator', locale: 'it-IT');
const _actor = SpeechVoice(name: 'Actor', locale: 'it-IT');

class _FastCastSpeechEngine implements SpeechEngine {
  final passages = <String>[];
  final voiced = <String?>[];
  String? chosen;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [_narrator, _actor];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    chosen = voice.name;
  }

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    passages.add(text);
    voiced.add(chosen);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected speech progress was not reached');
}

Future<ReaderPlayer> _setUpPlayer(
  _FastCastSpeechEngine engine, {
  required List<SpeechSegment> segments,
  required Duration pause,
  String provider = 'system',
  SegmentStarted? started,
  SegmentCompleted? completed,
}) async {
  final player = ReaderPlayer(
    engine: engine,
    engineProviderId: provider,
    segments: segments,
    dialogueTurnPause: pause,
    onSegmentStarted: started ?? (_) async {},
    onSegmentCompleted: completed,
  );
  await player.loadVoices();
  await player.applyPreferences(SpeechPreferences(
    providerId: provider,
    language: 'it-IT',
    voiceName: _narrator.name,
    voiceLocale: _narrator.locale,
  ));
  return player;
}

void main() {
  test('system speech inserts brief breaths only when cast voice changes',
      () async {
    final engine = _FastCastSpeechEngine();
    final checkpoints = <int>[];
    final player = await _setUpPlayer(
      engine,
      segments: const [
        SpeechSegment(0, 4, 'Uno.'),
        SpeechSegment(5, 9, 'Due.'),
        SpeechSegment(10, 16, 'Ciao!!'),
        SpeechSegment(17, 24, 'Ancora.'),
      ],
      pause: const Duration(milliseconds: 10),
      started: (seg) async => checkpoints.add(seg.start),
    );
    player.castVoiceForSegment = (seg) =>
        seg.start == 10 ? _actor : null;
    player.castSpeakerForSegment = (seg) =>
        seg.start == 10 ? 'character' : null;

    await player.play();
    expect(engine.passages, ['Uno.', 'Due.', 'Ciao!!', 'Ancora.']);
    expect(engine.voiced, [
      'Narrator', 'Narrator', 'Actor', 'Narrator',
    ]);
    expect(checkpoints, [0, 5, 10, 17]);
    expect(player.currentIndex, 4);
    expect(player.activeSpeakerId, isNull);
    player.dispose();
  });

  test('Stop during turn breath cancels pending speech and checkpoint',
      () async {
    final engine = _FastCastSpeechEngine();
    final checkpoints = <int>[];
    final player = await _setUpPlayer(
      engine,
      segments: const [
        SpeechSegment(0, 4, 'Uno.'),
        SpeechSegment(5, 9, 'Due.'),
      ],
      pause: const Duration(seconds: 2),
      started: (seg) async => checkpoints.add(seg.start),
    );
    player.castVoiceForSegment = (seg) =>
        seg.start == 5 ? _actor : null;
    player.castSpeakerForSegment = (seg) =>
        seg.start == 5 ? 'actor' : null;
    final running = player.play();
    await _until(() => player.currentIndex == 1);
    await Future<void>.delayed(Duration.zero);
    expect(engine.passages, ['Uno.']);
    expect(checkpoints, [0]);

    await player.pause();
    await running.timeout(const Duration(milliseconds: 500));
    expect(engine.passages, ['Uno.'],
        reason: 'No stale character voice may speak after Stop');
    expect(checkpoints, [0],
        reason: 'Unheard character position cannot be committed');
    expect(player.currentIndex, 1);
    expect(player.isPlaying, isFalse);
    player.dispose();
  });

  test('two tagged speakers sharing one voice do not incur turn delay',
      () async {
    final engine = _FastCastSpeechEngine();
    final player = await _setUpPlayer(
      engine,
      segments: const [
        SpeechSegment(0, 4, 'Uno.'),
        SpeechSegment(5, 9, 'Due.'),
      ],
      pause: const Duration(seconds: 2),
    );
    player.castVoiceForSegment = (_) => _actor;
    player.castSpeakerForSegment = (seg) =>
        seg.start == 0 ? 'alice' : 'bob';
    await player.play().timeout(const Duration(milliseconds: 500));
    expect(engine.voiced, ['Actor', 'Actor']);
    player.dispose();
  });

  test('cloud provider never inserts system dialogue turn breath', () async {
    final engine = _FastCastSpeechEngine();
    final player = await _setUpPlayer(
      engine,
      provider: 'openai-speech',
      segments: const [
        SpeechSegment(0, 4, 'Uno.'),
        SpeechSegment(5, 9, 'Due.'),
      ],
      pause: const Duration(seconds: 2),
    );
    player.castVoiceForSegment = (seg) =>
        seg.start == 5 ? _actor : null;
    player.castSpeakerForSegment = (seg) =>
        seg.start == 5 ? 'actor' : null;
    await player.play().timeout(const Duration(milliseconds: 500));
    expect(engine.voiced, ['Narrator', 'Actor']);
    player.dispose();
  });

  test('skipped note does not erase a real narrator to actor turn',
      () async {
    final engine = _FastCastSpeechEngine();
    final player = await _setUpPlayer(
      engine,
      segments: const [
        SpeechSegment(0, 4, 'Uno.'),
        SpeechSegment(5, 10, 'Nota.'),
        SpeechSegment(11, 15, 'Due.'),
      ],
      pause: const Duration(milliseconds: 10),
    );
    player.shouldSkipSegment = (seg) => seg.start == 5;
    player.castVoiceForSegment = (seg) =>
        seg.start == 11 ? _actor : null;
    player.castSpeakerForSegment = (seg) =>
        seg.start == 11 ? 'actor' : null;
    await player.play();
    expect(engine.passages, ['Uno.', 'Due.']);
    expect(engine.voiced, ['Narrator', 'Actor']);
    player.dispose();
  });
}
