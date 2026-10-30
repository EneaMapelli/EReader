import 'dart:async';

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
    this.decoderHandoffMs,
    this.wholeProcessRssMiB,
    this.stopAndDisposeMs,
  });

  final String packId;
  final OfflineVoicePreviewOutcome outcome;
  final int totalMs;
  final int? verificationMs;
  final int? voiceSetupMs;
  final int? speechWallMs;
  final int? nativeSynthesisMs;
  final int? decoderHandoffMs;
  /// Whole app process RSS snapshot, NOT memory attributable to this voice.
  final int? wholeProcessRssMiB;
  final int? stopAndDisposeMs;

  OfflineVoicePreviewReport withStopAndDisposeMs(int milliseconds) =>
      OfflineVoicePreviewReport(
        packId: packId,
        outcome: outcome,
        totalMs: totalMs,
        verificationMs: verificationMs,
        voiceSetupMs: voiceSetupMs,
        speechWallMs: speechWallMs,
        nativeSynthesisMs: nativeSynthesisMs,
        decoderHandoffMs: decoderHandoffMs,
        wholeProcessRssMiB: wholeProcessRssMiB,
        stopAndDisposeMs: milliseconds,
      );
}

/// Isolated, opt-in offline audition. A pack is re-verified on each Play;
/// Stop invalidates verification BEFORE native synthesis starts.
/// Stop and Dispose settle before another engine may start.
class OfflineVoiceAudition {
  OfflineVoiceAudition({
    required OfflineVoicePackLoader loadPack,
    OfflineVoiceAuditionEngineFactory? createEngine,
  }) : _loadPack = loadPack,
       _createEngine = createEngine ?? _nativeEngine;

  final OfflineVoicePackLoader _loadPack;
  final OfflineVoiceAuditionEngineFactory _createEngine;
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

  Future<void> play(String packId) async {
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
    var failed = false;
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
      owned = _createEngine(pack);
      _active = owned;
      final choosing = Stopwatch()..start();
      try {
        await owned.chooseVoice(SpeechVoice(
          name: pack.manifest.id, locale: pack.manifest.locale,
        ));
      } finally {
        choosing.stop();
        voiceSetupMs = choosing.elapsedMilliseconds;
      }
      if (_disposed || token != _epoch) return;

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
      } finally {
        total.stop();
        if (_previewEpoch == token) {
          _lastReport = OfflineVoicePreviewReport(
            packId: packId,
            outcome: failed ? OfflineVoicePreviewOutcome.failed
                : completed ? OfflineVoicePreviewOutcome.completed
                : OfflineVoicePreviewOutcome.cancelled,
            totalMs: total.elapsedMilliseconds,
            verificationMs: verificationMs,
            voiceSetupMs: voiceSetupMs,
            speechWallMs: speechWallMs,
            nativeSynthesisMs: nativeStats == null ||
                    nativeStats.syntheses == 0
                ? null : nativeStats.lastSynthesisMs,
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
    final engine = _active;
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
    return stop();
  }
}
