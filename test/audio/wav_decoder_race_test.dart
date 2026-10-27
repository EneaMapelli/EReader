import 'dart:async';

import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledDecoder implements WaveDecoder {
  Completer<void>? loadGate;
  Completer<void>? playbackGate;
  Completer<void>? stopGate;
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
    final pendingStop = stopGate;
    if (pendingStop != null) await pendingStop.future;
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
  test('discardNext stops only the idle decoder before WAV cleanup',
      () async {
    final first = _ControlledDecoder()..playbackGate = Completer<void>();
    final second = _ControlledDecoder()..stopGate = Completer<void>();
    var count = 0;
    final output = DualJustAudioWaveOutput(
        decoderFactory: () => count++ == 0 ? first : second);
    final ongoing = output.play('current.wav');
    await _waitFor(() => first.playCalls == 1);
    await output.prepareNext('obsolete.wav');
    expect(second.stopCalls, 0);
    var discarded = false;
    final discard = output.discardNext().then((_) => discarded = true);
    await _waitFor(() => second.stopCalls == 1);
    await Future<void>.delayed(Duration.zero);
    expect(discarded, isFalse,
        reason: 'Private WAV deletion must wait for native standby Stop');
    expect(first.stopCalls, 0,
        reason: 'Discarding lookahead must not interrupt audible playback');
    second.stopGate!.complete();
    await discard;
    expect(discarded, isTrue);
    first.playbackGate!.complete();
    await ongoing;
    await output.play('actual.wav');
    expect(second.playCalls, 0);
    await output.dispose();
  });

  test('second decoder preloads during playback and reuses setFilePath',
      () async {
    final first = _ControlledDecoder()..playbackGate = Completer<void>();
    final second = _ControlledDecoder();
    var created = 0;
    final output = DualJustAudioWaveOutput(
      decoderFactory: () => created++ == 0 ? first : second,
    );
    final playing = output.play('first.wav');
    await _waitFor(() => first.playCalls == 1);
    await output.prepareNext('second.wav');
    expect(first.playCalls, 1);
    expect(second.events, ['load:start:second.wav', 'load:done:second.wav']);
    expect(second.playCalls, 0,
        reason: 'Warming the next decoder must never play it');
    first.playbackGate!.complete();
    await playing;
    await output.play('second.wav');
    expect(second.playCalls, 1);
    expect(second.events
        .where((event) => event.startsWith('load:start:')).length, 1,
        reason: 'Playback must reuse its preloaded native source');
    expect(first.stopCalls, 1);
    await output.dispose();
    expect(first.disposed, isTrue);
    expect(second.disposed, isTrue);
    expect(created, 2);
  });

  test('obsolete speculative load never blocks correct audible clip',
      () async {
    final first = _ControlledDecoder()..playbackGate = Completer<void>();
    final second = _ControlledDecoder()..loadGate = Completer<void>();
    var created = 0;
    final output = DualJustAudioWaveOutput(
        decoderFactory: () => created++ == 0 ? first : second);
    final ongoing = output.play('one.wav');
    await _waitFor(() => first.playCalls == 1);
    final speculative = output.prepareNext('predicted.wav');
    await _waitFor(() => second.loading);
    first.playbackGate!.complete();
    await ongoing;
    // The correct WAV loads on the now-idle first decoder, without
    // waiting for the other physical decoder's pending setFilePath.
    final actual = output.play('actual.wav');
    await _waitFor(() => first.playCalls == 2);
    await actual;
    expect(second.playCalls, 0);
    expect(first.events, contains('load:start:actual.wav'));
    second.loadGate!.complete();
    await speculative;
    await output.stop();
    await output.dispose();
    expect(second.stopCalls, 1,
        reason: 'Wrong speculative WAV releases its decoder handle');
  });

  test('Stop waits for both decoder loads before WAV may be deleted',
      () async {
    final first = _ControlledDecoder()..playbackGate = Completer<void>();
    final second = _ControlledDecoder()..loadGate = Completer<void>();
    var created = 0;
    final output = DualJustAudioWaveOutput(
        decoderFactory: () => created++ == 0 ? first : second);
    final playing = output.play('first.wav');
    await _waitFor(() => first.playCalls == 1);
    final speculative = output.prepareNext('next.wav');
    await _waitFor(() => second.loading);
    var stopped = false;
    final stopping = output.stop().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse,
        reason: 'Private WAV remains owned until standby decoder stops');
    expect(second.stopCalls, 0,
        reason: 'Native Stop must wait until setFilePath has settled');
    second.loadGate!.complete();
    await speculative;
    await Future.wait([playing, stopping]);
    expect(stopped, isTrue);
    expect(first.stopCalls, 1);
    expect(second.stopCalls, 1);
    await output.dispose();
  });

  test('Stop during pending warm load prevents stale decoder playback',
      () async {
    final first = _ControlledDecoder()..playbackGate = Completer<void>();
    final second = _ControlledDecoder()..loadGate = Completer<void>();
    var created = 0;
    final output = DualJustAudioWaveOutput(
        decoderFactory: () => created++ == 0 ? first : second);
    final playing = output.play('first.wav');
    await _waitFor(() => first.playCalls == 1);
    final speculative = output.prepareNext('next.wav');
    await _waitFor(() => second.loading);
    final stopped = output.stop();
    second.loadGate!.complete();
    await Future.wait([playing, speculative, stopped]);
    await output.play('new.wav');
    expect(first.playCalls, 2);
    expect(second.playCalls, 0);
    await output.dispose();
  });

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

  test('cancelled native load cannot finish before its Stop settles',
      () async {
    final decoder = _ControlledDecoder()
      ..loadGate = Completer<void>()
      ..stopGate = Completer<void>();
    final output = JustAudioWaveOutput(decoder: decoder);
    final play = output.play('sensitive.wav');
    await _waitFor(() => decoder.loading);
    var playSettled = false;
    final observedPlay = play.then((_) { playSettled = true; });
    final stopping = output.stop();
    decoder.loadGate!.complete();
    await _waitFor(() => decoder.stopCalls == 1);
    await Future<void>.delayed(Duration.zero);
    expect(playSettled, isFalse,
        reason: 'Engine must not delete WAV before physical Stop settles');
    decoder.stopGate!.complete();
    await Future.wait([observedPlay, stopping]);
    expect(playSettled, isTrue);
    await output.dispose();
  });

  test('cancelled ongoing playback waits for native Stop confirmation',
      () async {
    final decoder = _ControlledDecoder()
      ..playbackGate = Completer<void>()
      ..stopGate = Completer<void>();
    final output = JustAudioWaveOutput(decoder: decoder);
    final playing = output.play('audible.wav');
    await _waitFor(() => decoder.playCalls == 1);
    var playSettled = false;
    final observed = playing.then((_) { playSettled = true; });
    final stopping = output.stop();
    await _waitFor(() => decoder.stopCalls == 1);
    await Future<void>.delayed(Duration.zero);
    expect(playSettled, isFalse,
        reason: 'Native playback future might resolve before Stop returns');
    decoder.stopGate!.complete();
    await Future.wait([observed, stopping]);
    expect(playSettled, isTrue);
    await output.dispose();
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
