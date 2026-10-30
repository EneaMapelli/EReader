import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../data/offline_voice_pack.dart';
import 'speech_engine.dart';
import 'sherpa_vits_worker.dart';
import 'sherpa_vits_session.dart';
import 'offline_voice_diagnostics.dart';
import 'offline_wav_cleanup.dart';
import 'offline_wav_session.dart';
import 'offline_wave_metrics.dart';

/// A separate audio boundary makes model synthesis testable with no native
/// ONNX library, sound output, model download or network permissions.
abstract interface class OfflineWaveOutput {
  Future<void> play(String wavFile);
  Future<void> stop();
  Future<void> dispose();
}

/// Optional decoder-only preload of an ALREADY synthesized private WAV.
/// Never invokes text synthesis, the network or a cloud provider.
abstract interface class PreloadableOfflineWaveOutput
    implements OfflineWaveOutput {
  Future<void> prepareNext(String wavFile);
  /// Waits for the idle decoder to release a mismatched prepared WAV
  /// before the file's owner is permitted to remove that private file.
  Future<void> discardNext();
}

/// Injectable native boundary: unit tests may hold a decoder load/stop
/// without instantiating a Windows/Android platform audio plugin.
abstract interface class WaveDecoder {
  Future<void> load(String wavFile);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioWaveDecoder implements WaveDecoder {
  JustAudioWaveDecoder() : _player = AudioPlayer();
  final AudioPlayer _player;

  @override
  Future<void> load(String wavFile) async {
    await _player.setFilePath(wavFile);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Native decoder operations are serialized without serializing the full
/// playback duration. Stop can interrupt playback immediately when the
/// decoder is ready, but must wait for an unfinished setFilePath operation
/// before calling the SAME decoder's native Stop.
///
/// ReaderPlayer already bounds native Stop confirmation. If native load
/// hangs, its timeout keeps narration locked rather than allowing two
/// overlapping utterances with the same audio device.
class JustAudioWaveOutput implements OfflineWaveOutput {
  JustAudioWaveOutput({WaveDecoder? decoder})
      : _decoder = decoder ?? JustAudioWaveDecoder();

  final WaveDecoder _decoder;
  Future<void> _nativeOperations = Future<void>.value();
  Future<void>? _disposeFuture;
  int _revision = 0;
  bool _disposed = false;
  // Native file handles can remain open after a partial/failed load.
  // Only a SUCCESSFUL physical Stop clears this obligation.
  bool _needsNativeStop = false;
  String? _loadedFile;

  Future<void> _confirmNativeStop() async {
    if (!_needsNativeStop) return;
    await _decoder.stop();
    _needsNativeStop = false;
    _loadedFile = null;
  }

  /// Chain load/Stop/dispose on ONE decoder. A previous failed load
  /// cannot poison the next native Stop or the user's later Play.
  Future<void> _serialize(Future<void> Function() operation) {
    final previous = _nativeOperations;
    final running = () async {
      try {
        await previous;
      } catch (_) {
        // A previous unsuccessful load still needs native cleanup.
      }
      await operation();
    }();
    _nativeOperations = running;
    return running;
  }

  /// Preload on an idle slot only. While loading, Stop and Dispose append
  /// their native operations behind this load, never racing the decoder.
  Future<void> prepare(String wavFile) async {
    if (_disposed) throw StateError('Offline audio output disposed');
    final version = _revision;
    await _serialize(() async {
      if (_disposed || version != _revision) return;
      if (_loadedFile == wavFile && _needsNativeStop) return;
      await _confirmNativeStop();
      if (_disposed || version != _revision) return;
      _needsNativeStop = true;
      _loadedFile = null;
      try {
        await _decoder.load(wavFile);
        _loadedFile = wavFile;
      } catch (_) {
        try {
          await _confirmNativeStop();
        } catch (_) {
          // Retain the native-stop obligation for the next invocation.
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> play(String wavFile) async {
    if (_disposed) throw StateError('Offline audio output disposed');
    final version = _revision;
    await _serialize(() async {
      if (_disposed || version != _revision) return;
      // A WAV prepared on this exact decoder can start without another
      // setFilePath. All other files require confirmed native Stop first.
      if (_loadedFile == wavFile && _needsNativeStop) return;
      await _confirmNativeStop();
      if (_disposed || version != _revision) return;
      _needsNativeStop = true; // BEFORE native setFilePath.
      _loadedFile = null;
      try {
        await _decoder.load(wavFile);
        _loadedFile = wavFile;
      } catch (_) {
        // A partially opened file still requires physical Stop.
        try {
          await _confirmNativeStop();
        } catch (_) {
          // Retain _needsNativeStop=true so future loads first retry Stop.
          // The original load error is still reported to the reader.
        }
        rethrow;
      }
    });
    if (_disposed || version != _revision) {
      // A cancelled load may settle BEFORE the queued native Stop does.
      // Keep the WAV alive until that Stop/Dispose has settled; otherwise
      // the engine's finalizer could delete a Windows file still in use.
      await _nativeOperations;
      return;
    }
    try {
      // Do NOT queue the entire playback duration: Stop must reach the
      // native decoder while sound is playing.
      await _decoder.play();
    } finally {
      if (!_disposed && version == _revision) {
        // A natural end is not proof that Windows closed the WAV handle.
        // The engine may delete this private WAV only AFTER confirmed Stop.
        await _serialize(() async {
          if (!_disposed && version == _revision) {
            await _confirmNativeStop();
          }
        });
      }
      if (_disposed || version != _revision) {
        // A platform play() Future can resolve before native stop() does.
        // Do not let the engine delete the private WAV until that stop
        // (or decoder disposal) has actually completed.
        await _nativeOperations;
      }
      // A newer Stop/Dispose owns native cleanup after invalidation.
      // This stale finalizer must NEVER stop a newer live utterance.
    }
  }

  @override
  Future<void> stop() {
    // Invalidate future playback synchronously, BEFORE waiting for load.
    _revision++;
    _loadedFile = null;
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    // Always execute a previously requested native Stop, even if Dispose
    // is subsequently requested; both operations must be fully serialized.
    return _serialize(_confirmNativeStop);
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _revision++;
    _loadedFile = null;
    _disposed = true;
    // Any in-flight load and Stop must finish before decoder disposal.
    // Physical disposal is the final native cleanup when Stop itself
    // failed. Never mark a failed Stop as confirmed.
    return _disposeFuture = _serialize(() => _decoder.dispose());
  }
}

/// Two physical WAV decoders. At most one is audible while the other
/// may load exactly ONE already synthesized future WAV in advance.
/// This is the same general approach as cached-MP3 decoder warming,
/// but avoids adding any model generation or network request.
class DualJustAudioWaveOutput implements PreloadableOfflineWaveOutput {
  DualJustAudioWaveOutput({WaveDecoder Function()? decoderFactory})
      : _primary = JustAudioWaveOutput(
            decoder: (decoderFactory ?? JustAudioWaveDecoder.new)()),
        _secondary = JustAudioWaveOutput(
            decoder: (decoderFactory ?? JustAudioWaveDecoder.new)());

  final JustAudioWaveOutput _primary;
  final JustAudioWaveOutput _secondary;
  JustAudioWaveOutput? _active;
  JustAudioWaveOutput? _preparedSlot;
  String? _preparedFile;
  Future<void>? _preparing;
  Future<void>? _disposeFuture;
  int _revision = 0;
  bool _disposed = false;

  @override
  Future<void> prepareNext(String wavFile) async {
    if (_disposed || _active == null) return;
    final previous = _preparedFile;
    if (previous != null) {
      if (previous == wavFile) await _preparing;
      return; // One ahead, never unbounded decoder preloading.
    }
    final target = identical(_active, _primary) ? _secondary : _primary;
    final version = _revision;
    _preparedFile = wavFile;
    _preparedSlot = target;
    final task = target.prepare(wavFile);
    _preparing = task;
    try {
      await task;
    } catch (_) {
      if (version == _revision &&
          identical(_preparedSlot, target) &&
          _preparedFile == wavFile) {
        _preparedFile = null;
        _preparedSlot = null;
        _preparing = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> discardNext() {
    final target = _preparedSlot;
    _preparedFile = null;
    _preparedSlot = null;
    _preparing = null;
    if (target == null) return Future<void>.value();
    // Its own native Stop is serialized behind a pending setFilePath.
    // The active audio decoder is never interrupted here.
    return target.stop();
  }

  @override
  Future<void> play(String wavFile) async {
    if (_disposed) throw StateError('Offline audio output disposed');
    final version = _revision;
    var target = _active ?? _primary;
    final warmed = _preparedSlot;
    if (warmed != null && _preparedFile == wavFile) {
      final preparing = _preparing;
      try {
        if (preparing != null) await preparing;
      } catch (_) {
        // A failed optional preload is not a fatal audible playback.
        // The requested clip can load on the current primary decoder.
      }
      if (_disposed || version != _revision) return;
      if (_preparedFile == wavFile && identical(_preparedSlot, warmed)) {
        target = warmed;
        _preparedFile = null;
        _preparedSlot = null;
        _preparing = null;
      }
    } else if (warmed != null) {
      // Incorrect speculation: invalidate it. Its decoder's Stop will be
      // chained AFTER its own load; do not wait on idle native work just
      // to start an audible clip on the other decoder.
      _preparedFile = null;
      _preparedSlot = null;
      _preparing = null;
      unawaited(warmed.stop().catchError((Object _) {
        // Dispose/Stop also wait for the physical decoder's operations.
      }));
    }
    if (_disposed || version != _revision) return;
    _active = target;
    await target.play(wavFile);
  }

  @override
  Future<void> stop() {
    _revision++;
    _preparedFile = null;
    _preparedSlot = null;
    _preparing = null;
    _active = null;
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    // Stop both physical decoders before the engine may delete their
    // private WAVs; a slow second load cannot be allowed to outlive Stop.
    return Future.wait<void>([_primary.stop(), _secondary.stop()]).then((_) {});
  }

  @override
  Future<void> dispose() {
    final previous = _disposeFuture;
    if (previous != null) return previous;
    _disposed = true;
    _revision++;
    _preparedFile = null;
    _preparedSlot = null;
    _preparing = null;
    _active = null;
    // Decoder disposal is serialized behind any unfinished file loads.
    return _disposeFuture = Future.wait<void>(
        [_primary.dispose(), _secondary.dispose()]).then((_) {});
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
class SherpaVitsSpeechEngine implements SpeechEngine, OfflineAheadSpeechEngine, OfflineVoiceDiagnosticsProvider {
  static const providerId = 'sherpa-vits';

  SherpaVitsSpeechEngine({
    required this.pack,
    this.dataDir = '',
    OfflineWaveSynthesizer? synthesizer,
    VitsWaveJob Function(VitsWaveRequest)? jobFactory,
    VitsPersistentSession Function(VitsSessionModel)? sessionFactory,
    OfflineWaveOutput? output,
    Future<Directory> Function()? temporaryDirectory,
    OfflineWavCleanup? wavCleanup,
    Future<int> Function(Directory tempRoot)? abandonedWavRecovery,
    bool? validateNativeWaveOutput,
  })  : _validateNativeWaveOutput = validateNativeWaveOutput ??
            (synthesizer == null &&
             jobFactory == null &&
             sessionFactory == null),
        _wavCleanup = wavCleanup ?? OfflineWavCleanup(),
        _abandonedWavRecovery =
            abandonedWavRecovery ?? OfflineWavSession.recoverAbandoned,
        _synthesizer = synthesizer,
        _jobFactory = jobFactory ?? VitsWaveJob.new,
        _useLegacyJobs = jobFactory != null,
        _sessionFactory = sessionFactory ?? VitsPersistentSession.new,
        _output = output ?? DualJustAudioWaveOutput(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    pack.manifest.validate();
  }

  final InstalledOfflineVoicePack pack;
  final String dataDir;
  /// Optional mock synthesizer; production uses a cancellable isolate job.
  final OfflineWaveSynthesizer? _synthesizer;
  final VitsWaveJob Function(VitsWaveRequest) _jobFactory;
  final bool _useLegacyJobs;
  final VitsPersistentSession Function(VitsSessionModel) _sessionFactory;
  VitsPersistentSession? _nativeSession;
  VitsWaveJob? _nativeJob;
  _PreparedWave? _prepared;
  Future<void>? _currentSynthesisReady;
  final OfflineWaveOutput _output;
  final Future<Directory> Function() _temporaryDirectory;
  final OfflineWavCleanup _wavCleanup;
  /// Injected in tests to simulate slow filesystem recovery. Production
  /// recovery retains OfflineWavSession's bounded marker/lease safety checks.
  final Future<int> Function(Directory tempRoot) _abandonedWavRecovery;
  Future<void>? _backgroundWavRecovery;
  // In production every completed sherpa WAV must pass bounded PCM
  // structural inspection BEFORE any decoder is allowed to load it.
  // Synthetic injection seams disable this by default (they often write
  // intentionally fake WAVs), but tests may explicitly opt in.
  final bool _validateNativeWaveOutput;
  Future<OfflineWavSession>? _wavSessionOpening;
  int _activeWaveJobs = 0;
  Completer<void> _allWaveJobsEnded = Completer<void>()..complete();

  void _beginWaveJob() {
    if (_activeWaveJobs++ == 0) _allWaveJobsEnded = Completer<void>();
  }

  void _endWaveJob() {
    if (--_activeWaveJobs == 0 && !_allWaveJobsEnded.isCompleted) {
      _allWaveJobsEnded.complete();
    }
  }

  Future<OfflineWavSession> _session() =>
      _wavSessionOpening ??= () async {
        final temporaryRoot = await _temporaryDirectory();
        if (_disposed) throw StateError('Offline voice already disposed');
        // Create and lock OUR new session before looking for orphaned WAVs.
        // A slow system-temp scan must not delay the first utterance.
        final session = await OfflineWavSession.create(temporaryRoot);
        // Recovery is bounded and excludes every current in-process or
        // OS-leased session; it remains best-effort, never authorizes
        // touching arbitrary user files. Failures cannot block speech.
        _backgroundWavRecovery = () async {
          try {
            await _abandonedWavRecovery(temporaryRoot);
          } catch (_) {
            // Optional recovery cannot interrupt a valid narration.
          }
        }();
        return session;
      }();

  Future<Directory> _newStaging(String prefix) async {
    final session = await _session();
    if (_disposed) throw StateError('Offline voice already disposed');
    return session.directory.createTemp(prefix);
  }

  final OfflineVoiceDiagnostics _diagnostics = OfflineVoiceDiagnostics();

  @override
  OfflineVoiceStatistics get offlineVoiceStatistics {
    _diagnostics.recordPendingWaveFolders(_wavCleanup.pendingCount);
    return _diagnostics.snapshot;
  }

  int _generation = 0;
  bool _disposed = false;
  Future<void>? _disposeFuture;
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

  /// Times native/model work only. The surrounding WAV decoder handoff
  /// is measured separately; neither is guaranteed acoustic onset time.
  Future<bool> _synthesizeWave(
    String text, String wavPath, double rate, {
    bool ahead = false,
  }) async {
    final clock = Stopwatch()..start();
    final epoch = _generation;
    bool obsolete() => _disposed || epoch != _generation;
    try {
      final successful = await _synthesizeWaveNative(text, wavPath, rate);
      clock.stop();
      // Native FFI or an injected synthesizer may report SUCCESS after
      // Stop invalidates this session. Never accept or count that result.
      if (obsolete() || !successful) {
        _diagnostics.recordCancellation();
        return false;
      }
      if (_validateNativeWaveOutput) {
        try {
          // Bounded PCM inspection; never retains the audio samples.
          await inspectOfflinePcmWave(File(wavPath));
        } catch (_) {
          if (obsolete()) {
            _diagnostics.recordCancellation();
            return false;
          }
          // Only the CURRENT generation may retire its resident model.
          // A stale post-Stop validation must not cancel a newer Play.
          _nativeSession?.cancel();
          _nativeSession = null;
          throw const FormatException('Offline voice produced invalid PCM');
        }
      }
      if (obsolete()) {
        _diagnostics.recordCancellation();
        return false;
      }
      _diagnostics.recordSynthesis(
        clock.elapsed,
        ahead: ahead,
        wholeProcessRssBytes: ProcessInfo.currentRss,
      );
      return true;
    } catch (_) {
      if (obsolete()) {
        _diagnostics.recordCancellation();
        return false;
      }
      _diagnostics.recordFailure();
      rethrow;
    }
  }

  Future<bool> _synthesizeWaveNative(String text, String wavPath, double rate) async {
    final speed = (rate / 0.5).clamp(0.4, 2.0).toDouble();
    final mock = _synthesizer;
    if (mock != null) {
      await mock(
        text: text, modelPath: pack.modelPath, tokensPath: pack.tokensPath,
        dataDir: dataDir, wavPath: wavPath, speed: speed,
      );
      return true;
    }
    if (!_useLegacyJobs) {
      // An idle-timeout retires a resident model after book completion
      // without changing the player's speech generation. Start a new
      // native session only when the next explicit clip is requested.
      var session = _nativeSession;
      if (session == null || session.isClosed) {
        session = _sessionFactory(VitsSessionModel(
          modelPath: pack.modelPath,
          tokensPath: pack.tokensPath,
          dataDir: dataDir,
        ));
        _nativeSession = session;
        _diagnostics.recordModelLoad();
      }
      try {
        await session.synthesize(text: text, wavPath: wavPath, speed: speed);
        return true;
      } on VitsWaveCancelled {
        return false;
      } catch (_) {
        session.cancel();
        if (identical(_nativeSession, session)) _nativeSession = null;
        rethrow;
      }
    }
    if (_nativeJob != null) {
      throw StateError('Offline synthesis is already running');
    }
    _diagnostics.recordModelLoad();
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

  Future<void> _deleteStaging(Directory? staging) =>
      _wavCleanup.release(staging);

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
    _beginWaveJob();
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
      // Only directories from finished WAV owners may be retried.
      // No warmup if locked files have saturated the bounded queue.
      await _wavCleanup.ensureCapacity();
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      next.staging = await _newStaging('ereader-local-lookahead-');
      next.wavPath =
          next.staging!.path + Platform.pathSeparator + 'speech.wav';
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      final completed =
          await _synthesizeWave(next.text, next.wavPath!, next.rate,
              ahead: true);
      if (!completed || _disposed || token != _generation ||
          !identical(_prepared, next)) return;
      if (!await File(next.wavPath!).exists()) return;
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      // The WAV has already passed PCM validation. Preload its decoder
      // independently while the current WAV is still playing.
      if (_output is PreloadableOfflineWaveOutput) {
        await (_output as PreloadableOfflineWaveOutput)
            .prepareNext(next.wavPath!);
      }
      if (_disposed || token != _generation ||
          !identical(_prepared, next)) return;
      next.ready = true;
    } catch (_) {
      // Optional warming is best effort; audible speak reports real errors.
    } finally {
      try {
        if (!next.ready || _disposed || token != _generation ||
            !identical(_prepared, next)) {
          if (identical(_prepared, next)) _prepared = null;
          await _deleteStaging(next.staging);
        }
      } finally {
        // A rare filesystem error must not leave the OS session lease
        // held indefinitely after its last WAV owner has finished.
        _endWaveJob();
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
    _beginWaveJob();
    final token = _generation;
    final decoderHandoff = Stopwatch()..start();
    final ready = Completer<void>();
    // Synchronously publish the synthesis barrier before our first await.
    _currentSynthesisReady = ready.future;
    Directory? staging;
    String? wavPath;
    try {
      final pending = _prepared;
      if (pending != null) {
        // An earlier speculative synthesis might have been prepared for
        // a different rate, text or voice. Wait for that ONE existing
        // native job to settle before starting the actual utterance.
        // Otherwise the persistent worker reports "busy", retires its
        // model, and the requested audible phrase fails to play.
        await pending.task;
        if (_disposed || token != _generation) return;
        if (identical(_prepared, pending) &&
            pending.ready &&
            pending.matches(text, language, rate, pitch, _packVoice.key)) {
          staging = pending.staging;
          wavPath = pending.wavPath;
          _prepared = null; // Audible clip now owns this private WAV.
          _diagnostics.recordReuse();
        } else if (identical(_prepared, pending)) {
          // Discard the idle decoder's native file handle BEFORE trying
          // to delete an obsolete private WAV (Windows file locking).
          _prepared = null;
          if (_output is PreloadableOfflineWaveOutput) {
            await (_output as PreloadableOfflineWaveOutput).discardNext();
          }
          await _deleteStaging(pending.staging);
          if (_disposed || token != _generation) return;
        }
      }
      if (staging == null) {
        // Retry only previous released WAVs; fail closed if Windows still
        // holds too many rather than creating unlimited temp files.
        await _wavCleanup.ensureCapacity();
        if (_disposed || token != _generation) return;
        staging = await _newStaging('ereader-local-tts-');
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
      decoderHandoff.stop();
      _diagnostics.recordHandoff(decoderHandoff.elapsed);
      await _output.play(wavPath);
    } finally {
      if (!ready.isCompleted) ready.complete();
      if (identical(_currentSynthesisReady, ready.future)) {
        _currentSynthesisReady = null;
      }
      try {
        await _deleteStaging(staging);
      } finally {
        _endWaveJob();
      }
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _nativeSession?.cancel();
    _nativeSession = null;
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
      // Only after native output Stop; never delay issuing audible Stop.
      await _wavCleanup.retryPending(maxAttempts: 2);
    }
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  /// One in-flight disposal for every caller. A second Dispose must NOT
  /// report success until the same native output/worker cleanup settles.
  Future<void> _disposeOnce() async {
    _disposed = true;
    _generation++;
    _nativeSession?.cancel();
    _nativeSession = null;
    _nativeJob?.cancel();
    _nativeJob = null;
    final pending = _prepared;
    _prepared = null;
    // Native output is disposed before private WAVs are reclaimed. All
    // callers share this Future, including any native failure.
    try {
      await _output.dispose();
    } finally {
      try {
        if (pending != null && pending.ready) {
          await _deleteStaging(pending.staging);
        }
      } finally {
        // A native call may outlive Dispose after cancellation. Keep the
        // session OS lease until the LAST WAV owner finishes its finalizer.
        Future<void> finishSession() async {
          await _allWaveJobsEnded.future;
          try {
            await _wavCleanup.retryPending(
                maxAttempts: _wavCleanup.maxPending);
          } finally {
            // Even when cleanup fails, the OS lease must ultimately be
            // released so a later app launch can retry remaining WAVs.
            final opening = _wavSessionOpening;
            if (opening != null) {
              try {
                final session = await opening;
                await session.close();
              } on FileSystemException {
                // Locked folders remain marked for a later guarded scan.
              } on StateError {
                // Dispose may have cancelled session initialization.
              }
            }
          }
        }

        if (_activeWaveJobs == 0) {
          await finishSession();
        } else {
          // Do not hang the reader UI on native FFI which ignores cancel.
          // A later explicit Dispose still shares this completed request;
          // cleanup continues and holds the lease until all WAVs end.
          unawaited(finishSession().catchError((Object _) {
            // Never expose private paths or resurrect stale audio.
          }));
        }
      }
    }
  }
}
