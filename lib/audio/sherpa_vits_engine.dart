import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../data/offline_voice_pack.dart';
import 'speech_engine.dart';

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

/// Native calls stay wholly inside a worker isolate so ONNX inference does
/// not freeze Flutter's build/raster thread. FFI bindings must be initialized
/// separately in the worker isolate. VITS output is written to an app-private
/// WAV file; the large Float32List never crosses isolate boundaries.
///
/// Each call currently initializes and frees a model. This intentionally
/// prioritizes correctness over latency until a persistent cancellable
/// sherpa worker and device memory benchmarks are available.
Future<void> synthesizeVitsWave({
  required String text,
  required String modelPath,
  required String tokensPath,
  required String dataDir,
  required String wavPath,
  required double speed,
}) async {
  await Isolate.run(() {
    sherpa.initBindings();
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: modelPath,
          tokens: tokensPath,
          dataDir: dataDir,
        ),
        numThreads: 2,
        provider: 'cpu',
      ),
    );
    final tts = sherpa.OfflineTts(config);
    try {
      final generated = tts.generate(text: text, speed: speed);
      if (generated.sampleRate < 8000 ||
          generated.sampleRate > 96000 ||
          generated.samples.isEmpty ||
          generated.samples.length > generated.sampleRate * 90) {
        throw const FormatException('Invalid offline generated audio duration');
      }
      final written = sherpa.writeWave(
        filename: wavPath,
        samples: generated.samples,
        sampleRate: generated.sampleRate,
      );
      if (!written) throw StateError('Offline wave writer failed');
    } finally {
      tts.free();
    }
  });
}

/// Prototype local VITS engine using the same SpeechEngine contract as
/// OS TTS/cloud. Not registered in the user-selectable provider registry
/// until the device and model-asset gates have been passed.
///
/// Unlike cloud providers, this never accesses API keys, quotas or network.
/// Stop never starts playback of an already canceled synthesis. Native ONNX
/// computation may continue until its bounded chunk finishes; a persistent
/// worker with hard cancellation is a later native milestone.
class SherpaVitsSpeechEngine implements SpeechEngine {
  SherpaVitsSpeechEngine({
    required this.pack,
    this.dataDir = '',
    OfflineWaveSynthesizer synthesizer = synthesizeVitsWave,
    OfflineWaveOutput? output,
    Future<Directory> Function()? temporaryDirectory,
  })  : _synthesizer = synthesizer,
        _output = output ?? JustAudioWaveOutput(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    pack.manifest.validate();
  }

  final InstalledOfflineVoicePack pack;
  final String dataDir;
  final OfflineWaveSynthesizer _synthesizer;
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
      await _synthesizer(
        text: text,
        modelPath: pack.modelPath,
        tokensPath: pack.tokensPath,
        dataDir: dataDir,
        wavPath: wavPath,
        speed: (rate / 0.5).clamp(0.4, 2.0).toDouble(),
      );
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
    await _output.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _output.dispose();
  }
}
