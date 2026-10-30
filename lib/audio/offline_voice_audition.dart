import 'dart:async';
import 'dart:convert';

import '../data/offline_voice_pack.dart';
import 'offline_voice_diagnostics.dart';
import 'speech_engine.dart';
import 'sherpa_vits_engine.dart';
import 'system_voice_audition.dart';

typedef OfflineVoicePackLoader =
    Future<InstalledOfflineVoicePack> Function(String packId);
typedef OfflineVoiceAuditionEngineFactory =
    SpeechEngine Function(InstalledOfflineVoicePack pack);

/// Use the SAME fixed public phrase as the system voice preview. No book
/// passages, private paths, API keys or user text enter this controller.
String? offlineVoiceSampleText(String locale) =>
    systemVoiceSampleText(locale);

enum OfflineVoicePreviewOutcome { completed, cancelled, failed }

/// Same public demonstration phrase, synthesized twice by ONE engine.
/// Wall times include audio playback and cleanup, so they are NOT
/// interchangeable with native WAV generation / audible onset.
class OfflineVoiceColdWarmComparison {
  const OfflineVoiceColdWarmComparison({
    required this.firstSpeechWallMs,
    required this.secondSpeechWallMs,
    this.firstSynthesisPathMs,
    this.secondSynthesisPathMs,
    this.firstNativeGenerationMs,
    this.secondNativeGenerationMs,
    this.reusedNativeModel,
  });

  final int firstSpeechWallMs;
  final int secondSpeechWallMs;
  final int? firstSynthesisPathMs;
  final int? secondSynthesisPathMs;
  final int? firstNativeGenerationMs;
  final int? secondNativeGenerationMs;
  /// Null for non-diagnostic TTS, true only if counter evidence confirms
  /// one model load across exactly two successive syntheses.
  final bool? reusedNativeModel;
}

/// An in-memory, per-preview performance snapshot. Timing is monotonic.
/// Verification includes a full SHA-256 rehash; voice setup is only the
/// chooseVoice call (NOT necessarily model load). Speech wall-clock time
/// includes synthesis, decoder startup, audio playback and WAV cleanup.
/// Native synthesis/handoff are available only from diagnostic engines.
///
/// No source text, filenames, audio, model paths or telemetry are stored.
class OfflineVoicePreviewReport {
  const OfflineVoicePreviewReport({
    required this.packId,
    required this.outcome,
    required this.totalMs,
    this.verificationMs,
    this.voiceSetupMs,
    this.speechWallMs,
    this.nativeSynthesisMs,
    this.nativeGenerationMs,
    this.workerReadyMs,
    this.nativeModelInitializationMs,
    this.decoderHandoffMs,
    this.wholeProcessRssMiB,
    this.stopAndDisposeMs,
    this.coldWarmComparison,
  });

  final String packId;
  final OfflineVoicePreviewOutcome outcome;
  final int totalMs;
  final int? verificationMs;
  final int? voiceSetupMs;
  final int? speechWallMs;
  /// Caller-side synthesis path; first clip includes worker startup
  /// and model initialization. Do NOT add it to native model load time.
  final int? nativeSynthesisMs;
  /// Worker-local generate + WAV writing, excluding model setup/playback.
  final int? nativeGenerationMs;
  /// From worker creation through ready handshake, including isolate spawn.
  final int? workerReadyMs;
  /// Worker-local time to initialize sherpa bindings and the ONNX model.
  final int? nativeModelInitializationMs;
  final int? decoderHandoffMs;
  /// Whole app process RSS snapshot, NOT memory attributable to this voice.
  final int? wholeProcessRssMiB;
  final int? stopAndDisposeMs;
  final OfflineVoiceColdWarmComparison? coldWarmComparison;

