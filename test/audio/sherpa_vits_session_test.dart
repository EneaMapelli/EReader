import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:ereader/audio/sherpa_vits_session.dart';
import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:ereader/audio/sherpa_vits_worker.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../support/windows_temp_cleanup.dart';

void _fakeReusableWorker((SendPort, VitsSessionModel) init) async {
  final incoming = ReceivePort();
  init.$1.send(incoming.sendPort);
  var count = 0;
  await for (final message in incoming) {
    final request = message as List;
    count++;
    await File(request[2] as String)
        .writeAsString('instance=1;request=$count');
    init.$1.send([0, request[0]]);
  }
}

/// Emulates a native worker that reports its model-init duration. Only
/// measurements and a tiny test WAV string cross the isolate boundary.
void _timedReusableWorker((SendPort, VitsSessionModel) init) async {
  final incoming = ReceivePort();
  init.$1.send([incoming.sendPort, 23]);
  var count = 0;
  await for (final message in incoming) {
    final request = message as List;
    count++;
    await File(request[2] as String).writeAsString('timed-request=$count');
    init.$1.send([0, request[0], 7]);
  }
}

void _blockedReusableWorker((SendPort, VitsSessionModel) init) async {
  final incoming = ReceivePort();
  init.$1.send(incoming.sendPort);
  await for (final _ in incoming) {
    // Simulates a native call that never answers, but unlike sleep loops
    // leaves the isolate's event loop responsive to immediate kill.
    await Completer<void>().future;
  }
}

/// An ONNX isolate that never sends readiness, for deterministic startup
/// timeout without waiting 60 real seconds.
void _neverReadyWorker((SendPort, VitsSessionModel) init) {
  ReceivePort();
}

/// A ready synthetic ONNX model that intentionally never completes WAV work.
void _neverCompletesWorker((SendPort, VitsSessionModel) init) async {
  final commands = ReceivePort();
  init.$1.send(commands.sendPort);
  await for (final _ in commands) {
    // Keep receiving but intentionally never reply.
  }
}

class _ManualVitsTimer implements Timer {
  _ManualVitsTimer(this.delay, this.action);
  final Duration delay;
  final void Function() action;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    action();
  }
}

