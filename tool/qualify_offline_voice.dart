// Local, opt-in sherpa-onnx qualification. Requires a fully installed,
// verified model and native Windows/Android assets. Not a Flutter unit test.
//
// dart run tool/qualify_offline_voice.dart --models-dir ABSOLUTE_DIRECTORY
//   --pack-id voice-id --accept-native-risk [--retain-wav] [--exercise-stop]
//
// Output is sanitized numeric JSON. WAV files are deleted by default.
// --retain-wav saves only this script's fixed public-domain sample phrases
// in the gitignored .local-test-results directory for listening.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ereader/audio/offline_wave_metrics.dart';
import 'package:ereader/audio/sherpa_vits_worker.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:path/path.dart' as p;

const _toolVersion = 1;
const _limit = Duration(seconds: 120);
const _samples = <String, List<String>>{
  'it': [
    'Buongiorno. Questa è una prova della voce sintetica locale.',
    'Il lettore prova la punteggiatura: una domanda? Una risposta! '
        'Una frase più lunga per misurare la velocità di sintesi.',
  ],
  'en': [
    'Good morning. This is a local neural speech test.',
    'The reader checks punctuation: a question? An answer! '
        'A slightly longer sentence to measure synthesis latency.',
  ],
};

Future<void> main(List<String> args) async {
  final result = <String, Object?>{
    'schemaVersion': _toolVersion,
    'kind': 'offline-vits-local-qualification',
    'status': 'FAIL',
    'samples': <Object>[],
  };
  Directory? staging;
  try {
    final flags = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--accept-native-risk' ||
          args[i] == '--retain-wav' ||
          args[i] == '--exercise-stop') {
        if (flags.containsKey(args[i])) {
          throw const FormatException('Duplicate CLI option');
        }
        flags[args[i]] = 'true';
      } else if (args[i] == '--models-dir' || args[i] == '--pack-id') {
        if (i + 1 >= args.length || flags.containsKey(args[i])) {
          throw const FormatException('Missing/duplicate CLI option');
        }
        flags[args[i]] = args[++i];
      } else {
        throw const FormatException('Unknown CLI option');
      }
    }
    final modelPath = flags['--models-dir'];
    final packId = flags['--pack-id'];
    if (flags['--accept-native-risk'] != 'true' ||
        modelPath == null || packId == null ||
        !p.isAbsolute(modelPath)) {
      throw const FormatException(
          'Explicit opt-in, an absolute models directory, and ID required');
    }

    final pack = await loadInstalledOfflineVoicePack(
      packId: packId,
      modelsDirectory: Directory(modelPath),
    );
    final language = pack.manifest.locale.split(RegExp('[-_]')).first
        .toLowerCase();
    final passages = _samples[language];
    if (passages == null) {
      throw const FormatException('Qualification supports Italian/English');
    }
    result['packId'] = pack.manifest.id;
    result['locale'] = pack.manifest.locale;
    result['localManifestVerified'] = true;
    result['licensePublisherAuthenticated'] = false;

    staging = await Directory.systemTemp.createTemp(
      'ereader-voice-qualification-',
    );
    final measurements = <Map<String, Object?>>[];
    for (var i = 0; i < passages.length; i++) {
      final out = File(p.join(staging.path, 'sample-${i + 1}.wav'));
      final watch = Stopwatch()..start();
      final job = VitsWaveJob(VitsWaveRequest(
        text: passages[i],
        modelPath: pack.modelPath,
        tokensPath: pack.tokensPath,
        dataDir: pack.phonemizerDataDir ?? '',
        wavPath: out.path,
        speed: 1.0,
      ));
      try {
        await job.result.timeout(_limit);
      } on TimeoutException {
        job.cancel();
        throw const FormatException('Native synthesis exceeded time budget');
      }
      watch.stop();
      final audio = await inspectOfflinePcmWave(out);
      final rtf = watch.elapsedMilliseconds / audio.durationMs;
      measurements.add({
        'sample': i + 1,
        'synthesisMs': watch.elapsedMilliseconds,
        'audio': audio.toJson(),
        'realTimeFactor': double.parse(rtf.toStringAsFixed(3)),
        // Current whole-process RSS includes native heap shared by isolates;
        // it is not precise peak memory attributable to the model.
        'processRssMiB': (ProcessInfo.currentRss / (1024 * 1024)).round(),
      });
      if (flags['--retain-wav'] == 'true') {
        final outputDir = Directory(
            p.join(Directory.current.path, '.local-test-results',
                'offline-voice-listening'));
        await outputDir.create(recursive: true);
        await out.copy(p.join(outputDir.path,
            '${pack.manifest.id}-sample-${i + 1}.wav'));
      }
    }
    result['samples'] = measurements;

    if (flags['--exercise-stop'] == 'true') {
      // Separate opt-in: on some native platforms terminating an isolate
      // during blocking FFI might not be immediately preemptible.
      final job = VitsWaveJob(VitsWaveRequest(
        text: passages.last,
        modelPath: pack.modelPath,
        tokensPath: pack.tokensPath,
        dataDir: pack.phonemizerDataDir ?? '',
        wavPath: p.join(staging.path, 'cancellation.wav'),
        speed: 1.0,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final clock = Stopwatch()..start();
      job.cancel();
      try {
        await job.result.timeout(const Duration(seconds: 10));
        result['stopOutcome'] = 'completed-before-cancel';
      } on VitsWaveCancelled {
        result['stopOutcome'] = 'cancelled';
      } on TimeoutException {
        result['stopOutcome'] = 'timeout';
        throw const FormatException('Stop did not settle the job');
      }
      clock.stop();
      result['stopSettleMs'] = clock.elapsedMilliseconds;
    }
    result['status'] = 'PASS';
  } catch (_) {
    // Never emit native errors, input paths, book excerpts, API credentials,
    // model names from unverified manifests, or private stack traces.
    result['status'] = 'FAIL';
    result['failureClass'] = 'qualification-rejected-or-runtime-failed';
    exitCode = 1;
  } finally {
    if (staging != null) {
      try {
        if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } on FileSystemException {
        // The local status still fails; a Windows decoder may hold an output
        // temporarily. No private filesystem path is written to the report.
        result['temporaryCleanup'] = 'incomplete';
        result['status'] = 'FAIL';
        exitCode = 1;
      }
    }
    stdout.writeln(jsonEncode(result));
  }
}