  OfflineVoicePreviewReport withStopAndDisposeMs(int milliseconds) =>
      OfflineVoicePreviewReport(
        packId: packId,
        outcome: outcome,
        totalMs: totalMs,
        verificationMs: verificationMs,
        voiceSetupMs: voiceSetupMs,
        speechWallMs: speechWallMs,
        nativeSynthesisMs: nativeSynthesisMs,
        nativeGenerationMs: nativeGenerationMs,
        workerReadyMs: workerReadyMs,
        nativeModelInitializationMs: nativeModelInitializationMs,
        decoderHandoffMs: decoderHandoffMs,
        wholeProcessRssMiB: wholeProcessRssMiB,
        stopAndDisposeMs: milliseconds,
        coldWarmComparison: coldWarmComparison,
      );
}

/// Timing scopes are explicit so audio playback is never mistaken
/// for native synthesis. Compare only the same fixed demo phrase.
String formatOfflineVoicePreviewReport(OfflineVoicePreviewReport report) {
  final status = switch (report.outcome) {
    OfflineVoicePreviewOutcome.completed => 'Completed',
    OfflineVoicePreviewOutcome.cancelled => 'Stopped',
    OfflineVoicePreviewOutcome.failed => 'Failed',
  };
  final fields = <String>[
    '$status preview',
    if (report.verificationMs != null)
      'SHA verification: ${report.verificationMs} ms',
    if (report.voiceSetupMs != null)
      'Voice selection: ${report.voiceSetupMs} ms',
    if (report.workerReadyMs != null)
      'Worker ready: ${report.workerReadyMs} ms',
    if (report.nativeModelInitializationMs != null)
      'Native model init: ${report.nativeModelInitializationMs} ms',
    if (report.nativeGenerationMs != null)
      'Worker WAV generation: ${report.nativeGenerationMs} ms',
    if (report.nativeSynthesisMs != null)
      'Synthesis path incl. startup: ${report.nativeSynthesisMs} ms',
    if (report.decoderHandoffMs != null)
      'WAV decoder handoff: ${report.decoderHandoffMs} ms',
    if (report.speechWallMs != null)
      'Speech incl. playback: ${report.speechWallMs} ms',
    if (report.stopAndDisposeMs != null)
      'Stop + disposal: ${report.stopAndDisposeMs} ms',
    if (report.wholeProcessRssMiB != null)
      'Whole-app RAM snapshot: ${report.wholeProcessRssMiB} MiB',
    if (report.coldWarmComparison != null) ...[
      'Cold/warm demo (same phrase twice)',
      'First incl. playback: ${report.coldWarmComparison!.firstSpeechWallMs} ms',
      'Second incl. playback: ${report.coldWarmComparison!.secondSpeechWallMs} ms',
      if (report.coldWarmComparison!.firstSynthesisPathMs != null)
        'First synthesis path: ${report.coldWarmComparison!.firstSynthesisPathMs} ms',
      if (report.coldWarmComparison!.secondSynthesisPathMs != null)
        'Second synthesis path: ${report.coldWarmComparison!.secondSynthesisPathMs} ms',
      if (report.coldWarmComparison!.firstNativeGenerationMs != null)
        'First worker WAV: ${report.coldWarmComparison!.firstNativeGenerationMs} ms',
      if (report.coldWarmComparison!.secondNativeGenerationMs != null)
        'Second worker WAV: ${report.coldWarmComparison!.secondNativeGenerationMs} ms',
      if (report.coldWarmComparison!.reusedNativeModel != null)
        report.coldWarmComparison!.reusedNativeModel!
            ? 'One native model reused'
            : 'Model reuse not confirmed',
    ],
  ];
  return fields.join(' · ');
}

/// Isolated, opt-in offline audition. A pack is re-verified on each Play;
/// Stop invalidates verification BEFORE native synthesis starts.
/// Stop and Dispose settle before another engine may start.
class OfflineVoiceAudition {
  OfflineVoiceAudition({
    required OfflineVoicePackLoader loadPack,
    OfflineVoiceAuditionEngineFactory? createEngine,
    this.onPreparedModelChanged,
  }) : _loadPack = loadPack,
       _createEngine = createEngine ?? _nativeEngine;

