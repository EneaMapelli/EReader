import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level gates for the optional, genuine native benchmark. These are
/// intentionally NOT a substitute for running the ONNX model on a device.
void main() {
  test('native benchmark only runs with explicit opt-in and local pack',
      () async {
    final cli = await File('tool/qualify_offline_voice.dart').readAsString();
    expect(cli, contains('--accept-native-risk'));
    expect(cli, contains('loadInstalledOfflineVoicePack('));
    expect(cli, contains('inspectOfflinePcmWave('));
    expect(cli, contains('VitsWaveJob('));
    expect(cli, contains('ProcessInfo.currentRss'));
    expect(cli, contains('realTimeFactor'));
    expect(cli, contains('timeout(_limit)'));
    expect(cli, contains('job.cancel()'));
    expect(cli, contains('staging.delete(recursive: true)'));
    expect(cli, contains("'.local-test-results'"));
    expect(cli, isNot(contains('HttpClient(')));
    expect(cli, isNot(contains('OpenAI(')));
  });

  test('PowerShell reporter only permits explicit sanitized JSON publishing',
      () async {
    final script = await File('tool/run-offline-voice-qualification.ps1')
        .readAsString();
    expect(script, contains(r'if ($PublishSummary)'));
    expect(script, contains(r'if (-not $AcceptNativeRisk)'));
    expect(script, contains('feature/m0-flutter-foundation'));
    expect(script, contains(r'$git add --'));
    expect(script, contains('offline-voice-qualification-latest.json'));
    expect(script, contains(r'$payload.samples'));
    expect(script, contains(r'$payload.status'));
    expect(script, isNot(contains('--force')));
    expect(script, isNot(contains('git add -A')));
    expect(script, isNot(contains('Invoke-WebRequest')));
    expect(script, isNot(contains('Start-BitsTransfer')));
  });

  test('real-model benchmark does not expose neural TTS in production',
      () async {
    final factory =
        await File('lib/audio/speech_engine_factory.dart').readAsString();
    expect(factory, contains("static const availableProviders = ['system',"));
    expect(factory, isNot(contains(
      "static const availableProviders = ['system', 'sherpa-vits'")));
    final report = await File('.gitignore').readAsString();
    expect(report, contains('.local-test-results/'));
  });
}
