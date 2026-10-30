import 'dart:async';

import 'package:ereader/audio/offline_voice_audition.dart';
import 'package:ereader/audio/offline_voice_diagnostics.dart';
import 'package:ereader/audio/system_voice_audition.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOfflineEngine implements SpeechEngine {
  int speaks = 0;
  int stops = 0;
  int disposals = 0;
  SpeechVoice? voice;
  String? spoken;
  String? language;
  double? rate;
  double? pitch;
  Completer<void>? pending;
  Completer<void>? choiceGate;
  Completer<void>? stopGate;
  int choices = 0;
  bool choosing = false;
  bool disposedWhileChoosing = false;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [
    SpeechVoice(name: 'italian', locale: 'it-IT'),
  ];

  @override
  Future<void> chooseVoice(SpeechVoice selection) async {
    choices++;
    choosing = true;
    try {
      final gate = choiceGate;
      if (gate != null) await gate.future;
      voice = selection;
    } finally {
      choosing = false;
    }
  }

  @override
  Future<void> speak(String text, {required String language,
      required double rate, required double pitch}) async {
    speaks++;
    spoken = text;
    this.language = language;
    this.rate = rate;
    this.pitch = pitch;
    final waiting = pending;
    if (waiting != null) await waiting.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending != null && !pending!.isCompleted) pending!.complete();
    final gate = stopGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> dispose() async {
    if (choosing) disposedWhileChoosing = true;
    disposals++;
  }
}

class DiagnosticFakeOfflineEngine extends FakeOfflineEngine
    implements OfflineVoiceDiagnosticsProvider {
  final OfflineVoiceDiagnostics diagnostics = OfflineVoiceDiagnostics();

  @override
  OfflineVoiceStatistics get offlineVoiceStatistics => diagnostics.snapshot;

  @override
  Future<void> speak(String text, {required String language,
      required double rate, required double pitch}) async {
    diagnostics.recordModelLoad();
    diagnostics.recordSynthesis(const Duration(milliseconds: 47),
        ahead: false, wholeProcessRssBytes: 84 * 1024 * 1024);
    diagnostics.recordHandoff(const Duration(milliseconds: 8));
    await super.speak(text, language: language, rate: rate, pitch: pitch);
  }
}

InstalledOfflineVoicePack samplePack({String id = 'italian',
    String locale = 'it-IT', bool withPhonemizer = true}) =>
    InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: id,
        displayName: 'Local preview',
        locale: locale,
        licenseId: 'MIT',
        modelSha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        tokensSha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        phonemizerResources: withPhonemizer
            ? const [OfflineVoiceResource(
                relativePath: 'espeak-ng-data/phonemes',
                sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              )] : const [],
      ),
      modelPath: '/private/models/$id/model.onnx',
      tokensPath: '/private/models/$id/tokens.txt',
    );

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Offline preview operation did not reach expected state');
}

