/// Numbers only: no book text, local paths, audio samples, credentials,
/// speaker IDs, titles or network telemetry are retained in this model.
///
/// Values are per engine instance. RAM means a snapshot of the WHOLE Dart /
/// Flutter process's resident set, not model-attributable memory or a peak.
class OfflineVoiceStatistics {
  const OfflineVoiceStatistics({
    required this.modelLoads,
    this.lastWorkerReadyMs,
    this.lastNativeModelInitializationMs,
    required this.syntheses,
    required this.aheadSyntheses,
    required this.warmedWaveReuses,
    required this.failures,
    required this.cancelledSyntheses,
    required this.lastSynthesisMs,
    required this.averageSynthesisMs,
    required this.p95SynthesisMs,
    required this.lastDecoderHandoffMs,
    required this.lastWholeProcessRssMiB,
    required this.pendingWaveFolders,
  });

  final int modelLoads;
  /// Wall time from persistent session creation to ready worker; includes
  /// isolate spawn, model load and message scheduling. Null if unmeasured.
  final int? lastWorkerReadyMs;
  /// Worker-local native sherpa bindings + ONNX construction. Null when
  /// using an older/test worker or before any timed ready handshake.
  final int? lastNativeModelInitializationMs;
  final int syntheses;
  final int aheadSyntheses;
  final int warmedWaveReuses;
  final int failures;
  final int cancelledSyntheses;
  final int lastSynthesisMs;
  final int averageSynthesisMs;
  /// Nearest rank among the LAST 64 syntheses, not a population estimate.
  final int p95SynthesisMs;
  /// Start of speak() until handing the WAV path to the native decoder.
  /// This is NOT the measured first audible sample.
  final int lastDecoderHandoffMs;
  final int lastWholeProcessRssMiB;
  /// WAV staging folders whose removal is deferred after native file locks.
  final int pendingWaveFolders;
}

/// Bounded, in-memory counters only. Exposing a snapshot does not write
/// a file, change provider permissions, or trigger a billable request.
class OfflineVoiceDiagnostics {
  static const int recentSampleLimit = 64;
  final List<int> _recentMs = <int>[];

  int _modelLoads = 0;
  int? _lastWorkerReadyMs;
  int? _lastNativeModelInitializationMs;
  int _syntheses = 0;
  int _aheadSyntheses = 0;
  int _reused = 0;
  int _failures = 0;
  int _cancelled = 0;
  int _lastMs = 0;
  int _lastHandoffMs = 0;
  int _rssMiB = 0;
  int _sumMs = 0;
  int _pendingWaveFolders = 0;

  void recordPendingWaveFolders(int count) {
    if (count >= 0) _pendingWaveFolders = count;
  }

  void recordModelLoad() {
    _modelLoads++;
    // A new model has not necessarily finished initializing yet. Never
    // show a previous model's startup as the new model's measurement.
    _lastWorkerReadyMs = null;
    _lastNativeModelInitializationMs = null;
  }

  void recordModelStartup({
    int? workerReadyMs,
    int? nativeModelInitializationMs,
  }) {
    if (workerReadyMs != null && workerReadyMs >= 0) {
      _lastWorkerReadyMs = workerReadyMs;
    }
    if (nativeModelInitializationMs != null &&
        nativeModelInitializationMs >= 0) {
      _lastNativeModelInitializationMs = nativeModelInitializationMs;
    }
  }

  void recordSynthesis(
    Duration elapsed, {
    required bool ahead,
    required int wholeProcessRssBytes,
  }) {
    final ms = elapsed.inMilliseconds < 0 ? 0 : elapsed.inMilliseconds;
    _syntheses++;
    if (ahead) _aheadSyntheses++;
    _lastMs = ms;
    _sumMs += ms;
    _recentMs.add(ms);
    if (_recentMs.length > recentSampleLimit) _recentMs.removeAt(0);
    // ProcessInfo.currentRss is a point-in-time whole-process measurement.
    if (wholeProcessRssBytes >= 0) {
      _rssMiB = wholeProcessRssBytes ~/ (1024 * 1024);
    }
  }

  void recordFailure() => _failures++;
  void recordCancellation() => _cancelled++;
  void recordReuse() => _reused++;
  void recordHandoff(Duration elapsed) {
    _lastHandoffMs =
        elapsed.inMilliseconds < 0 ? 0 : elapsed.inMilliseconds;
  }

  OfflineVoiceStatistics get snapshot {
    final sorted = _recentMs.toList()..sort();
    final p95Index = sorted.isEmpty
        ? 0 : ((sorted.length * 95 + 99) ~/ 100) - 1;
    return OfflineVoiceStatistics(
      modelLoads: _modelLoads,
      lastWorkerReadyMs: _lastWorkerReadyMs,
      lastNativeModelInitializationMs: _lastNativeModelInitializationMs,
      syntheses: _syntheses,
      aheadSyntheses: _aheadSyntheses,
      warmedWaveReuses: _reused,
      failures: _failures,
      cancelledSyntheses: _cancelled,
      lastSynthesisMs: _lastMs,
      averageSynthesisMs: _syntheses == 0 ? 0 : _sumMs ~/ _syntheses,
      p95SynthesisMs: sorted.isEmpty ? 0 : sorted[p95Index],
      lastDecoderHandoffMs: _lastHandoffMs,
      lastWholeProcessRssMiB: _rssMiB,
      pendingWaveFolders: _pendingWaveFolders,
    );
  }
}
