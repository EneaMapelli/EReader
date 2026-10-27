import 'dart:async';

import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledDecoder implements WaveDecoder {
  Completer<void>? loadGate;
  Completer<void>? playbackGate;
  final events = <String>[];
  bool loading = false;
  bool disposed = false;
  int playCalls = 0;
  int stopCalls = 0;
  bool failLoad = false;
  bool failStop = false;

  @override
  Future<void> load(String file) async {
    if (loading || disposed) throw StateError('Invalid concurrent load');
    loading = true;
    events.add('load:start:$file');
    try {
      final gate = loadGate;
      if (gate != null) await gate.future;
      if (failLoad) throw StateError('Native load failed');
      events.add('load:done:$file');
    } finally {
      loading = false;
    }
  }

  @override
  Future<void> play() async {
    if (disposed || loading) throw StateError('Playing invalid decoder');
    playCalls++;
    events.add('play');
    final gate = playbackGate;
    if (gate != null) await gate.future;
    events.add('play:done');
  }

  @override
  Future<void> stop() async {
    if (loading || disposed) throw StateError('Stop raced native load');
    stopCalls++;
    events.add('stop');
    if (failStop) throw StateError('Native Stop did not confirm');
    final gate = playbackGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> dispose() async {
    if (loading || disposed) throw StateError('Dispose raced native load');
    disposed = true;
    events.add('dispose');
    final gate = playbackGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

Future<void> _waitFor(bool Function() reached) async {
  for (var i = 0; i < 100; i++) {
    if (reached()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected native operation was not reached');
}

void main() {
  test('Stop during slow setFilePath waits for it, then blocks stale Play',
      () async {
    final decoder = _ControlledDecoder()..loadGate = Completer<void>();
    final output = JustAudioWaveOutput(decoder: decoder);
    final playing = output.play('first.wav');
    await _waitFor(() => decoder.loading);
    var stopped = false;
    final stop = output.stop().then((_) { stopped = true; });
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(decoder.stopCalls, 0,
        reason: 'Native Stop must never race setFilePath on this decoder');
    decoder.loadGate!.complete();
    await Future.wait([playing, stop]);
    expect(stopped, isTrue);
    expect(decoder.playCalls, 0);
    expect(decoder.stopCalls, 1);
    expect(decoder.events, [
      'load:start:first.wav', 'load:done:first.wav', 'stop',
    ]);
    await output.dispose();
  });

  test('Dispose during pending load waits and cannot start late audio',
      () async {
    final decoder = _ControlledDecoder()..loadGate = Completer<void>();
    final output = JustAudioWaveOutput(decoder: decoder);
    final playing = output.play('private.wav');
    await _waitFor(() => decoder.loading);
    final disposing = output.dispose();
    expect(identical(disposing, output.dispose()), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(decoder.disposed, isFalse);
    decoder.loadGate!.complete();
    await Future.wait([playing, disposing]);
    expect(decoder.disposed, isTrue);
    expect(decoder.playCalls, 0);
    expect(decoder.events, [
      'load:start:private.wav', 'load:done:private.wav', 'dispose',
    ]);
    await expectLater(output.play('never.wav'), throwsStateError);
  });

  test('natural completion performs native Stop before WAV cleanup', () async {
    final decoder = _ControlledDecoder();
    final output = JustAudioWaveOutput(decoder: decoder);
    await output.play('book.wav');
    expect(decoder.events, [
      'load:start:book.wav', 'load:done:book.wav',
      'play', 'play:done', 'stop',
    ]);
    expect(decoder.stopCalls, 1);
    await output.dispose();
  });

  test('Stop during playback interrupts once; stale finalizer cannot stop'
      ' the next utterance', () async {
    final decoder = _ControlledDecoder()
        ..playbackGate = Completer<void>();
    final output = JustAudioWaveOutput(decoder: decoder);
    final first = output.play('one.wav');
    await _waitFor(() => decoder.playCalls == 1);
    await output.stop();
    await first;
    expect(decoder.stopCalls, 1,
        reason: 'Old playback finalizer cannot duplicate Stop');
    decoder.playbackGate = null;
    await output.play('two.wav');
    expect(decoder.playCalls, 2);
    expect(decoder.stopCalls, 2,
        reason: 'Natural completion of the new clip owns exactly one Stop');
    await output.dispose();
  });

  test('failed native Stop remains required before decoder reuse', () async {
    final decoder = _ControlledDecoder()
      ..failLoad = true
      ..failStop = true;
    final output = JustAudioWaveOutput(decoder: decoder);
    await expectLater(output.play('partial.wav'), throwsStateError);
    expect(decoder.stopCalls, 1);
    decoder.failLoad = false;
    // The old native file might still be open. Another Play must try
    // physical Stop FIRST, and fail closed if that Stop still fails.
    await expectLater(output.play('next.wav'), throwsStateError);
    expect(decoder.stopCalls, 2);
    expect(decoder.events.contains('load:start:next.wav'), isFalse);
    decoder.failStop = false;
    await output.stop();
    expect(decoder.stopCalls, 3);
    await output.play('safe.wav');
    expect(decoder.playCalls, 1);
    expect(decoder.stopCalls, 4);
    await output.dispose();
  });

  test('failed decoder load always performs native Stop before surfacing',
      () async {
    final decoder = _ControlledDecoder()..failLoad = true;
    final output = JustAudioWaveOutput(decoder: decoder);
    await expectLater(output.play('broken.wav'), throwsStateError);
    expect(decoder.stopCalls, 1);
    expect(decoder.events, [
      'load:start:broken.wav', 'stop',
    ]);
    decoder.failLoad = false;
    await output.play('healthy.wav');
    expect(decoder.playCalls, 1);
    expect(decoder.stopCalls, 2);
    await output.dispose();
  });
}
