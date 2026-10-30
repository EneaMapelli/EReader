import 'package:ereader/audio/offline_voice_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty metrics are well defined and contain numbers only', () {
    final stats = OfflineVoiceDiagnostics().snapshot;
    expect(stats.modelLoads, 0);
    expect(stats.syntheses, 0);
    expect(stats.averageSynthesisMs, 0);
    expect(stats.p95SynthesisMs, 0);
    expect(stats.lastWholeProcessRssMiB, 0);
  });

  test('independent native and speculative counts remain consistent', () {
    final log = OfflineVoiceDiagnostics();
    log.recordModelLoad();
    log.recordSynthesis(
      const Duration(milliseconds: 32),
      ahead: false,
      wholeProcessRssBytes: 100 * 1024 * 1024,
    );
    log.recordSynthesis(
      const Duration(milliseconds: 68),
      ahead: true,
      wholeProcessRssBytes: 104 * 1024 * 1024,
    );
    log.recordReuse();
    log.recordFailure();
    log.recordCancellation();
    log.recordHandoff(const Duration(milliseconds: 17));

    final stats = log.snapshot;
    expect(stats.modelLoads, 1);
    expect(stats.syntheses, 2);
    expect(stats.aheadSyntheses, 1);
    expect(stats.warmedWaveReuses, 1);
    expect(stats.failures, 1);
    expect(stats.cancelledSyntheses, 1);
    expect(stats.lastSynthesisMs, 68);
    expect(stats.averageSynthesisMs, 50);
    expect(stats.p95SynthesisMs, 68);
    expect(stats.lastDecoderHandoffMs, 17);
    expect(stats.lastWholeProcessRssMiB, 104);
  });

  test('startup metrics reset on a new native model load', () {
    final log = OfflineVoiceDiagnostics();
    expect(log.snapshot.lastWorkerReadyMs, isNull);
    expect(log.snapshot.lastNativeModelInitializationMs, isNull);
    log.recordModelLoad();
    log.recordModelStartup(
      workerReadyMs: 120,
      nativeModelInitializationMs: 84,
    );
    final cold = log.snapshot;
    expect(cold.modelLoads, 1);
    expect(cold.lastWorkerReadyMs, 120);
    expect(cold.lastNativeModelInitializationMs, 84);
    log.recordModelStartup(
      workerReadyMs: -1, nativeModelInitializationMs: -10);
    expect(log.snapshot.lastWorkerReadyMs, 120,
        reason: 'Invalid metrics cannot overwrite measurements');
    log.recordModelLoad();
    expect(log.snapshot.modelLoads, 2);
    expect(log.snapshot.lastWorkerReadyMs, isNull,
        reason: 'A new model is not yet initialized');
    expect(log.snapshot.lastNativeModelInitializationMs, isNull);
    expect(cold.lastNativeModelInitializationMs, 84,
        reason: 'Older numeric snapshot remains immutable');
    log.recordModelStartup(workerReadyMs: 90);
    expect(log.snapshot.lastWorkerReadyMs, 90);
    expect(log.snapshot.lastNativeModelInitializationMs, isNull);
  });

  test('P95 retains only the last 64 samples, without unbounded history', () {
    final log = OfflineVoiceDiagnostics();
    log.recordSynthesis(
      const Duration(milliseconds: 5000),
      ahead: false,
      wholeProcessRssBytes: 0,
    );
    for (var i = 1; i <= 64; i++) {
      log.recordSynthesis(
        Duration(milliseconds: i),
        ahead: false,
        wholeProcessRssBytes: 0,
      );
    }
    final stats = log.snapshot;
    expect(stats.syntheses, 65);
    expect(stats.p95SynthesisMs, 61);
    expect(stats.lastSynthesisMs, 64);
  });

  test('snapshots do not change when more samples arrive', () {
    final log = OfflineVoiceDiagnostics();
    log.recordSynthesis(
      const Duration(milliseconds: 5),
      ahead: false,
      wholeProcessRssBytes: -1,
    );
    final old = log.snapshot;
    log.recordSynthesis(
      const Duration(milliseconds: 25),
      ahead: true,
      wholeProcessRssBytes: 0,
    );
    expect(old.syntheses, 1);
    expect(old.lastSynthesisMs, 5);
    expect(log.snapshot.syntheses, 2);
  });
}
