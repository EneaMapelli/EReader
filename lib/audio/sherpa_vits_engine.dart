import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../data/offline_voice_pack.dart';
import 'speech_engine.dart';
import 'sherpa_vits_worker.dart';

/// A separate audio boundary makes model synthesis testable with no native
/// ONNX library, sound output, model download or network permissions.
abstract interface class OfflineWaveOutput {
  Future<void> play(String wavFile);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioWaveOutput implements OfflineWaveOutput {
  JustAudioWaveOutput() : _player = AudioPlayer();

  final AudioPlayer _player;
  int _revision = 0;
  bool _disposed = false;

  @override
  Future<void> play(String wavFile) async {
    if (_disposed) throw StateError('Offline audio output disposed');
    final version = _revision;
    await _player.setFilePath(wavFile);
    if (_disposed || version != _revision) return;
    await _player.play();
  }

  @override
  Future<void> stop() async {
    _revision++;
    if (!_disposed) await _player.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    await _player.dispose();
  }
}

typedef OfflineWaveSynthesizer = Future<void> Function({
  required String text,
  required String modelPath,
  required String tokensPath,
  required String dataDir,
  required String wavPath,
  required double speed,
});

/// Compatibility helper for one native utterance. Production playback
/// retains its [VitsWaveJob] handle so Stop may also request cancellation.
Future<void> synthesizeVitsWave({
  required String text,
  required String modelPath,
  required String tokensPath,
  required String dataDir,
  required String wavPath,
  required double speed,
}) => VitsWaveJob(VitsWaveRequest(
  text: text,
  modelPath: modelPath,
  tokensPath: tokensPath,
  dataDir: dataDir,
  wavPath: wavPath,
  speed: speed,
)).result;

/// Prototype local VITS engine using the same SpeechEngine contract as
/// OS TTS/cloud. Not registered in the user-selectable provider registry
/// until the device and model-asset gates have been passed.
///
/// Unlike cloud providers, this never accesses API keys, quotas or network.
/// Stop requests immediate worker-isolate termination and suppresses delayed
/// WAV playback. Dart cannot guarantee instantaneous preemption of a native
/// blocking FFI call; physical device testing remains mandatory.
class SherpaVitsSpeechEngine implements SpeechEngine {
  static const providerId = 'sherpa-vits';

  SherpaVitsSpeechEngine({
    required this.pack,
    this.dataDir = '',
    OfflineWaveSynthesizer? synthesizer,
    OfflineWaveOutput? output,
    Future<Directory> Function()? temporaryDirectory,
  })  : _synthesizer = synthesizer,
        _output = output ?? JustAudioWaveOutput(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    pack.manifest.validate();
  }

  final InstalledOfflineVoicePack pack;
  final String dataDir;
  /// Optional mock synthesizer; production uses a cancellable isolate job.
  final OfflineWaveSynthesizer? _synthesizer;
  VitsWaveJob? _nativeJob;
  final OfflineWaveOutput _output;
  final Future<Directory> Function() _temporaryDirectory;

  int _generation = 0;
  bool _disposed = false;
  SpeechVoice? _voice;

  SpeechVoice get _packVoice => SpeechVoice(
    name: pack.manifest.id,
    locale: pack.manifest.locale,
  );

  @override
  Future<List<SpeechVoice>> listVoices() async => [_packVoice];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    if (_disposed) throw StateError('Offline TTS disposed');
    if (voice.key != _packVoice.key) {
      throw const FormatException('Offline voice not installed');
    }
    _voice = voice;
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    if (_disposed) throw StateError('Offline TTS disposed');
    if (text.isEmpty) return;
    if (text.length > 2048) {
      throw const FormatException('Offline VITS chunk is too long');
    }
    if (language.toLowerCase().replaceAll('_', '-') !=
        pack.manifest.locale.toLowerCase().replaceAll('_', '-')) {
      throw const FormatException('Offline voice does not match book language');
    }
    if (!rate.isFinite || rate < 0.2 || rate > 1) {
      throw const FormatException('Invalid offline speech rate');
    }
    if (pitch != 1) {
      throw UnsupportedError('VITS post-synthesis pitch control unavailable');
    }
    if (_voice != null && _voice!.key != _packVoice.key) {
      throw const FormatException('Selected offline voice changed');
    }

    final token = _generation;
    final root = await _temporaryDirectory();
    if (_disposed || token != _generation) return;
    final staging = await root.createTemp('ereader-local-tts-');
    final wavPath = '${staging.path}${Platform.pathSeparator}speech.wav';
    try {
      if (_disposed || token != _generation) return;
      final speed = (rate / 0.5).clamp(0.4, 2.0).toDouble();
      final mock = _synthesizer;
      if (mock != null) {
        // Keep unit tests entirely independent of native ONNX binaries.
        await mock(
          text: text,
          modelPath: pack.modelPath,
          tokensPath: pack.tokensPath,
          dataDir: dataDir,
          wavPath: wavPath,
          speed: speed,
        );
      } else {
        // A previous utterance must be finished or explicitly stopped.
        if (_nativeJob != null) {
          throw StateError('Offline synthesis is already running');
        }
        final job = VitsWaveJob(VitsWaveRequest(
          text: text,
          modelPath: pack.modelPath,
          tokensPath: pack.tokensPath,
          dataDir: dataDir,
          wavPath: wavPath,
          speed: speed,
        ));
        _nativeJob = job;
        try {
          await job.result;
        } on VitsWaveCancelled {
          return; // Stop/Dispose cancelled this job; never play its WAV.
        } finally {
          if (identical(_nativeJob, job)) _nativeJob = null;
        }
      }
      if (_disposed || token != _generation) return;
      if (!await File(wavPath).exists()) {
        throw StateError('Offline TTS generated no WAV file');
      }
      if (_disposed || token != _generation) return;
      await _output.play(wavPath);
    } finally {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Some Windows decoders retain temporary handles briefly after
          // Stop. This local cleanup failure must never restart narration.
        }
      }
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _nativeJob?.cancel();
    _nativeJob = null;
    await _output.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _nativeJob?.cancel();
    _nativeJob = null;
    await _output.dispose();
  }
}
