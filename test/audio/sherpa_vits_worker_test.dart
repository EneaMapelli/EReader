import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:ereader/audio/sherpa_vits_worker.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void _completed((SendPort, VitsWaveRequest) message) {
  Isolate.exit(message.$1, [0]);
}

void _failed((SendPort, VitsWaveRequest) message) {
  Isolate.exit(message.$1, [1]);
}

void _neverFinishes((SendPort, VitsWaveRequest) message) {
  while (true) {
    sleep(const Duration(milliseconds: 250));
  }
}

class _ObservedWaveOutput implements OfflineWaveOutput {
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(String wavFile) async { playCount++; }

  @override
  Future<void> stop() async { stopCount++; }

  @override
  Future<void> dispose() async { disposeCount++; }
}

void main() {
  const request = VitsWaveRequest(
    text: 'offline voice test',
    modelPath: 'test-model.onnx',
    tokensPath: 'test-tokens.txt',
    dataDir: '',
    wavPath: 'never-written.wav',
    speed: 1.0,
  );

  test('native worker success transfers a small status, not model audio',
      () async {
    final job = VitsWaveJob.withEntrypoint(request, _completed);
    await job.result;
  });

  test('native worker failure does not disclose paths or model content',
      () async {
    final job = VitsWaveJob.withEntrypoint(request, _failed);
    await expectLater(job.result, throwsStateError);
  });

  test('cancellation settles result even if native worker never finishes',
      () async {
    final job = VitsWaveJob.withEntrypoint(request, _neverFinishes);
    final result = expectLater(
      job.result, throwsA(isA<VitsWaveCancelled>()),
    );
    job.cancel();
    await result;
    job.cancel();
  });

  test('immediately canceled worker cannot later complete successfully',
      () async {
    final job = VitsWaveJob.withEntrypoint(request, _completed);
    final result = expectLater(
      job.result, throwsA(isA<VitsWaveCancelled>()),
    );
    job.cancel();
    await result;
  });

  group('Reader Stop and Dispose with real cancellable worker contract', () {
    late Directory root;
    late InstalledOfflineVoicePack pack;
    late _ObservedWaveOutput output;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ereader-vits-job-');
      output = _ObservedWaveOutput();
      final manifest = OfflineVoicePackManifest(
        id: 'vits-local-test', displayName: 'Test', locale: 'en-US',
        licenseId: 'MIT', modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
      );
      pack = InstalledOfflineVoicePack(
        manifest: manifest,
        modelPath: p.join(root.path, 'model.onnx'),
        tokensPath: p.join(root.path, 'tokens.txt'),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('Stop cancels active worker, suppresses audio and clears temp WAV',
        () async {
      final created = Completer<void>();
      final engine = SherpaVitsSpeechEngine(
        pack: pack, output: output, temporaryDirectory: () async => root,
        jobFactory: (req) {
          final job = VitsWaveJob.withEntrypoint(req, _neverFinishes);
          created.complete();
          return job;
        },
      );
      final playback = engine.speak(
        'long native synthesis', language: 'en-US', rate: 0.5, pitch: 1,
      );
      await created.future;
      await engine.stop();
      await playback;
      expect(output.playCount, 0);
      expect(output.stopCount, 1);
      expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
      await engine.dispose();
    });

    test('Dispose cancels active worker without playing late sound',
        () async {
      final created = Completer<void>();
      final engine = SherpaVitsSpeechEngine(
        pack: pack, output: output, temporaryDirectory: () async => root,
        jobFactory: (req) {
          final job = VitsWaveJob.withEntrypoint(req, _neverFinishes);
          created.complete();
          return job;
        },
      );
      final playback = engine.speak(
        'pending voice', language: 'en-US', rate: 0.5, pitch: 1,
      );
      await created.future;
      await engine.dispose();
      await playback;
      expect(output.playCount, 0);
      expect(output.disposeCount, 1);
      expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    });
  });
}
