import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineSpy implements SpeechEngine, OfflineAheadSpeechEngine {
  final spoken = <String>[];
  final prepared = <String>[];
  Completer<void>? current;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [
    SpeechVoice(name: 'piper-local', locale: 'it-IT'),
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
    current = Completer<void>();
    return current!.future;
  }

  @override
  Future<void> prepareOfflineSpeech(String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  }) async {
    prepared.add(text);
  }

  @override
  Future<void> stop() async {
    final active = current;
    if (active != null && !active.isCompleted) active.complete();
  }

  @override
  Future<void> dispose() => stop();

  void finish() {
    final active = current;
    if (active != null && !active.isCompleted) active.complete();
  }
}

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Offline playback state was not reached');
}

void main() {
  test('offline lookahead prepares only the next audible non-note chunk',
      () async {
    final engine = _OfflineSpy();
    final player = ReaderPlayer(
      engine: engine,
      engineProviderId: 'sherpa-vits',
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 10, '[note]'),
        SpeechSegment(11, 16, 'Three'),
      ],
      onSegmentStarted: (_) async {},
    );
    player.shouldSkipSegment = (segment) => segment.text == '[note]';
    await player.loadVoices();
    final reading = player.play();
    await _until(() => engine.spoken.isNotEmpty &&
        engine.prepared.isNotEmpty);
    expect(engine.prepared, ['Three']);
    expect(engine.spoken, ['One']);
    engine.finish();
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Three']);
    expect(engine.prepared, ['Three']);
    engine.finish();
    await reading;
    player.dispose();
  });

  test('failed next-chunk pronunciation preview cannot interrupt audio',
      () async {
    final engine = _OfflineSpy();
    final started = <int>[];
    final completed = <int>[];
    final player = ReaderPlayer(
      engine: engine,
      engineProviderId: 'sherpa-vits',
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
      ],
      onSegmentStarted: (segment) async => started.add(segment.start),
      onSegmentCompleted: (segment, _) async =>
          completed.add(segment.start),
    );
    var nextCalls = 0;
    player.speechTextTransform = (text) {
      if (text == 'Two' && nextCalls++ == 0) {
        throw StateError('Speculative pronunciation preview failed');
      }
      return text;
    };

    final reading = player.play();
    await _until(() => engine.spoken.length == 1);
    expect(player.isPlaying, isTrue,
        reason: 'Preview failure must not abandon active native audio');
    expect(engine.spoken, ['One']);
    expect(engine.prepared, isEmpty);
    expect(started, [0]);
    engine.finish();
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Two']);
    expect(started, [0, 4]);
    expect(completed, [0]);
    engine.finish();
    await reading;
    expect(completed, [0, 4]);
    expect(player.currentIndex, 2);
    expect(player.lastError, isNull);
    player.dispose();
  });

  test('failed next-chunk cast preview does not alter speaker checkpoint',
      () async {
    final engine = _OfflineSpy();
    final positions = <int>[];
    final player = ReaderPlayer(
      engine: engine,
      engineProviderId: 'sherpa-vits',
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
      ],
      onSegmentStarted: (segment) async => positions.add(segment.start),
    );
    var nextCalls = 0;
    player.castVoiceForSegment = (segment) {
      if (segment.start == 4 && nextCalls++ == 0) {
        throw StateError('Future voice preview unavailable');
      }
      return null;
    };
    await player.loadVoices();

    final reading = player.play();
    await _until(() => engine.spoken.length == 1);
    expect(player.isPlaying, isTrue);
    expect(positions, [0]);
    engine.finish();
    await _until(() => engine.spoken.length == 2);
    expect(positions, [0, 4]);
    expect(engine.spoken, ['One', 'Two']);
    engine.finish();
    await reading;
    expect(player.currentIndex, 2);
    expect(player.lastError, isNull);
    player.dispose();
  });

  test('failed speculative note filtering cannot abandon the current clip',
      () async {
    final engine = _OfflineSpy();
    final player = ReaderPlayer(
      engine: engine,
      engineProviderId: 'sherpa-vits',
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
      ],
      onSegmentStarted: (_) async {},
    );
    var futureChecks = 0;
    player.shouldSkipSegment = (segment) {
      if (segment.start == 4 && futureChecks++ == 0) {
        throw StateError('Note preview failed');
      }
      return false;
    };

    final reading = player.play();
    await _until(() => engine.spoken.length == 1);
    expect(player.isPlaying, isTrue);
    engine.finish();
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Two']);
    engine.finish();
    await reading;
    expect(player.lastError, isNull);
    player.dispose();
  });

  test('offline lookahead may be disabled without affecting speech',
      () async {
    final engine = _OfflineSpy();
    final player = ReaderPlayer(
      engine: engine,
      engineProviderId: 'sherpa-vits',
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
      ],
      onSegmentStarted: (_) async {},
    );
    player.setOfflineWarmup(false);
    final reading = player.play();
    await _until(() => engine.spoken.length == 1);
    expect(engine.prepared, isEmpty);
    engine.finish();
    await _until(() => engine.spoken.length == 2);
    expect(engine.prepared, isEmpty);
    engine.finish();
    await reading;
    player.dispose();
  });
}
