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
