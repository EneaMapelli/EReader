import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

const narrator = SpeechVoice(name: 'Narrator IT', locale: 'it-IT');
const englishActor = SpeechVoice(name: 'Actor EN', locale: 'en-US');
const wrongActor = SpeechVoice(name: 'Not installed', locale: 'en-US');

class _CastHandoffEngine
    implements SpeechEngine, AheadOfTimeSpeechEngine {
  final voicesUsed = <String?>[];
  final speechLanguages = <String>[];
  final spokenText = <String>[];
  final preparedLanguages = <String>[];
  final preparedVoices = <String?>[];
  final chosen = <String>[];
  String? selected;
  Completer<void>? actorChoiceGate;
  int choosing = 0;
  int peakConcurrentChoices = 0;

  @override
  Future<List<SpeechVoice>> listVoices() async =>
      const [narrator, englishActor];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    choosing++;
    if (choosing > peakConcurrentChoices) {
      peakConcurrentChoices = choosing;
    }
    chosen.add(voice.name);
    try {
      if (voice.key == englishActor.key && actorChoiceGate != null) {
        await actorChoiceGate!.future;
      }
      selected = voice.name;
    } finally {
      choosing--;
    }
  }

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    spokenText.add(text);
    speechLanguages.add(language);
    voicesUsed.add(selected);
  }

  @override
  Future<void> prepareSpeech(String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  }) async {
    preparedLanguages.add(language);
    preparedVoices.add(voice?.name);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _until(bool Function() check) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (check()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected native voice state did not become ready');
}

ReaderPlayer _player(_CastHandoffEngine engine, List<SpeechSegment> chunks, {
  String provider = 'system',
}) => ReaderPlayer(
  engine: engine,
  engineProviderId: provider,
  segments: chunks,
  onSegmentStarted: (_) async {},
);

Future<void> _selectItalianNarrator(
    ReaderPlayer player, {String provider = 'system'}) async {
  await player.loadVoices();
  await player.applyPreferences(SpeechPreferences(
    providerId: provider,
    language: 'it-IT',
    voiceName: narrator.name,
    voiceLocale: narrator.locale,
  ));
}

void main() {
  test('narrator Italian → actor English → narrator Italian restores locale',
      () async {
    final engine = _CastHandoffEngine();
    final player = _player(engine, const [
      SpeechSegment(0, 5, 'Ciao!'),
      SpeechSegment(6, 12, 'Hello!'),
      SpeechSegment(13, 20, 'Ancora.'),
    ]);
    await _selectItalianNarrator(player);
    player.castVoiceForSegment = (chunk) =>
        chunk.start == 6 ? englishActor : null;
    player.castSpeakerForSegment = (chunk) =>
        chunk.start == 6 ? 'actor-1' : null;

    await player.play();
    expect(engine.spokenText, ['Ciao!', 'Hello!', 'Ancora.']);
    expect(engine.voicesUsed, [
      'Narrator IT', 'Actor EN', 'Narrator IT',
    ]);
    expect(engine.speechLanguages, ['it-IT', 'en-US', 'it-IT']);
    expect(engine.chosen, ['Narrator IT', 'Actor EN', 'Narrator IT']);
    expect(engine.peakConcurrentChoices, 1);
    expect(player.currentPreferences.language, 'it-IT');
    expect(player.currentPreferences.voiceName, 'Narrator IT');
    expect(player.activeSpeakerId, isNull);
    player.dispose();
  });

  test('stale character voice uses installed narrator and book language',
      () async {
    final engine = _CastHandoffEngine();
    final player = _player(engine, const [
      SpeechSegment(0, 6, 'Ciao!!'),
    ]);
    await _selectItalianNarrator(player);
    player.castVoiceForSegment = (_) => wrongActor;
    await player.play();
    expect(engine.spokenText, ['Ciao!!']);
    expect(engine.voicesUsed, ['Narrator IT']);
    expect(engine.speechLanguages, ['it-IT']);
    expect(engine.chosen, ['Narrator IT']);
    player.dispose();
  });

  test('paid prefetch of next cast turn snapshots its language and voice',
      () async {
    final engine = _CastHandoffEngine();
    final player = _player(engine, const [
      SpeechSegment(0, 5, 'Ciao!'),
      SpeechSegment(6, 12, 'Hello!'),
    ], provider: 'openai-speech');
    await _selectItalianNarrator(player, provider: 'openai-speech');
    player.castVoiceForSegment = (chunk) =>
        chunk.start == 6 ? englishActor : null;
    // This is a fake provider; no network request or billing occurs.
    // Production paid prefetch remains OFF until user explicitly enables it.
    expect(player.prefetchNextCloudChunk, isFalse);
    player.setCloudPrefetch(true);
    await player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.preparedLanguages, ['en-US']);
    expect(engine.preparedVoices, ['Actor EN']);
    expect(engine.speechLanguages, ['it-IT', 'en-US']);
    player.dispose();
  });

  test('interrupted actor choice cannot overwrite subsequent narrator choice',
      () async {
    final engine = _CastHandoffEngine();
    final player = _player(engine, const [
      SpeechSegment(0, 5, 'Hello'),
      SpeechSegment(6, 13, 'Narrate'),
    ]);
    await _selectItalianNarrator(player);
    engine.actorChoiceGate = Completer<void>();
    player.castVoiceForSegment = (chunk) =>
        chunk.start == 0 ? englishActor : null;
    final abandoned = player.play();
    await _until(() => engine.chosen.contains('Actor EN'));
    final seek = player.seekTo(1);
    await seek;
    // The old engine chooseVoice is still pending: no new clip may speak
    // or asynchronously reorder a newer narrator selection behind it.
    expect(engine.spokenText, isEmpty);
    engine.actorChoiceGate!.complete();
    await abandoned;
    await _until(() => engine.spokenText.isNotEmpty);
    expect(engine.spokenText, ['Narrate']);
    expect(engine.voicesUsed, ['Narrator IT']);
    expect(engine.speechLanguages, ['it-IT']);
    expect(engine.selected, 'Narrator IT');
    expect(engine.peakConcurrentChoices, 1);
    expect(engine.chosen, [
      'Narrator IT', 'Actor EN', 'Narrator IT',
    ]);
    expect(player.currentIndex, 2);
    player.dispose();
  });
}
