import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrator = SpeechVoice(name: 'Narrator', locale: 'it-IT');
const _actor = SpeechVoice(name: 'Actor', locale: 'it-IT');

/// Injected system-engine contract without a native TTS dependency.
class _GatedSystemEngine implements SpeechEngine, PreSegmentSpeechPause {
  final events = <String>[];
  final requestedBreaths = <Duration>[];
  final spoken = <String>[];
  Completer<void>? pendingGap;
  Completer<void>? pendingVoice;
  bool blockNextGap = false;
  bool blockActorChoice = false;

  @override
  Future<List<SpeechVoice>> listVoices() async =>
      const [_narrator, _actor];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    events.add('choose:${voice.name}');
    if (voice.name == _actor.name && blockActorChoice) {
      pendingVoice = Completer<void>();
      await pendingVoice!.future;
      pendingVoice = null;
    }
  }

  @override
  Future<void> waitBeforeSegment({
    required Duration voiceTurnPause,
  }) async {
    events.add('breath:${voiceTurnPause.inMilliseconds}');
    requestedBreaths.add(voiceTurnPause);
    if (voiceTurnPause > Duration.zero && blockNextGap) {
      pendingGap = Completer<void>();
      await pendingGap!.future;
      pendingGap = null;
    }
  }

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    events.add('speak:$text');
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    final gap = pendingGap;
    if (gap != null && !gap.isCompleted) gap.complete();
    final voice = pendingVoice;
    if (voice != null && !voice.isCompleted) voice.complete();
  }

  @override
  Future<void> dispose() => stop();
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected the in-flight native setup phase');
}

Future<ReaderPlayer> _createPlayer(
  _GatedSystemEngine engine, {
  List<SpeechSegment> segments = const [
    SpeechSegment(0, 4, 'Uno.'),
    SpeechSegment(5, 9, 'Due.'),
    SpeechSegment(10, 14, 'Tre.'),
  ],
}) async {
  final player = ReaderPlayer(
    engine: engine,
    engineProviderId: 'system',
    segments: segments,
    dialogueTurnPause: const Duration(milliseconds: 110),
    onSegmentStarted: (segment) async =>
        engine.events.add('checkpoint:${segment.start}'),
  );
  await player.loadVoices();
  await player.applyPreferences(const SpeechPreferences(
    voiceName: 'Narrator', voiceLocale: 'it-IT',
  ));
  engine.events.clear();
  player.castSpeakerForSegment = (segment) =>
      segment.start == 5 ? 'actor' : null;
  player.castVoiceForSegment = (segment) =>
      segment.start == 5 ? _actor : null;
  return player;
}

void main() {
  test('native voice and merged inter-segment gap finish before checkpoint',
      () async {
    final engine = _GatedSystemEngine();
    final player = await _createPlayer(engine);
    await player.play();

    expect(engine.requestedBreaths, [
      Duration.zero,
      const Duration(milliseconds: 110),
      const Duration(milliseconds: 110),
    ]);
    expect(engine.events, [
      'breath:0',
      'checkpoint:0',
      'speak:Uno.',
      'breath:110',
      'choose:Actor',
      'checkpoint:5',
      'speak:Due.',
      'breath:110',
      'choose:Narrator',
      'checkpoint:10',
      'speak:Tre.',
    ]);
    expect(player.currentIndex, 3);
    player.dispose();
  });

  test('Stop in pending punctuation/voice pause cannot checkpoint unheard text',
      () async {
    final engine = _GatedSystemEngine();
    engine.blockNextGap = true;
    final player = await _createPlayer(engine);
    final run = player.play();
    await _until(() => engine.pendingGap != null);
    expect(engine.spoken, ['Uno.']);
    expect(engine.events.where((event) => event == 'checkpoint:5'),
        isEmpty);

    await player.pause();
    await run.timeout(const Duration(milliseconds: 500));
    expect(engine.spoken, ['Uno.']);
    expect(player.currentIndex, 1);
    expect(engine.events.where((event) => event == 'checkpoint:5'),
        isEmpty);
    player.dispose();
  });

  test('Stop during delayed native voice selection cannot advance highlight',
      () async {
    final engine = _GatedSystemEngine();
    final player = await _createPlayer(engine);
    engine.blockActorChoice = true;
    final run = player.play();
    await _until(() => engine.pendingVoice != null);
    expect(engine.spoken, ['Uno.']);
    expect(engine.events, contains('choose:Actor'));
    expect(engine.events.where((event) => event == 'checkpoint:5'),
        isEmpty);

    await player.pause();
    await run.timeout(const Duration(milliseconds: 500));
    expect(engine.spoken, ['Uno.']);
    expect(engine.events.where((event) => event == 'checkpoint:5'),
        isEmpty);
    expect(player.currentIndex, 1);
    player.dispose();
  });

  test('skipped note never emits a source checkpoint or voice request',
      () async {
    final engine = _GatedSystemEngine();
    final player = await _createPlayer(engine);
    player.shouldSkipSegment = (segment) => segment.start == 5;
    await player.play();
    expect(engine.requestedBreaths, [
      Duration.zero, Duration.zero,
    ]);
    expect(engine.spoken, ['Uno.', 'Tre.']);
    expect(engine.events.where((event) => event == 'checkpoint:5'),
        isEmpty);
    expect(engine.events.where((event) => event == 'choose:Actor'),
        isEmpty);
    player.dispose();
  });

  test('turn labels sharing narrator voice never schedule artificial delay',
      () async {
    final engine = _GatedSystemEngine();
    final player = await _createPlayer(engine);
    player.castVoiceForSegment = (_) => _narrator;
    await player.play();
    expect(engine.requestedBreaths, [
      Duration.zero, Duration.zero, Duration.zero,
    ]);
    expect(engine.spoken, ['Uno.', 'Due.', 'Tre.']);
    player.dispose();
  });
}
