import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:path/path.dart' as p;

/// Opt-in, simulated long-session WAV test. NEVER loads native ONNX,
/// books, platform sound output, API secrets, or internet resources.
/// Run: flutter test tool/offline_vits_soak_test.dart --dart-define=EREADER_SOAK_ITERATIONS=200
class _FakeOutput implements OfflineWaveOutput {
  int plays = 0;
  int stops = 0;
  Completer<void>? _gate;
  Completer<void>? _entered;

  void blockNext() {
    _gate = Completer<void>();
    _entered = Completer<void>();
  }

  Future<void> get entered => _entered!.future;

  void release() {
    final old = _gate;
    _gate = null;
    _entered = null;
    if (old != null && !old.isCompleted) old.complete();
  }

  @override
  Future<void> play(String wav) async {
    if (await File(wav).length() != 4) {
      throw StateError('Synthetic WAV was missing or invalid');
    }
    plays++;
    final gate = _gate;
    final started = _entered;
    if (started != null && !started.isCompleted) started.complete();
    if (gate != null) await gate.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    release();
  }

  @override
  Future<void> dispose() async { release(); }
}

Future<int> _wavFiles(Directory root) async {
  var count = 0;
  await for (final entry in root.list(
      recursive: true, followLinks: false)) {
    if (entry is File && p.basename(entry.path) == 'speech.wav') count++;
  }
  return count;
}

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln('flutter test tool/offline_vits_soak_test.dart --dart-define=EREADER_SOAK_ITERATIONS=200');
    return;
  }
  var iterations = 200;
  if (args.isNotEmpty) {
    if (args.length != 2 || args[0] != '--iterations') {
      throw const FormatException('Expected --iterations N');
    }
    iterations = int.parse(args[1]);
  }
  if (iterations < 2 || iterations > 2000) {
    throw const FormatException('Iterations must be from 2 to 2000');
  }

  // A random-owned temp directory, never an existing book/user directory.
  final root = await Directory.systemTemp.createTemp('ereader-soak-');
  final output = _FakeOutput();
  final pack = InstalledOfflineVoicePack(
    manifest: OfflineVoicePackManifest(
      id: 'synthetic-voice', displayName: 'Soak simulation',
      locale: 'en-US', licenseId: 'MIT',
      modelSha256: 'a' * 64, tokensSha256: 'b' * 64,
    ),
    modelPath: p.join(root.path, 'unused.onnx'),
    tokensPath: p.join(root.path, 'unused-tokens.txt'),
  );
  final stopwatch = Stopwatch()..start();
  var requests = 0;
  final interruptedStart = Completer<void>();
  final releaseInterrupted = Completer<void>();
  final engine = SherpaVitsSpeechEngine(
    pack: pack, output: output,
    temporaryDirectory: () async => root,
    synthesizer: ({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      requests++;
      if (text == 'Interrupted') {
        interruptedStart.complete();
        await releaseInterrupted.future;
      }
      await File(wavPath).writeAsBytes([82, 73, 70, 70]);
    },
  );

  try {
    for (var i = 0; i < iterations; i++) {
      final text = 'Synthetic segment $i';
      final rate = ((i ~/ 10).isEven) ? 0.5 : 0.75;
      if (i % 10 == 0 && i + 1 < iterations) {
        output.blockNext();
        final first = engine.speak(text,
            language: 'en-US', rate: rate, pitch: 1);
        await output.entered;
        await engine.prepareOfflineSpeech(
          'Synthetic segment ' + (i + 1).toString(),
          voice: null, language: 'en-US', rate: rate, pitch: 1,
        );
        output.release();
        await first;
      } else {
        await engine.speak(text,
            language: 'en-US', rate: rate, pitch: 1);
      }
      // At most ONE prepared WAV may remain between audible clips.
      if (await _wavFiles(root) > 1) {
        throw StateError('Unexpected unreleased WAV files');
      }
      if ((i + 1) % 25 == 0) await engine.stop();
    }

    final beforeCancel = output.plays;
    final late = engine.speak('Interrupted',
        language: 'en-US', rate: 0.5, pitch: 1);
    await interruptedStart.future;
    await engine.stop();
    releaseInterrupted.complete();
    await late;
    if (output.plays != beforeCancel) {
      throw StateError('Stale audio played after Stop');
    }

    final stats = engine.offlineVoiceStatistics;
    if (stats.syntheses < iterations ||
        stats.warmedWaveReuses == 0 ||
        stats.pendingWaveFolders != 0 || stats.modelLoads != 0) {
      throw StateError('Unexpected long-session synthetic metrics');
    }
    await engine.dispose();
    final leftover = await root.list().toList();
    if (leftover.isNotEmpty) {
      throw StateError('Private WAV lease/metadata remained after Dispose');
    }
    stopwatch.stop();
    stdout.writeln(jsonEncode({
      'mode': 'synthetic-no-native-audio',
      'result': 'PASS',
      'iterations': iterations,
      'syntheses': stats.syntheses,
      'warmedWavReuses': stats.warmedWaveReuses,
      'nativeModelLoads': stats.modelLoads,
      'fakeOutputPlays': output.plays,
      'stops': output.stops,
      'fakeRequests': requests,
      'unreleasedWavFiles': 0,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    }));
  } finally {
    // Never delete the global temp root, only this process's new folder.
    await engine.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
