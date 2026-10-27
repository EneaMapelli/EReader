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

/// One unconsumed, optional future WAV, never multiple queued jobs.
class _PreparedWave {
  _PreparedWave(this.text, this.language, this.rate, this.pitch, this.voiceKey);
  final String text;
  final String language;
  final double rate;
  final double pitch;
  final String voiceKey;
  Future<void>? task;
  Directory? staging;
  String? wavPath;
  bool ready = false;

  bool matches(String value, String locale, double speed, double tone,
      String selected) =>
      text == value && language == locale && rate == speed &&
      pitch == tone && voiceKey == selected;
}

/// Prototype local VITS engine using the same SpeechEngine contract as
/// OS TTS/cloud. Not registered in the user-selectable provider registry
/// until the device and model-asset gates have been passed.
///
/// Unlike cloud providers, this never accesses API keys, quotas or network.
/// Stop requests immediate worker-isolate termination and suppresses delayed
/// WAV playback. Dart cannot guarantee instantaneous preemption of a native
/// blocking FFI call; physical device testing remains mandatory.
class SherpaVitsSpeechEngine implements SpeechEngine, OfflineAheadSpeechEngine {
  static const providerId = 'sherpa-vits';

  SherpaVitsSpeechEngine({
    required this.pack,
    this.dataDir = '',
    OfflineWaveSynthesizer? synthesizer,
    VitsWaveJob Function(VitsWaveRequest)? jobFactory,
    OfflineWaveOutput? output,
    Future<Directory> Function()? temporaryDirectory,
  })  : _synthesizer = synthesizer,
        _jobFactory = jobFactory ?? VitsWaveJob.new,
        _output = output ?? JustAudioWaveOutput(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    pack.manifest.validate();
  }

  final InstalledOfflineVoicePack pack;
  final String dataDir;
  /// Optional mock synthesizer; production uses a cancellable isolate job.
  final OfflineWaveSynthesizer? _synthesizer;
  final VitsWaveJob Function(VitsWaveRequest) _jobFactory;
  VitsWaveJob? _nativeJob;
  _PreparedWave? _prepared;
  Future<void>? _currentSynthesisReady;
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

  void _validateSpeech(String text, String language, double rate,
      double pitch) {
    if (_disposed) throw StateError('Offline TTS disposed');
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
  }

  Future<bool> _synthesizeWave(String text, String wavPath, double rate) async {
    final speed = (rate / 0.5).clamp(0.4, 2.0).toDouble();
    final mock = _synthesizer;
    if (mock != null) {
      await mock(
        text: text, modelPath: pack.modelPath, tokensPath: pack.tokensPath,
        dataDir: dataDir, wavPath: wavPath, speed: speed,
      );
      return true;
    }
    if (_nativeJob != null) {
      throw StateError('Offline synthesis is already running');
    }
    final job = _jobFactory(VitsWaveRequest(
      text: text, modelPath: pack.modelPath, tokensPath: pack.tokensPath,
      dataDir: dataDir, wavPath: wavPath, speed: speed,
    ));
    _nativeJob = job;
    try {
      await job.result;
      return true;
    } on VitsWaveCancelled {
      return false;
    } finally {
      if (identical(_nativeJob, job)) _nativeJob = null;
    }
  }

  Future<void> _deleteStaging(Directory? staging) async {
    if (staging == null) return;
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } on FileSystemException {
      // Native Windows WAV handles may linger after Stop.
      // Never play stale speech as a side effect of cleanup.
    }
  }

  /// Prepare one LOCAL future segment after the current synthesis finishes.
  /// While the current WAV plays, native synthesis may warm the next one.
  /// This never obtains keys, networks, quotas or model downloads.
  @override
  Future<void> prepareOfflineSpeech(
    String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  }) async {
    _validateSpeech(text, language, rate, pitch);
    if (text.isEmpty) return;
    if (voice != null && voice.key != _packVoice.key) return;
    final priorSynthesis = _currentSynthesisReady;
    if (priorSynthesis == null) return;
    final previous = _prepared;
    if (previous != null) {
      if (previous.matches(text, language, rate, pitch, _packVoice.key)) {
        await previous.task;
      }
      return; // Never enqueue another native model instance.
    }
    final token = _generation;
    final next = _PreparedWave(text, language, rate, pitch, _packVoice.key);
    _prepared = next;
    final task = _prepareWave(next, token, priorSynthesis);
    next.task = task;
    await task;
  }

  Future<void> _prepareWave(
      _PreparedWave next, int token, Future<void> priorSynthesis) async {
    try {
      await priorSynthesis;
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      final root = await _temporaryDirectory();
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      next.staging = await root.createTemp('ereader-local-lookahead-');
      next.wavPath =
          next.staging!.path + Platform.pathSeparator + 'speech.wav';
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      final completed =
          await _synthesizeWave(next.text, next.wavPath!, next.rate);
      if (!completed || _disposed || token != _generation ||
          !identical(_prepared, next)) return;
      if (!await File(next.wavPath!).exists()) return;
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      next.ready = true;
    } catch (_) {
      // Optional warming is best effort; audible speak reports real errors.
    } finally {
      if (!next.ready || _disposed || token != _generation ||
          !identical(_prepared, next)) {
        if (identical(_prepared, next)) _prepared = null;
        await _deleteStaging(next.staging);
      }
    }
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    _validateSpeech(text, language, rate, pitch);
    if (text.isEmpty) return;
    final token = _generation;
    final ready = Completer<void>();
    // Synchronously publish the synthesis barrier before our first await.
    _currentSynthesisReady = ready.future;
    Directory? staging;
    String? wavPath;
    try {
      final pending = _prepared;
      if (pending != null &&
          pending.matches(text, language, rate, pitch, _packVoice.key)) {
        await pending.task;
        if (_disposed || token != _generation) return;
        if (pending.ready) {
          staging = pending.staging;
          wavPath = pending.wavPath;
          _prepared = null; // This audible clip owns file cleanup now.
        }
      }
      if (staging == null) {
        final root = await _temporaryDirectory();
        if (_disposed || token != _generation) return;
        staging = await root.createTemp('ereader-local-tts-');
        wavPath = staging.path + Platform.pathSeparator + 'speech.wav';
        if (_disposed || token != _generation) return;
        final completed = await _synthesizeWave(text, wavPath, rate);
        if (!completed || _disposed || token != _generation) return;
      }
      if (!await File(wavPath!).exists()) {
        throw StateError('Offline TTS generated no WAV file');
      }
      if (_disposed || token != _generation) return;
      if (!ready.isCompleted) ready.complete();
      await _output.play(wavPath);
    } finally {
      if (!ready.isCompleted) ready.complete();
      if (identical(_currentSynthesisReady, ready.future)) {
        _currentSynthesisReady = null;
      }
      await _deleteStaging(staging);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _nativeJob?.cancel();
    _nativeJob = null;
    final pending = _prepared;
    _prepared = null;
    // Native audible Stop is more important than deleting a future WAV.
    // Cleanup must not delay the user's Pause/Stop or focus release.
    try {
      await _output.stop();
    } finally {
      if (pending != null && pending.ready) {
        await _deleteStaging(pending.staging);
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _nativeJob?.cancel();
    _nativeJob = null;
    final pending = _prepared;
    _prepared = null;
    // Dispose the active decoder first so Windows can release WAV handles.
    try {
      await _output.dispose();
    } finally {
      if (pending != null && pending.ready) {
        await _deleteStaging(pending.staging);
      }
    }
  }
}
