import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/narration_transition_diagnostics.dart';
import 'package:ereader/audio/offline_voice_diagnostics.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/pronunciation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  final spokenVoices = <String?>[];
  String? activeVoice;
  int voiceSelections = 0;
  Completer<void>? waiting;
  Completer<void>? stopGate;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [
        SpeechVoice(name: 'Sample', locale: 'en-US'),
        SpeechVoice(name: 'Character', locale: 'en-US'),
      ];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    voiceSelections++;
    activeVoice = voice.name;
  }

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    spoken.add(text);
    spokenVoices.add(activeVoice);
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

class MeasuredFakeSpeechEngine extends FakeSpeechEngine
    implements OfflineVoiceDiagnosticsProvider {
  final OfflineVoiceDiagnostics diagnostics = OfflineVoiceDiagnostics();
  @override
  OfflineVoiceStatistics get offlineVoiceStatistics => diagnostics.snapshot;

  @override
  Future<void> speak(String text, {required String language,
      required double rate, required double pitch}) {
    diagnostics.recordSynthesis(const Duration(milliseconds: 31),
        ahead: false, wholeProcessRssBytes: 100 * 1024 * 1024);
    diagnostics.recordHandoff(const Duration(milliseconds: 8));
    return super.speak(text, language: language, rate: rate, pitch: pitch);
  }
}

class VolumeFakeSpeechEngine extends FakeSpeechEngine
    implements SpeechVolumeEngine {
  final configured = <double>[];
  final volumeAtSpeak = <double>[];
  double currentVolume = 1.0;

  @override
  void configureVolume(double volume) {
    currentVolume = volume;
    configured.add(volume);
  }

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    volumeAtSpeak.add(currentVolume);
    return super.speak(text, language: language, rate: rate, pitch: pitch);
  }
}