  final OfflineVoicePackLoader _loadPack;
  final OfflineVoiceAuditionEngineFactory _createEngine;
  /// Optional UI refresh hook; the controller never owns Flutter widgets.
  void Function()? onPreparedModelChanged;
  static const preparedLifetime = Duration(minutes: 3);
  SpeechEngine? _preparedEngine;
  String? _preparedId;
  String? _preparedFingerprint;
  Timer? _preparedExpiry;

  bool hasPreparedModel(String packId) =>
      !_disposed && _preparedId == packId && _preparedEngine != null;

  String _packFingerprint(InstalledOfflineVoicePack pack) =>
      jsonEncode(pack.manifest.toJson()) +
      '|'+ pack.modelPath + '|' + pack.tokensPath +
      '|' + (pack.phonemizerDataDir ?? '');

  SpeechEngine? _takePreparedEngine(String packId, String fingerprint) {
    final old = _preparedEngine;
    _preparedEngine = null;
    final matching = _preparedId == packId &&
        _preparedFingerprint == fingerprint;
    _preparedId = null;
    _preparedFingerprint = null;
    _preparedExpiry?.cancel();
    _preparedExpiry = null;
    if (old != null) onPreparedModelChanged?.call();
    return matching ? old : null;
  }

  Future<void> _discardPreparedEngine() async {
    final old = _preparedEngine;
    _preparedEngine = null;
    _preparedId = null;
    _preparedFingerprint = null;
    _preparedExpiry?.cancel();
    _preparedExpiry = null;
    if (old != null) {
      onPreparedModelChanged?.call();
      await old.dispose();
    }
  }

  /// Explicit-only silent preparation. Rehash before starting a native
  /// worker. A single owned engine is kept for at most three minutes,
  /// never synthesizes a phrase, and is consumed by the next Play.
  Future<void> prewarm(String packId) async {
    if (_disposed) throw StateError('Voice preview is closed');
    if (_running) throw StateError('A voice preview is already running');
    _running = true;
    final token = ++_epoch;
    final settled = Completer<void>();
    _activeSettled = settled;
    SpeechEngine? owned;
    try {
      await _stopping;
      if (_disposed || token != _epoch) return;
      await _discardPreparedEngine();
      if (_disposed || token != _epoch) return;
      final pack = await _loadPack(packId);
      if (_disposed || token != _epoch) return;
      if (pack.manifest.id != packId || pack.phonemizerDataDir == null) {
        throw const FormatException('Offline voice model is not verified');
      }
      owned = _createEngine(pack);
      _active = owned;
      if (owned is! OfflineVoiceModelPrewarmer) {
        throw UnsupportedError('Native silent model warmup is not supported');
      }
      await owned.chooseVoice(SpeechVoice(
          name: pack.manifest.id, locale: pack.manifest.locale));
      if (_disposed || token != _epoch) return;
      await (owned as OfflineVoiceModelPrewarmer).prewarmModel();
      if (_disposed || token != _epoch) return;

      _active = null;
      _preparedEngine = owned;
      _preparedId = packId;
      _preparedFingerprint = _packFingerprint(pack);
      owned = null; // Prepared cache now owns its disposal.
      _preparedExpiry = Timer(preparedLifetime, () {
        unawaited(_discardPreparedEngine().catchError((Object _) {}));
      });
      onPreparedModelChanged?.call();
    } finally {
      try {
        if (owned != null && identical(_active, owned)) {
          _active = null;
          await owned.dispose();
        }
      } finally {
        _running = false;
        if (identical(_activeSettled, settled)) _activeSettled = null;
        if (!settled.isCompleted) settled.complete();
      }
    }
  }

  static SpeechEngine _nativeEngine(InstalledOfflineVoicePack pack) =>
      SherpaVitsSpeechEngine(
        pack: pack, dataDir: pack.phonemizerDataDir!,
      );

  SpeechEngine? _active;
  Future<void> _stopping = Future<void>.value();
  int _epoch = 0;
  int _previewEpoch = 0;
  bool _running = false;
  bool _disposed = false;
  Completer<void>? _activeSettled;
  OfflineVoicePreviewReport? _lastReport;