class _StringWaveOutput implements OfflineWaveOutput {
  final played = <String>[];
  @override
  Future<void> play(String path) async {
    played.add(await File(path).readAsString());
  }
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  const model = VitsSessionModel(
    modelPath: 'mock.onnx', tokensPath: 'tokens.txt', dataDir: '',
  );
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-vits-session-');
  });
  tearDown(() async {
    await deleteOwnedTestTemp(root);
  });

  test('two sequential WAVs use same model worker and numbered requests',
      () async {
    final session = VitsPersistentSession.withEntrypoint(
        model, _fakeReusableWorker);
    final one = p.join(root.path, 'one.wav');
    final two = p.join(root.path, 'two.wav');
    await session.synthesize(text: 'one', wavPath: one, speed: 1.0);
    await session.synthesize(text: 'two', wavPath: two, speed: 1.0);
    expect(await File(one).readAsString(), 'instance=1;request=1');
    expect(await File(two).readAsString(), 'instance=1;request=2');
    session.cancel();
    await expectLater(
      session.synthesize(text: 'again', wavPath: one, speed: 1),
      throwsA(isA<VitsWaveCancelled>()),
    );
  });

  test('new native readiness handshake separates model init and spawn',
      () async {
    final session = VitsPersistentSession.withEntrypoint(
        model, _timedReusableWorker);
    expect(session.workerReadyMs, isNull);
    expect(session.nativeModelInitializationMs, isNull);
    final wav = p.join(root.path, 'timed.wav');
    await session.synthesize(text: 'a', wavPath: wav, speed: 1);
    expect(session.workerReadyMs, greaterThanOrEqualTo(0));
    expect(session.nativeModelInitializationMs, 23);
    expect(session.lastNativeGenerationMs, 7);
    expect(await File(wav).readAsString(), 'timed-request=1');
    final firstWorkerReadyMs = session.workerReadyMs;
    await session.synthesize(text: 'b', wavPath: wav, speed: 1);
    expect(await File(wav).readAsString(), 'timed-request=2');
    expect(session.nativeModelInitializationMs, 23,
        reason: 'Reuse cannot reinitialize or double-count the model');
    expect(session.workerReadyMs, firstWorkerReadyMs);
    expect(session.lastNativeGenerationMs, 7);
    session.cancel();

    final legacy = VitsPersistentSession.withEntrypoint(
        model, _fakeReusableWorker);
    await legacy.synthesize(text: 'c',
        wavPath: p.join(root.path, 'legacy.wav'), speed: 1);
    expect(legacy.workerReadyMs, greaterThanOrEqualTo(0));
    expect(legacy.nativeModelInitializationMs, isNull,
        reason: 'Old worker handshake must not invent native timing');
    expect(legacy.lastNativeGenerationMs, isNull,
        reason: 'Older two-field responses cannot invent WAV timing');
    legacy.cancel();
  });

  test('explicit prepare loads native model with no WAV or text',
      () async {
    final session = VitsPersistentSession.withEntrypoint(
        model, _timedReusableWorker);
    final first = session.prepare();
    final second = session.prepare();
    await Future.wait([first, second]);
    expect(session.workerReadyMs, greaterThanOrEqualTo(0));
    expect(session.nativeModelInitializationMs, 23);
    expect(session.lastNativeGenerationMs, isNull);
    expect(await root.list().toList(), isEmpty,
        reason: 'A model-only warmup must not generate WAV files');
    await session.synthesize(text: 'later',
        wavPath: p.join(root.path, 'prepared.wav'), speed: 1);
    expect(await File(p.join(root.path, 'prepared.wav')).readAsString(),
        'timed-request=1',
        reason: 'Preparing does not consume a synthesis slot');
    session.cancel();
  });

  test('Stop cancels pending warmup without generating any WAV', () async {
    final session = VitsPersistentSession.withEntrypoint(
        model, _neverReadyWorker);
    final waiting = expectLater(
        session.prepare(), throwsA(isA<VitsWaveCancelled>()));
    session.cancel();
    await waiting;
    expect(session.isClosed, isTrue);
    expect(await root.list().toList(), isEmpty);
    await expectLater(session.prepare(),
        throwsA(isA<VitsWaveCancelled>()));
  });

  test('unused prepared model retires on unchanged idle timeout',
      () async {
    final timers = <_ManualVitsTimer>[];
    final session = VitsPersistentSession.withEntrypoint(
      model, _timedReusableWorker,
      timerScheduler: (delay, action) {
        final timer = _ManualVitsTimer(delay, action);
        timers.add(timer);
        return timer;
      },
    );
    await session.prepare();
    expect(await root.list().toList(), isEmpty);
    final idle = timers.lastWhere((timer) =>
        timer.delay == const Duration(minutes: 3) && timer.isActive);
    idle.fire();
    expect(session.isClosed, isTrue);
    expect(await root.list().toList(), isEmpty,
        reason: 'An idle warm model never generates audio or WAV files');
  });

  test('model initialization timeout also rejects explicit warmup',
      () async {
    final timers = <_ManualVitsTimer>[];
    final session = VitsPersistentSession.withEntrypoint(
      model, _neverReadyWorker,
      timerScheduler: (delay, action) {
        final timer = _ManualVitsTimer(delay, action);
        timers.add(timer);
        return timer;
      },
    );
    final waiting = expectLater(session.prepare(), throwsStateError);
    timers.firstWhere((timer) =>
        timer.delay == const Duration(seconds: 60)).fire();
    await waiting;
    expect(session.isClosed, isTrue);
    expect(await root.list().toList(), isEmpty);
  });

  test('busy persistent worker rejects second request and cancels first',
      () async {
    final session = VitsPersistentSession.withEntrypoint(
        model, _blockedReusableWorker);
    final started = session.synthesize(
        text: 'first', wavPath: p.join(root.path, 'one.wav'), speed: 1);
    final canceled = expectLater(
        started, throwsA(isA<VitsWaveCancelled>()));
    await expectLater(
      session.synthesize(
          text: 'second', wavPath: p.join(root.path, 'two.wav'), speed: 1),
      throwsStateError,
    );
    session.cancel();
    await canceled;
  });

  test('Stop before isolate is ready invalidates queued synthesis',
      () async {
    final session = VitsPersistentSession.withEntrypoint(
        model, _fakeReusableWorker);
    final started = session.synthesize(
        text: 'early', wavPath: p.join(root.path, 'early.wav'), speed: 1);
    final canceled = expectLater(
        started, throwsA(isA<VitsWaveCancelled>()));
    session.cancel();
    await canceled;
  });

  test('startup timeout rejects queued text and closes worker', () async {
    final timers = <_ManualVitsTimer>[];
    final session = VitsPersistentSession.withEntrypoint(
      model, _neverReadyWorker,
      timerScheduler: (duration, action) {
        final timer = _ManualVitsTimer(duration, action);
        timers.add(timer);
        return timer;
      },
    );
    final pending = session.synthesize(
      text: 'queued', wavPath: p.join(root.path, 'queued.wav'), speed: 1,
    );
    final failure = expectLater(pending, throwsStateError);
    final startup = timers.firstWhere(
        (timer) => timer.delay == const Duration(seconds: 60));
    startup.fire();
    await failure;
    expect(session.isClosed, isTrue);
    expect(timers.every((timer) => !timer.isActive), isTrue);
    await expectLater(session.synthesize(
        text: 'again', wavPath: p.join(root.path, 'again.wav'), speed: 1),
        throwsA(isA<VitsWaveCancelled>()));
  });

  test('synthesis watchdog retires unresponsive worker with a safe error',
      () async {
    final timers = <_ManualVitsTimer>[];
    final session = VitsPersistentSession.withEntrypoint(
      model, _neverCompletesWorker,
      timerScheduler: (duration, action) {
        final timer = _ManualVitsTimer(duration, action);
        timers.add(timer);
        return timer;
      },
    );
    final pending = session.synthesize(
      text: 'blocked', wavPath: p.join(root.path, 'blocked.wav'), speed: 1,
    );
    final failure = expectLater(pending, throwsStateError);
    timers.firstWhere(
      (timer) => timer.delay == const Duration(minutes: 3) &&
          timer.isActive,
    ).fire();
    await failure;
    expect(session.isClosed, isTrue);
    expect(timers.every((timer) => !timer.isActive), isTrue);
  });

  test('idle worker is released without an active request', () async {
    final timers = <_ManualVitsTimer>[];
    final session = VitsPersistentSession.withEntrypoint(
      model, _fakeReusableWorker,
      idleTimeout: const Duration(minutes: 4),
      timerScheduler: (duration, action) {
        final timer = _ManualVitsTimer(duration, action);
        timers.add(timer);
        return timer;
      },
    );
    await session.synthesize(
      text: 'one', wavPath: p.join(root.path, 'one.wav'), speed: 1,
    );
    expect(session.isClosed, isFalse);
    final idle = timers.lastWhere(
        (timer) => timer.delay == const Duration(minutes: 4) &&
            timer.isActive);
    idle.fire();
    expect(session.isClosed, isTrue);
    await expectLater(session.synthesize(
        text: 'two', wavPath: p.join(root.path, 'two.wav'), speed: 1),
        throwsA(isA<VitsWaveCancelled>()));
  });

  test('engine recovers from idle worker retirement on next phrase', () async {
    final pack = InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: 'mock-pack', displayName: 'Mock', locale: 'en-US',
        licenseId: 'MIT', modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
      ),
      modelPath: p.join(root.path, 'voice.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
    final timers = <_ManualVitsTimer>[];
    var created = 0;
    final output = _StringWaveOutput();
    final engine = SherpaVitsSpeechEngine(
      pack: pack,
      output: output,
      temporaryDirectory: () async => root,
      sessionFactory: (config) {
        created++;
        return VitsPersistentSession.withEntrypoint(
          config, _fakeReusableWorker,
          idleTimeout: const Duration(minutes: 4),
          timerScheduler: (duration, action) {
            final timer = _ManualVitsTimer(duration, action);
            timers.add(timer);
            return timer;
          },
        );
      },
    );
    await engine.speak('one', language: 'en-US', rate: 0.5, pitch: 1);
    timers.lastWhere((t) => t.delay == const Duration(minutes: 4) &&
        t.isActive).fire();
    await engine.speak('two', language: 'en-US', rate: 0.5, pitch: 1);
    expect(created, 2);
    expect(output.played, ['instance=1;request=1', 'instance=1;request=1']);
    await engine.dispose();
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
  });

  test('engine records cold ONNX load once per worker, not every phrase',
      () async {
    final pack = InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: 'mock-pack', displayName: 'Mock', locale: 'en-US',
        licenseId: 'MIT', modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
      ),
      modelPath: p.join(root.path, 'voice.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
    var created = 0;
    final engine = SherpaVitsSpeechEngine(
      pack: pack,
      output: _StringWaveOutput(),
      temporaryDirectory: () async => root,
      sessionFactory: (model) {
        created++;
        return VitsPersistentSession.withEntrypoint(
            model, _timedReusableWorker);
      },
    );
    expect(engine.offlineVoiceStatistics.lastNativeModelInitializationMs,
        isNull);
    await engine.speak('first', language: 'en-US', rate: 0.5, pitch: 1);
    final cold = engine.offlineVoiceStatistics;
    expect(cold.modelLoads, 1);
    expect(cold.lastNativeModelInitializationMs, 23);
    expect(cold.lastNativeGenerationMs, 7);
    expect(cold.lastWorkerReadyMs, greaterThanOrEqualTo(0));
    expect(cold.syntheses, 1);

    await engine.speak('second', language: 'en-US', rate: 0.5, pitch: 1);
    final warm = engine.offlineVoiceStatistics;
    expect(created, 1);
    expect(warm.modelLoads, 1);
    expect(warm.syntheses, 2);
    expect(warm.lastNativeModelInitializationMs, 23);
    expect(warm.lastNativeGenerationMs, 7);
    expect(warm.lastWorkerReadyMs, cold.lastWorkerReadyMs);

    await engine.stop();
    await engine.speak('third', language: 'en-US', rate: 0.5, pitch: 1);
    expect(created, 2,
        reason: 'Stop must still retire the native resident model');
    expect(engine.offlineVoiceStatistics.modelLoads, 2);
    expect(engine.offlineVoiceStatistics.lastNativeModelInitializationMs, 23);
    await engine.dispose();
  });

  test('model-only engine preparation reuses worker on next audible speech',
      () async {
    final pack = InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: 'mock-pack', displayName: 'Mock', locale: 'en-US',
        licenseId: 'MIT', modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
      ),
      modelPath: p.join(root.path, 'voice.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
    var created = 0;
    final output = _StringWaveOutput();
    final engine = SherpaVitsSpeechEngine(
      pack: pack, output: output,
      temporaryDirectory: () async => root,
      sessionFactory: (cfg) {
        created++;
        return VitsPersistentSession.withEntrypoint(
            cfg, _timedReusableWorker);
      },
    );
    await engine.chooseVoice(
        const SpeechVoice(name: 'mock-pack', locale: 'en-US'));
    await engine.prewarmModel();
    expect(created, 1);
    expect(engine.offlineVoiceStatistics.modelLoads, 1);
    expect(engine.offlineVoiceStatistics.syntheses, 0);
    expect(engine.offlineVoiceStatistics.lastNativeModelInitializationMs, 23);
    expect(await root.list().toList(), isEmpty);
    await engine.speak('audible', language: 'en-US',
        rate: 0.5, pitch: 1);
    expect(created, 1, reason: 'Do not spawn a second ONNX model');
    expect(output.played, ['timed-request=1']);
    expect(engine.offlineVoiceStatistics.syntheses, 1);
    await engine.stop();
    await engine.prewarmModel();
    expect(created, 2, reason: 'Stop must retire the old native model');
    await engine.dispose();
  });

  test('Stop cancels an engine model-only warmup in progress',
      () async {
    final pack = InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: 'mock-pack', displayName: 'Mock', locale: 'en-US',
        licenseId: 'MIT', modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
      ),
      modelPath: p.join(root.path, 'voice.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
    final engine = SherpaVitsSpeechEngine(
      pack: pack, output: _StringWaveOutput(),
      temporaryDirectory: () async => root,
      sessionFactory: (cfg) =>
          VitsPersistentSession.withEntrypoint(cfg, _neverReadyWorker),
    );
    await engine.chooseVoice(
        const SpeechVoice(name: 'mock-pack', locale: 'en-US'));
    final pending = expectLater(engine.prewarmModel(),
        throwsA(isA<VitsWaveCancelled>()));
    await engine.stop();
    await pending;
    expect(engine.offlineVoiceStatistics.syntheses, 0);
    expect(await root.list().toList(), isEmpty);
    await engine.dispose();
  });

  test('engine reuses one model across speech, then recreates after Stop',
      () async {
    final pack = InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: 'mock-pack', displayName: 'Mock', locale: 'en-US',
        licenseId: 'MIT', modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
      ),
      modelPath: p.join(root.path, 'voice.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
    var created = 0;
    final output = _StringWaveOutput();
    final engine = SherpaVitsSpeechEngine(
      pack: pack,
      output: output,
      temporaryDirectory: () async => root,
      sessionFactory: (config) {
        created++;
        return VitsPersistentSession.withEntrypoint(
            config, _fakeReusableWorker);
      },
    );
    await engine.speak('one', language: 'en-US', rate: 0.5, pitch: 1);
    await engine.speak('two', language: 'en-US', rate: 0.5, pitch: 1);
    expect(created, 1);
    expect(output.played,
        ['instance=1;request=1', 'instance=1;request=2']);
    await engine.stop();
    await engine.speak('three', language: 'en-US', rate: 0.5, pitch: 1);
    expect(created, 2);
    expect(output.played.last, 'instance=1;request=1');
    await engine.dispose();
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
  });
}
