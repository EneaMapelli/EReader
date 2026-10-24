import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class _ManualTimer implements Timer {
  _ManualTimer(this.fireCallback);

  final void Function() fireCallback;
  bool _active = true;
  int _ticks = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _ticks++;
    fireCallback();
  }
}

class _BlockingSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? pending;
  Completer<void>? stopGate;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    spoken.add(text);
    pending = Completer<void>();
    return pending!.future;
  }

  void finish() {
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }

  @override
  Future<void> stop() async {
    if (stopGate != null) await stopGate!.future;
    finish();
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  test('sleep expiry invalidates current session before native stop completes',
      () async {
    final engine = _BlockingSpeechEngine();
    final timers = <_ManualTimer>[];
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 5, 'First'),
        SpeechSegment(6, 12, 'Second'),
      ],
      onSegmentStarted: (_) async {},
      timerScheduler: (duration, callback) {
        expect(duration, const Duration(minutes: 15));
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    final run = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);

    player.setSleepTimer(const Duration(minutes: 15));
    expect(player.sleepTimerEndsAt, isNotNull);
    engine.stopGate = Completer<void>();
    timers.single.fire();
    expect(player.isPlaying, isFalse);
    expect(player.sleepTimerEndsAt, isNull);
    expect(player.currentIndex, 0);
    expect(engine.spoken, ['First'],
        reason: 'The next segment must not begin after expiry');

    engine.stopGate!.complete();
    await run;
    expect(engine.spoken, ['First']);
    expect(player.lastError, isNull);
    player.dispose();
  });

  test('rearming cancels obsolete deadline; off cancels latest', () {
    final timers = <_ManualTimer>[];
    final player = ReaderPlayer(
      engine: _BlockingSpeechEngine(),
      segments: const [],
      onSegmentStarted: (_) async {},
      timerScheduler: (_, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    expect(() => player.setSleepTimer(Duration.zero), throwsArgumentError);
    player.setSleepTimer(const Duration(minutes: 10));
    final first = timers.last;
    player.setSleepTimer(const Duration(minutes: 30));
    final second = timers.last;
    expect(first.isActive, isFalse);
    expect(second.isActive, isTrue);
    first.fire();
    expect(player.sleepTimerEndsAt, isNotNull);
    player.cancelSleepTimer();
    expect(second.isActive, isFalse);
    second.fire();
    expect(player.sleepTimerEndsAt, isNull);
    player.dispose();
  });

  test('manual pause keeps wall-clock timer; expiry never resumes audio',
      () async {
    final engine = _BlockingSpeechEngine();
    late _ManualTimer timer;
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 5, 'First')],
      onSegmentStarted: (_) async {},
      timerScheduler: (_, callback) => timer = _ManualTimer(callback),
    );
    final run = player.play();
    await Future<void>.delayed(Duration.zero);
    player.setSleepTimer(const Duration(minutes: 15));
    await player.pause();
    await run;
    expect(timer.isActive, isTrue);
    expect(player.sleepTimerEndsAt, isNotNull);
    timer.fire();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, ['First']);
    expect(player.sleepTimerEndsAt, isNull);
    player.dispose();
  });

  test('natural reading completion and dispose cancel the deadline', () async {
    final engine = _BlockingSpeechEngine();
    final timers = <_ManualTimer>[];
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 5, 'First')],
      onSegmentStarted: (_) async {},
      timerScheduler: (_, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    player.setSleepTimer(const Duration(minutes: 30));
    final run = player.play();
    await Future<void>.delayed(Duration.zero);
    engine.finish();
    await run;
    expect(timers.single.isActive, isFalse);
    expect(player.sleepTimerEndsAt, isNull);
    player.setSleepTimer(const Duration(minutes: 10));
    expect(timers.last.isActive, isTrue);
    player.dispose();
    expect(timers.last.isActive, isFalse);
  });
}