void main() {
  test('preview report measures real phases and native provider counters',
      () async {
    final fake = DiagnosticFakeOfflineEngine();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    expect(audition.lastReport, isNull);
    await audition.play('italian');
    final report = audition.lastReport!;
    expect(report.packId, 'italian');
    expect(report.outcome, OfflineVoicePreviewOutcome.completed);
    expect(report.verificationMs, greaterThanOrEqualTo(0));
    expect(report.voiceSetupMs, greaterThanOrEqualTo(0));
    expect(report.speechWallMs, greaterThanOrEqualTo(0));
    expect(report.totalMs, greaterThanOrEqualTo(report.speechWallMs!));
    expect(report.nativeSynthesisMs, 47);
    expect(report.decoderHandoffMs, 8);
    expect(report.wholeProcessRssMiB, 84);
    expect(report.stopAndDisposeMs, isNull);
    final text = formatOfflineVoicePreviewReport(report);
    expect(text, contains('Native synthesis: 47 ms'));
    expect(text, contains('WAV decoder handoff: 8 ms'));
    expect(text, contains('Whole-app RAM snapshot: 84 MiB'));
    expect(text, isNot(contains('model.onnx')));
    await audition.dispose();
  });

  test('Stop captures elapsed disposal and labels cancellation, not success',
      () async {
    final fake = DiagnosticFakeOfflineEngine()
      ..pending = Completer<void>()
      ..stopGate = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final work = audition.play('italian');
    await until(() => fake.speaks == 1);
    final stopping = audition.stop();
    await until(() => fake.stops == 1);
    expect(audition.lastReport, isNull);
    fake.stopGate!.complete();
    await Future.wait([work, stopping]);
    final report = audition.lastReport!;
    expect(report.outcome, OfflineVoicePreviewOutcome.cancelled);
    expect(report.stopAndDisposeMs, greaterThanOrEqualTo(0));
    expect(report.speechWallMs, greaterThanOrEqualTo(0));
    expect(report.nativeSynthesisMs, 47);
    expect(formatOfflineVoicePreviewReport(report),
        contains('Stop + disposal:'));
    await audition.dispose();
  });

  test('cancelled SHA verification has no invented native timing',
      () async {
    final verification = Completer<InstalledOfflineVoicePack>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) => verification.future,
      createEngine: (_) => FakeOfflineEngine(),
    );
    final reading = audition.play('italian');
    await audition.stop();
    verification.complete(samplePack());
    await reading;
    final report = audition.lastReport!;
    expect(report.outcome, OfflineVoicePreviewOutcome.cancelled);
    expect(report.verificationMs, greaterThanOrEqualTo(0));
    expect(report.voiceSetupMs, isNull);
    expect(report.nativeSynthesisMs, isNull);
    expect(report.speechWallMs, isNull);
    expect(report.stopAndDisposeMs, isNull);
    await audition.dispose();
  });

  test('failed verification exposes no untrusted content in report',
      () async {
    final audition = OfflineVoiceAudition(
      loadPack: (_) async =>
          throw const FormatException('private file /home/user/secret'),
      createEngine: (_) => FakeOfflineEngine(),
    );
    await expectLater(audition.play('italian'), throwsFormatException);
    final report = audition.lastReport!;
    expect(report.outcome, OfflineVoicePreviewOutcome.failed);
    expect(report.voiceSetupMs, isNull);
    expect(report.nativeSynthesisMs, isNull);
    expect(formatOfflineVoicePreviewReport(report), isNot(contains('/home/')));
    await audition.dispose();
  });

  test('sample is a fixed local phrase, never sourced from an ebook', () async {
    final fake = FakeOfflineEngine();
    var loads = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (id) async { loads++; return samplePack(id: id); },
      createEngine: (_) => fake,
    );
    await audition.play('italian');
    expect(loads, 1);
    expect(fake.speaks, 1);
    expect(fake.spoken, offlineVoiceSampleText('it-IT'));
    expect(fake.spoken, contains('voce italiana'));
    expect(fake.voice!.name, 'italian');
    expect(fake.language, 'it-IT');
    expect(fake.rate, 0.5);
    expect(fake.pitch, 1);
    expect(fake.disposals, 1);
    await audition.dispose();
  });

  test('Stop during pack verification prevents all native audio', () async {
    final verification = Completer<InstalledOfflineVoicePack>();
    var creations = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) => verification.future,
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    final requested = audition.play('italian');
    await audition.stop();
    verification.complete(samplePack());
    await requested;
    expect(creations, 0);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
  });

  test('Stop cancels speech and releases exactly one native engine',
      () async {
    final fake = FakeOfflineEngine()..pending = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final requested = audition.play('italian');
    // Allow the Future to cross pack-load and voice selection.
    await Future<void>.delayed(Duration.zero);
    expect(fake.speaks, 1);
    await audition.stop();
    await requested;
    expect(fake.stops, 1);
    expect(fake.disposals, 1);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
    expect(fake.disposals, 1);
  });

  test('Stop during native voice choice waits to dispose the ONNX engine',
      () async {
    final fake = FakeOfflineEngine()..choiceGate = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final running = audition.play('italian');
    await until(() => fake.choices == 1);
    final stopping = audition.stop();
    await until(() => fake.stops == 1);
    expect(fake.disposals, 0,
        reason: 'Native voice choice still owns the model');
    expect(fake.disposedWhileChoosing, isFalse);
    fake.choiceGate!.complete();
    await Future.wait([running, stopping]);
    expect(fake.speaks, 0,
        reason: 'A cancelled preview cannot start synthesis');
    expect(fake.disposals, 1);
    expect(fake.disposedWhileChoosing, isFalse);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
  });

  test('next offline audition awaits previous native Stop disposal',
      () async {
    final firstEngine = FakeOfflineEngine()
      ..pending = Completer<void>()
      ..stopGate = Completer<void>();
    final secondEngine = FakeOfflineEngine();
    var creations = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => creations++ == 0 ? firstEngine : secondEngine,
    );
    final first = audition.play('italian');
    await until(() => firstEngine.speaks == 1);
    final stopping = audition.stop();
    await until(() => firstEngine.stops == 1);
    await until(() => !audition.isPlaying);
    expect(firstEngine.disposals, 0);
    final second = audition.play('italian');
    await Future<void>.delayed(Duration.zero);
    expect(creations, 1,
        reason: 'No second native model before Stop/dispose settles');
    expect(secondEngine.speaks, 0);
    firstEngine.stopGate!.complete();
    await Future.wait([stopping, first, second]);
    expect(firstEngine.disposals, 1);
    expect(secondEngine.speaks, 1);
    expect(secondEngine.disposals, 1);
    await audition.dispose();
  });

  test('system and local neural preview use identical public text',
      () {
    for (final locale in ['it-IT', 'en-GB', 'fr-FR', 'es-ES',
        'de-DE', 'pt-BR', 'nl-NL', 'pl-PL', 'sv-SE', 'ru-RU',
        'ja-JP', 'zh-CN']) {
      expect(offlineVoiceSampleText(locale),
          systemVoiceSampleText(locale));
      expect(offlineVoiceSampleText(locale), isNotNull);
    }
    expect(offlineVoiceSampleText('xx-XX'), isNull);
  });

  test('wrong model identity or missing phonemizer cannot reach native FFI',
      () async {
    var creations = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(id: 'different'),
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    await expectLater(audition.play('italian'), throwsFormatException);
    expect(creations, 0);
    await audition.dispose();
    final missing = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(withPhonemizer: false),
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    await expectLater(missing.play('italian'), throwsFormatException);
    expect(creations, 0);
    await missing.dispose();
  });

  test('unsupported language never synthesizes a mismatched sample',
      () async {
    var creations = 0;
    expect(offlineVoiceSampleText('xx-XX'), isNull);
    expect(offlineVoiceSampleText('en-GB'), isNotNull);
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(locale: 'xx-XX'),
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    await expectLater(audition.play('italian'), throwsFormatException);
    expect(creations, 0);
    await audition.dispose();
  });

  test('concurrent preview is rejected, not allowed to synthesize twice',
      () async {
    final fake = FakeOfflineEngine()..pending = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final first = audition.play('italian');
    await expectLater(audition.play('italian'), throwsStateError);
    await audition.stop();
    await first;
    expect(fake.speaks, lessThanOrEqualTo(1));
    await audition.dispose();
  });
}
