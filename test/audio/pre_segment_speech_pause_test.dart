import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
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

  test('a long, accepted dialogue only changes native voice at its edges',
      () async {
    final quote = '«' +
        List.filled(65, 'Una battuta abbastanza lunga').join(' ') +
        '.»';
    final source = 'Prima la voce narrante. ' + quote +
        ' Di nuovo il narratore.';
    final from = source.indexOf('«');
    final to = from + quote.length;
    final quotes = splitQuotedSegmentsWithRegions(
        segmentSpeech(source, maxChars: 65));
    final assigned = prepareCastSpeech(
      source: source,
      base: [for (final q in quotes) q.segment],
      annotations: [
        CastSpan(
          id: 'confirmed-long-turn',
          bookId: 'book',
          start: from,
          end: to,
          sourceDigest: CastSpan.digest(source.substring(from, to)),
          speakerId: 'actor',
          origin: CastSpanOrigin.user,
          status: CastSpanStatus.accepted,
          lockedByUser: true,
        ),
      ],
      bookId: 'book',
      knownCharacterIds: {'actor'},
      offsetFromAnchor: (_) => null,
    );
    final smooth = coalesceQuotedSpeech(
      source: source,
      chunks: assigned.segments,
      quotedChunks: quotes,
      speakerByStart: assigned.speakerByStart,
      maxChars: 220,
    );
    final engine = _GatedSystemEngine();
    final completed = <int>[];
    final player = ReaderPlayer(
      engine: engine,
      engineProviderId: 'system',
      segments: smooth.segments,
      dialogueTurnPause: const Duration(milliseconds: 110),
      onSegmentStarted: (segment) async {
        engine.events.add('checkpoint:${segment.start}');
      },
      onSegmentCompleted: (segment, _) async {
        completed.add(segment.start);
      },
    );
    await player.loadVoices();
    await player.applyPreferences(const SpeechPreferences(
      voiceName: 'Narrator', voiceLocale: 'it-IT',
    ));
    engine.events.clear();
    player.castVoiceForSegment = (segment) =>
        smooth.speakerByStart[segment.start] == 'actor'
            ? _actor : null;
    player.castSpeakerForSegment = (segment) =>
        smooth.speakerByStart[segment.start];
    await player.play();

    final expectedStarts = [
      for (final segment in smooth.segments) segment.start,
    ];
    final checkpoints = [
      for (final event in engine.events)
        if (event.startsWith('checkpoint:'))
          int.parse(event.substring('checkpoint:'.length)),
    ];
    expect(smooth.segments.length, greaterThan(5));
    expect(smooth.segments.every((part) =>
        part.text == source.substring(part.start, part.end)), isTrue);
    expect(smooth.segments.every((part) => part.text.length <= 220), isTrue);
    expect(checkpoints, expectedStarts,
        reason: 'Every spoken source span gets exactly one start highlight');
    expect(completed, expectedStarts,
        reason: 'A normally completed span must have one recovery completion');
    expect(engine.requestedBreaths
        .where((pause) => pause > Duration.zero), [
      const Duration(milliseconds: 110),
      const Duration(milliseconds: 110),
    ]);
    expect(engine.events.where((event) => event == 'choose:Actor').length, 1);
    expect(engine.events.where((event) => event == 'choose:Narrator').length, 1);
    expect(player.activeSpeakerId, isNull);
    expect(player.currentIndex, smooth.segments.length);
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
