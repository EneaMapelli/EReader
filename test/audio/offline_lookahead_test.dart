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