void main() {
  test('bounded transition metrics keep chapter and ordinary gaps separate',
      () {
    final diag = NarrationTransitionDiagnostics();
    expect(diag.medianChapterGapMs, isNull);
    for (var i = 0; i < 40; i++) {
      diag.record(NarrationTransitionSample(
        isFirstUtterance: i == 0,
        isChapterTransition: i % 5 == 0,
        speechWallMs: 100 + i,
        interSegmentGapMs: i == 0 ? null : i,
        checkpointMs: i == 0 ? null : 1,
        neuralSynthesisMs: 20,
        decoderHandoffMs: 15,
      ));
    }
    expect(diag.completedUtterances, 32);
    expect(diag.observedGaps, 32);
    expect(diag.chapterTransitions, 6);
    expect(diag.medianChapterGapMs, isNotNull);
    expect(diag.medianRegularGapMs, isNotNull);
    expect(diag.medianNeuralSynthesisMs, 20);
    expect(diag.medianPostHandoffMs, isNotNull);
    expect(() => diag.recent.clear(), throwsUnsupportedError);
    final view = formatNarrationTransitionDiagnostics(diag);
    expect(view, contains('chapter transition median'));
    expect(view, contains('post-handoff audio/cleanup'));
    expect(view, isNot(contains('speech source')));
    expect(() => diag.record(const NarrationTransitionSample(
      isFirstUtterance: false, isChapterTransition: false,
      speechWallMs: -1)), throwsArgumentError);
  });

  test('reader measures real gap across completed checkpoint and chapter',
      () async {
    final engine = MeasuredFakeSpeechEngine();
    final checkpointStarted = Completer<void>();
    final allowCheckpoint = Completer<void>();
    final player = ReaderPlayer(
      engineProviderId: 'sherpa-vits',
      engine: engine,
      chapterStartIndices: const {1},
      segments: const [
        SpeechSegment(0, 5, 'first'),
        SpeechSegment(100, 106, 'second'),
      ],
      onSegmentStarted: (_) async {},
      onSegmentCompleted: (segment, next) async {
        if (segment.start == 0) {
          checkpointStarted.complete();
          await allowCheckpoint.future;
        }
      },
    );
    final reading = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['first']);
    engine.finish();
    await checkpointStarted.future;
    expect(engine.spoken, ['first'],
        reason: 'Next audio may not start before a durable checkpoint');
    allowCheckpoint.complete();
    for (var i = 0; i < 40 && engine.spoken.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.spoken, ['first', 'second']);
    engine.finish();
    await reading;

    final samples = player.narrationTimings.recent;
    expect(samples, hasLength(2));
    expect(samples.first.isFirstUtterance, isTrue);
    expect(samples.first.interSegmentGapMs, isNull);
    expect(samples.last.isChapterTransition, isTrue);
    expect(samples.last.interSegmentGapMs, greaterThanOrEqualTo(0));
    expect(samples.last.checkpointMs, greaterThanOrEqualTo(0));
    expect(samples.last.interSegmentGapMs!,
        greaterThanOrEqualTo(samples.last.checkpointMs!));
    expect(samples.last.neuralSynthesisMs, 31);
    expect(samples.last.decoderHandoffMs, 8);
    expect(samples.last.postHandoffMs,
        anyOf(isNull, greaterThanOrEqualTo(0)),
        reason: 'Cannot invent post-handoff time if clocks are inconsistent');
    expect(player.narrationTimings.chapterTransitions, 1);
    player.dispose();
  });

  test('cancelled speech is not counted as completed narration',
      () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 6, 'secret')],
      onSegmentStarted: (_) async {},
    );
    final playing = player.play();
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    await playing;
    expect(player.narrationTimings.completedUtterances, 0);
    expect(formatNarrationTransitionDiagnostics(player.narrationTimings),
        isNot(contains('secret')));
    player.dispose();
  });

  test('volume capability applies saved choice before native speech',
      () async {
    final engine = VolumeFakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 5, 'Hello')],
      onSegmentStarted: (_) async {},
    );
    expect(player.supportsVolume, isTrue);
    await player.applyPreferences(const SpeechPreferences(volume: 0.4));
    expect(engine.configured, [0.4]);
    expect(player.currentPreferences.volume, 0.4);

    final reading = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.volumeAtSpeak, [0.4]);
    player.setVolume(0.2);
    expect(engine.configured, [0.4, 0.2]);
    expect(player.currentPreferences.volume, 0.2);
    await player.restartAfterSettingsChange();
    await Future<void>.delayed(Duration.zero);
    expect(engine.volumeAtSpeak, [0.4, 0.2]);
    engine.finish();
    await reading;
    player.dispose();
  });

  test('unsupported engine exposes no volume and cannot change it',
      () async {
    final player = ReaderPlayer(
      engine: FakeSpeechEngine(),
      segments: const [],
      onSegmentStarted: (_) async {},
    );
    expect(player.supportsVolume, isFalse);
    await player.applyPreferences(const SpeechPreferences(volume: 0.55));
    expect(player.currentPreferences.volume, 0.55,
        reason: 'Unsupported engine preserves preferences without applying');
    expect(() => player.setVolume(0.3), throwsUnsupportedError);
    expect(player.currentPreferences.volume, 0.55);
    player.dispose();
  });

  test('native volume input rejects invalid values without updating engine',
      () async {
    final engine = VolumeFakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine, segments: const [], onSegmentStarted: (_) async {},
    );
    for (final value in [-0.1, 1.1, double.nan]) {
      expect(() => player.setVolume(value), throwsRangeError);
    }
    expect(engine.configured, isEmpty);
    expect(player.currentPreferences.volume, 1.0);
    player.dispose();
  });

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
  test('pause listeners never observe idle until native stop finishes',
      () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 5, 'Hello')],
      onSegmentStarted: (_) async {},
    );
    final idleEvents = <bool>[];
    player.addListener(() => idleEvents.add(player.isSettledIdle));
    final playing = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Hello']);

    engine.stopGate = Completer<void>();
    final pausing = player.pause();
    // This notification is synchronous; the native Stop is still gated.
    expect(idleEvents.last, isFalse);
    expect(player.isSettledIdle, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(idleEvents.where((idle) => idle), isEmpty);

    engine.stopGate!.complete();
    await pausing;
    await playing;
    expect(player.isSettledIdle, isTrue);
    expect(idleEvents.last, isTrue);
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


  test('custom names affect speech only, never source segment offsets', () async {
    final engine = FakeSpeechEngine();
    const original = SpeechSegment(42, 57, 'Aeryn incontrò.');
    const rules = [
      PronunciationRule(id: 'one', pattern: 'Aeryn',
          replacement: 'Erin'),
    ];
    final positions = <int>[];
    final player = ReaderPlayer(
      engine: engine,
      segments: [original],
      onSegmentStarted: (seg) async => positions.add(seg.start),
    );
    player.speechTextTransform = (input) =>
        const PronunciationTransformer().apply(
            input, rules, bookId: 'book');
    final run = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Erin incontrò.']);
    expect(original.text, 'Aeryn incontrò.');
    expect(positions, [42]);
    engine.finish();
    await run;
    player.dispose();
  });

  test('restores saved OS voice, language, pitch and rate', () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: [const SpeechSegment(0, 4, 'Text')],
      onSegmentStarted: (_) async {},
    );
    await player.loadVoices();
    await player.applyPreferences(const SpeechPreferences(
      language: 'en-US',
      rate: 0.7,
      pitch: 1.2,
      voiceName: 'Sample',
      voiceLocale: 'en-US',
    ));
    expect(player.currentPreferences.voiceName, 'Sample');
    expect(player.currentPreferences.rate, 0.7);
    expect(player.currentPreferences.pitch, 1.2);
    player.dispose();
  });

  test('rejects unavailable engines rather than charging implicitly',
      () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [],
      onSegmentStarted: (_) async {},
    );
    await expectLater(
      player.applyPreferences(const SpeechPreferences(
        providerId: 'cloud-openai',
      )),
      throwsUnsupportedError,
    );
    player.dispose();
  });


  test('manually tagged character voice switches back to narrator',
      () async {
    final engine = FakeSpeechEngine();
    final segments = [
      const SpeechSegment(0, 6, 'Hello!'),
      const SpeechSegment(7, 16, 'Narrator.'),
    ];
    final player = ReaderPlayer(
      engine: engine,
      segments: segments,
      onSegmentStarted: (_) async {},
    );
    await player.loadVoices();
    await player.applyPreferences(const SpeechPreferences(
      language: 'en-US',
      voiceName: 'Sample',
      voiceLocale: 'en-US',
    ));
    player.castVoiceForSegment = (segment) =>
        segment.start == 0
            ? const SpeechVoice(name: 'Character', locale: 'en-US')
            : null;
    player.castSpeakerForSegment = (segment) =>
        segment.start == 0 ? 'actor-1' : null;

    final run = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken.first, 'Hello!');
    expect(engine.spokenVoices.first, 'Character');
    expect(player.activeSpeakerId, 'actor-1');
    engine.finish();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spokenVoices, ['Character', 'Sample']);
    expect(engine.spoken.last, 'Narrator.');
    expect(player.activeSpeakerId, isNull);
    engine.finish();
    await run;
    expect(player.isPlaying, isFalse);
    player.dispose();
  });

  test('unsupported character voice falls back without extra narration',
      () async {
    final engine = FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: [const SpeechSegment(0, 5, 'Ciao!')],
      onSegmentStarted: (_) async {},
    );
    await player.loadVoices();
    player.castVoiceForSegment = (_) =>
        const SpeechVoice(name: 'Does not exist', locale: 'en-US');
    final run = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['Ciao!']);
    expect(engine.spokenVoices, ['Sample']);
    engine.finish();
    await run;
    player.dispose();
  });

  test('long cross-chunk quote retains one voice and restores narrator',
      () async {
    final engine = FakeSpeechEngine();
    final quotedText = '«' +
        List.filled(145, 'hello').join(' ') + '»';
    final source = 'Intro. ' + quotedText + ' Then the narrator.';
    final begin = source.indexOf('«');
    final end = source.indexOf('»') + 1;
    final original = splitQuotedSegmentsWithRegions(
        segmentSpeech(source, maxChars: 75));
    final voiceSpan = CastSpan(
      id: 'long-quote', bookId: 'book',
      start: begin, end: end,
      sourceDigest: CastSpan.digest(source.substring(begin, end)),
      speakerId: 'character-1',
      origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted,
      lockedByUser: true,
    );
    final attributed = prepareCastSpeech(
      source: source,
      base: [for (final part in original) part.segment],
      annotations: [voiceSpan],
      bookId: 'book',
      knownCharacterIds: {'character-1'},
      offsetFromAnchor: (_) => null,
    );
    final joined = coalesceQuotedSpeech(
      source: source,
      chunks: attributed.segments,
      quotedChunks: original,
      speakerByStart: attributed.speakerByStart,
    );
    final quoteChunks = joined.segments.where((chunk) =>
        chunk.start >= begin && chunk.end <= end).toList();
    expect(quoteChunks.length, greaterThan(1));
    expect(quoteChunks.every((chunk) =>
        joined.speakerByStart[chunk.start] == 'character-1'), isTrue);

    final player = ReaderPlayer(
      engine: engine, segments: joined.segments,
      onSegmentStarted: (_) async {},
    );
    await player.loadVoices();
    await player.applyPreferences(const SpeechPreferences(
      language: 'en-US', voiceName: 'Sample', voiceLocale: 'en-US',
    ));
    player.castVoiceForSegment = (segment) =>
        joined.speakerByStart[segment.start] == 'character-1'
            ? const SpeechVoice(name: 'Character', locale: 'en-US')
            : null;
    player.castSpeakerForSegment = (segment) =>
        joined.speakerByStart[segment.start];

    final run = player.play();
    for (var i = 0; i < joined.segments.length; i++) {
      await Future<void>.delayed(Duration.zero);
      expect(engine.spoken.length, i + 1);
      expect(engine.spoken.last, joined.segments[i].text);
      engine.finish();
    }
    await run;
    final voiceSequence = <String?>[];
    for (final voice in engine.spokenVoices) {
      if (voiceSequence.isEmpty || voiceSequence.last != voice) {
        voiceSequence.add(voice);
      }
    }
    expect(voiceSequence, ['Sample', 'Character', 'Sample']);
    // One initial preference plus only two actual transitions.
    expect(engine.voiceSelections, 3);
    expect(player.currentIndex, joined.segments.length);
    player.dispose();
  });


}