  bool get isPlaying => _running;
  /// Last completed/cancelled/failed request, local memory only.
  OfflineVoicePreviewReport? get lastReport => _lastReport;

  /// compareColdWarm deliberately plays TWO audible public demonstrations.
  /// Use only after separate user consent; never prewarm while idle.
  Future<void> play(String packId, {bool compareColdWarm = false}) async {
    if (_disposed) throw StateError('Voice preview is closed');
    if (_running) throw StateError('A voice preview is already running');
    _running = true;
    final token = ++_epoch;
    _previewEpoch = token;
    _lastReport = null;
    final settled = Completer<void>();
    _activeSettled = settled;
    SpeechEngine? owned;
    OfflineVoiceStatistics? nativeStats;
    final total = Stopwatch()..start();
    int? verificationMs;
    int? voiceSetupMs;
    int? speechWallMs;
    OfflineVoiceColdWarmComparison? comparison;
    var failed = false;
    var cleanupFailed = false;
    var completed = false;
    try {
      await _stopping;
      if (_disposed || token != _epoch) return;

      final verification = Stopwatch()..start();
      late final InstalledOfflineVoicePack pack;
      try {
        pack = await _loadPack(packId);
      } finally {
        verification.stop();
        verificationMs = verification.elapsedMilliseconds;
      }
      if (_disposed || token != _epoch) return;
      if (pack.manifest.id != packId || pack.phonemizerDataDir == null) {
        throw const FormatException(
          'Voice pack identity or phonemizer data is unavailable',
        );
      }
      final sample = offlineVoiceSampleText(pack.manifest.locale);
      if (sample == null) {
        throw const FormatException(
          'No verified demonstration text for this language',
        );
      }
      // SHA verification is ALWAYS repeated before using resident ONNX.
      // Never reuse a worker whose manifest, hashes or verified paths changed.
      final prepared = _preparedEngine;
      final retained = _takePreparedEngine(
          packId, _packFingerprint(pack));
      if (prepared != null && retained == null) {
        await prepared.dispose();
        if (_disposed || token != _epoch) return;
      }
      owned = retained ?? _createEngine(pack);
      _active = owned;
      if (retained == null) {
        final choosing = Stopwatch()..start();
        try {
          await owned.chooseVoice(SpeechVoice(
            name: pack.manifest.id, locale: pack.manifest.locale,
          ));
        } finally {
          choosing.stop();
          voiceSetupMs = choosing.elapsedMilliseconds;
        }
      } else {
        voiceSetupMs = 0; // Already selected by the explicit warmup.
      }
      if (_disposed || token != _epoch) return;

      // Reuse the SAME engine/model for the comparison, and never make
      // a second request after Stop invalidates the generation epoch.
      final speaking = Stopwatch()..start();
      try {
        await owned.speak(
          sample,
          language: pack.manifest.locale,
          rate: 0.5,
          pitch: 1.0,
        );
        completed = token == _epoch && !_disposed;
      } finally {
        speaking.stop();
        speechWallMs = speaking.elapsedMilliseconds;
      }
      if (compareColdWarm && completed) {
        OfflineVoiceStatistics? first;
        if (owned is OfflineVoiceDiagnosticsProvider) {
          try {
            first = (owned as OfflineVoiceDiagnosticsProvider)
                .offlineVoiceStatistics;
          } catch (_) {
            // Compare wall times even when optional native metrics fail.
          }
        }
        completed = false;
        final warm = Stopwatch()..start();
        try {
          if (_disposed || token != _epoch) return;
          await owned.speak(
            sample,
            language: pack.manifest.locale,
            rate: 0.5,
            pitch: 1.0,
          );
          completed = token == _epoch && !_disposed;
        } finally {
          warm.stop();
        }
        if (completed) {
          OfflineVoiceStatistics? second;
          if (owned is OfflineVoiceDiagnosticsProvider) {
            try {
              second = (owned as OfflineVoiceDiagnosticsProvider)
                  .offlineVoiceStatistics;
            } catch (_) {
              // Native comparisons are optional; never fake a result.
            }
          }
          final successive = first != null && second != null &&
              second.syntheses == first.syntheses + 1;
          final bool? sameModel = successive && first!.modelLoads > 0
              ? first!.modelLoads == second!.modelLoads : null;
          comparison = OfflineVoiceColdWarmComparison(
            firstSpeechWallMs: speechWallMs!,
            secondSpeechWallMs: warm.elapsedMilliseconds,
            firstSynthesisPathMs: successive
                ? first!.lastSynthesisMs : null,
            secondSynthesisPathMs: successive
                ? second!.lastSynthesisMs : null,
            firstNativeGenerationMs: successive
                ? first!.lastNativeGenerationMs : null,
            secondNativeGenerationMs: successive
                ? second!.lastNativeGenerationMs : null,
            reusedNativeModel: sameModel,
          );
        }
      }
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      try {
        if (owned is OfflineVoiceDiagnosticsProvider) {
          try {
            nativeStats = (owned as OfflineVoiceDiagnosticsProvider)
                .offlineVoiceStatistics;
          } catch (_) {
            // An experimental diagnostic must not mask a native failure.
          }
        }
        // When Stop detached this engine, Stop exclusively owns disposal.
        if (owned != null && identical(_active, owned)) {
          _active = null;
          await owned.dispose();
        }
      } catch (_) {
        cleanupFailed = true;
        rethrow;
      } finally {
        total.stop();
        if (_previewEpoch == token) {
          _lastReport = OfflineVoicePreviewReport(
            packId: packId,
            coldWarmComparison: failed || cleanupFailed || !completed
                ? null : comparison,
            outcome: failed || cleanupFailed
                ? OfflineVoicePreviewOutcome.failed
                : completed ? OfflineVoicePreviewOutcome.completed
                : OfflineVoicePreviewOutcome.cancelled,
            totalMs: total.elapsedMilliseconds,
            verificationMs: verificationMs,
            voiceSetupMs: voiceSetupMs,
            speechWallMs: speechWallMs,
            nativeSynthesisMs: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastSynthesisMs,
            nativeGenerationMs: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastNativeGenerationMs,
            workerReadyMs: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastWorkerReadyMs,
            nativeModelInitializationMs: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastNativeModelInitializationMs,
            decoderHandoffMs: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastDecoderHandoffMs,
            wholeProcessRssMiB: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastWholeProcessRssMiB,
          );
        }
        _running = false;
        if (identical(_activeSettled, settled)) _activeSettled = null;
        if (!settled.isCompleted) settled.complete();
      }
    }
  }

