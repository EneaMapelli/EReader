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
  bool failDispose = false;

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
    if (failDispose) throw StateError('private native cleanup path');
  }
}

class PreparedVoiceFakeEngine extends FakeOfflineEngine
    implements OfflineVoiceModelPrewarmer {
  int prepares = 0;
  Completer<void>? prepareGate;

  @override
  Future<void> prewarmModel() async {
    prepares++;
    final pending = prepareGate;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> stop() async {
    if (prepareGate != null && !prepareGate!.isCompleted) {
      prepareGate!.complete();
    }
    await super.stop();
  }
}

class _FakePreparedExpiry implements Timer {
  _FakePreparedExpiry(this.delay, this.action);
  final Duration delay;
  final void Function() action;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    action();
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
    diagnostics.recordModelStartup(
      workerReadyMs: 94,
      nativeModelInitializationMs: 63,
    );
    diagnostics.recordNativeGeneration(
        const Duration(milliseconds: 21));
    diagnostics.recordSynthesis(const Duration(milliseconds: 47),
        ahead: false, wholeProcessRssBytes: 84 * 1024 * 1024);
    diagnostics.recordHandoff(const Duration(milliseconds: 8));
    await super.speak(text, language: language, rate: rate, pitch: pitch);
  }
}

class BenchmarkFakeOfflineEngine extends FakeOfflineEngine
    implements OfflineVoiceDiagnosticsProvider {
  final OfflineVoiceDiagnostics diagnostics = OfflineVoiceDiagnostics();
  final List<String> utterances = <String>[];
  Completer<void>? secondGate;
  bool reloadForSecond = false;

  @override
  OfflineVoiceStatistics get offlineVoiceStatistics => diagnostics.snapshot;

  @override
  Future<void> speak(String text, {required String language,
      required double rate, required double pitch}) async {
    final first = utterances.isEmpty;
    utterances.add(text);
    if (first || reloadForSecond) {
      diagnostics.recordModelLoad();
      diagnostics.recordModelStartup(
        workerReadyMs: 85, nativeModelInitializationMs: 51);
    }
    diagnostics.recordNativeGeneration(
        Duration(milliseconds: first ? 60 : 19));
    diagnostics.recordSynthesis(
      Duration(milliseconds: first ? 120 : 41),
      ahead: false,
      wholeProcessRssBytes: 88 * 1024 * 1024,
    );
    await super.speak(text, language: language, rate: rate, pitch: pitch);
    if (!first && secondGate != null) await secondGate!.future;
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (secondGate != null && !secondGate!.isCompleted) {
      secondGate!.complete();
    }
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
  test('explicit silent warmup is reused only after another verification',
      () async {
    final engine = PreparedVoiceFakeEngine();
    var reads = 0;
    var created = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async {
        reads++;
        return samplePack();
      },
      createEngine: (_) {
        created++;
        return engine;
      },
    );
    await audition.prewarm('italian');
    expect(audition.hasPreparedModel('italian'), isTrue);
    expect(engine.prepares, 1);
    expect(engine.speaks, 0,
        reason: 'Native model-only preparation must not generate speech');
    expect(engine.disposals, 0);
    await audition.play('italian');
    expect(reads, 2, reason: 'Always rehash pack before reuse');
    expect(created, 1);
    expect(engine.prepares, 1);
    expect(engine.speaks, 1);
    expect(engine.disposals, 1);
    expect(audition.hasPreparedModel('italian'), isFalse);
    await audition.dispose();
  });

  test('pack metadata change forbids reuse of a prepared worker',
      () async {
    final created = <PreparedVoiceFakeEngine>[];
    var reads = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async {
        reads++;
        return samplePack(locale: reads == 1 ? 'it-IT' : 'en-US');
      },
      createEngine: (_) {
        final engine = PreparedVoiceFakeEngine();
        created.add(engine);
        return engine;
      },
    );
    await audition.prewarm('italian');
    await audition.play('italian');
    expect(reads, 2);
    expect(created, hasLength(2));
    expect(created.first.disposals, 1);
    expect(created.first.speaks, 0);
    expect(created.last.speaks, 1);
    expect(created.last.disposals, 1);
    expect(audition.hasPreparedModel('italian'), isFalse);
    await audition.dispose();
  });

  test('prepared model is released after 3 minutes without audio',
      () async {
    final timers = <_FakePreparedExpiry>[];
    final engine = PreparedVoiceFakeEngine();
    var changes = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => engine,
      onPreparedModelChanged: () { changes++; },
      preparedTimerScheduler: (delay, action) {
        final timer = _FakePreparedExpiry(delay, action);
        timers.add(timer);
        return timer;
      },
    );
    await audition.prewarm('italian');
    expect(timers.single.delay, OfflineVoiceAudition.preparedLifetime);
    expect(audition.hasPreparedModel('italian'), isTrue);
    expect(engine.disposals, 0);
    timers.single.fire();
    await until(() => engine.disposals == 1);
    expect(audition.hasPreparedModel('italian'), isFalse);
    expect(engine.prepares, 1);
    expect(engine.speaks, 0);
    expect(changes, 2, reason: 'UI observes warm and expired transitions');
    await audition.dispose();
  });

  test('Stop cancels ONNX warmup still loading', () async {
    final engine = PreparedVoiceFakeEngine()
      ..prepareGate = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => engine,
    );
    final warming = audition.prewarm('italian');
    await until(() => engine.prepares == 1);
    final stopping = audition.stop();
    await Future.wait([warming, stopping]);
    expect(engine.stops, 1);
    expect(engine.disposals, 1);
    expect(engine.speaks, 0);
    expect(audition.hasPreparedModel('italian'), isFalse);
    await audition.dispose();
  });

  test('Stop releases a prepared ONNX worker without creating a WAV',
      () async {
    final engine = PreparedVoiceFakeEngine();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => engine,
    );
    await audition.prewarm('italian');
    await audition.stop();
    expect(engine.prepares, 1);
    expect(engine.speaks, 0);
    expect(engine.stops, 1);
    expect(engine.disposals, 1);
    expect(audition.hasPreparedModel('italian'), isFalse);
    await audition.dispose();
  });

  test('generic TTS engines cannot silently claim ONNX preparation',
      () async {
    final engine = FakeOfflineEngine();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => engine,
    );
    await expectLater(audition.prewarm('italian'),
        throwsUnsupportedError);
    expect(engine.speaks, 0);
    expect(engine.disposals, 1);
    expect(audition.hasPreparedModel('italian'), isFalse);
    await audition.dispose();
  });

  test('consented cold/warm comparison uses one model and fixed public text',
      () async {
    final fake = BenchmarkFakeOfflineEngine();
    var verifications = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async {
        verifications++;
        return samplePack();
      },
      createEngine: (_) => fake,
    );
    await audition.play('italian', compareColdWarm: true);
    expect(verifications, 1);
    expect(fake.speaks, 2);
    expect(fake.utterances, hasLength(2));
    expect(fake.utterances[0], offlineVoiceSampleText('it-IT'));
    expect(fake.utterances[1], fake.utterances[0]);
    expect(fake.disposals, 1);
    final report = audition.lastReport!;
    final compare = report.coldWarmComparison!;
    expect(report.outcome, OfflineVoicePreviewOutcome.completed);
    expect(compare.reusedNativeModel, isTrue);
    expect(compare.firstNativeGenerationMs, 60);
    expect(compare.secondNativeGenerationMs, 19);
    expect(compare.firstSynthesisPathMs, 120);
    expect(compare.secondSynthesisPathMs, 41);
    expect(compare.firstSpeechWallMs, greaterThanOrEqualTo(0));
    expect(compare.secondSpeechWallMs, greaterThanOrEqualTo(0));
    final label = formatOfflineVoicePreviewReport(report);
    expect(label, contains('Cold/warm demo (same phrase twice)'));
    expect(label, contains('One native model reused'));
    expect(label, contains('First worker WAV: 60 ms'));
    expect(label, contains('Second worker WAV: 19 ms'));
    expect(label, isNot(contains('/private/models/')));
    await audition.dispose();
  });

  test('Stop during first cold phrase never schedules warm phrase', () async {
    final fake = BenchmarkFakeOfflineEngine()
      ..pending = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final run = audition.play('italian', compareColdWarm: true);
    await until(() => fake.speaks == 1);
    await audition.stop();
    await run;
    expect(fake.speaks, 1);
    expect(fake.disposals, 1);
    expect(audition.lastReport?.outcome,
        OfflineVoicePreviewOutcome.cancelled);
    expect(audition.lastReport?.coldWarmComparison, isNull);
    await audition.dispose();
  });

  test('Stop during second warm phrase discards partial comparison',
      () async {
    final fake = BenchmarkFakeOfflineEngine()
      ..secondGate = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final run = audition.play('italian', compareColdWarm: true);
    await until(() => fake.speaks == 2);
    await audition.stop();
    await run;
    expect(fake.speaks, 2);
    expect(fake.disposals, 1);
    expect(audition.lastReport!.outcome,
        OfflineVoicePreviewOutcome.cancelled);
    expect(audition.lastReport!.coldWarmComparison, isNull);
    await audition.dispose();
  });

  test('benchmark refuses to claim reuse if a second model is loaded',
      () async {
    final fake = BenchmarkFakeOfflineEngine()..reloadForSecond = true;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    await audition.play('italian', compareColdWarm: true);
    expect(fake.speaks, 2);
    expect(fake.diagnostics.snapshot.modelLoads, 2);
    final report = audition.lastReport!;
    expect(report.outcome, OfflineVoicePreviewOutcome.completed);
    expect(report.coldWarmComparison?.reusedNativeModel, isFalse);
    expect(formatOfflineVoicePreviewReport(report),
        contains('Model reuse not confirmed'));
    await audition.dispose();
  });

  test('benchmark without native counters reports only observable wall times',
      () async {
    final fake = FakeOfflineEngine();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    await audition.play('italian', compareColdWarm: true);
    final result = audition.lastReport!.coldWarmComparison!;
    expect(fake.speaks, 2);
    expect(result.firstSpeechWallMs, greaterThanOrEqualTo(0));
    expect(result.secondSpeechWallMs, greaterThanOrEqualTo(0));
    expect(result.reusedNativeModel, isNull);
    expect(result.firstNativeGenerationMs, isNull);
    expect(result.secondNativeGenerationMs, isNull);
    expect(formatOfflineVoicePreviewReport(audition.lastReport!),
        isNot(contains('One native model reused')));
    await audition.dispose();
  });

  test('ordinary preview still speaks exactly once', () async {
    final fake = BenchmarkFakeOfflineEngine();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    await audition.play('italian');
    expect(fake.speaks, 1);
    expect(audition.lastReport?.coldWarmComparison, isNull);
    await audition.dispose();
  });

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
    expect(report.nativeGenerationMs, 21);
    expect(report.workerReadyMs, 94);
    expect(report.nativeModelInitializationMs, 63);
    expect(report.decoderHandoffMs, 8);
    expect(report.wholeProcessRssMiB, 84);
    expect(report.stopAndDisposeMs, isNull);
    final text = formatOfflineVoicePreviewReport(report);
    expect(text, contains('Worker ready: 94 ms'));
    expect(text, contains('Native model init: 63 ms'));
    expect(text, contains('Worker WAV generation: 21 ms'));
    expect(text, contains('Synthesis path incl. startup: 47 ms'));
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
    expect(report.nativeGenerationMs, isNull);
    expect(report.nativeModelInitializationMs, isNull);
    expect(report.workerReadyMs, isNull);
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

  test('native disposal failure never reports a successful preview',
      () async {
    final engine = FakeOfflineEngine()..failDispose = true;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => engine,
    );
    await expectLater(audition.play('italian'), throwsStateError);
    expect(engine.speaks, 1);
    expect(engine.disposals, 1);
    expect(audition.lastReport?.outcome, OfflineVoicePreviewOutcome.failed);
    expect(formatOfflineVoicePreviewReport(audition.lastReport!),
        isNot(contains('private native cleanup path')));
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