  Future<void> stop() {
    ++_epoch;
    final previewToken = _previewEpoch;
    final warmed = _preparedEngine;
    _preparedEngine = null;
    _preparedId = null;
    _preparedFingerprint = null;
    _preparedExpiry?.cancel();
    _preparedExpiry = null;
    if (warmed != null) onPreparedModelChanged?.call();
    final engine = _active ?? warmed;
    final settled = _activeSettled?.future;
    _active = null;
    // A cancelled SHA verification has no native engine to stop, and
    // cannot block the button on disk IO. The epoch blocks model loading.
    if (engine == null) return _stopping;
    final prior = _stopping;
    final timer = Stopwatch()..start();
    return _stopping = () async {
      try {
        await prior;
        try {
          await engine.stop();
        } finally {
          try {
            // A late chooseVoice cannot race disposal of native handles.
            if (settled != null) await settled;
          } finally {
            await engine.dispose();
          }
        }
      } finally {
        timer.stop();
        if (_previewEpoch == previewToken && _lastReport != null) {
          _lastReport = _lastReport!.withStopAndDisposeMs(
              timer.elapsedMilliseconds);
        }
      }
    }();
  }

  Future<void> dispose() {
    _disposed = true;
    _preparedExpiry?.cancel();
    onPreparedModelChanged = null;
    return stop();
  }
}
