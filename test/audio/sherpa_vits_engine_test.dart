import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/audio/offline_wav_cleanup.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeWaveOutput implements OfflineWaveOutput {
  final playedBytes = <List<int>>[];
  final filePaths = <String>[];
  int stops = 0;
  int disposals = 0;
  Completer<void>? playGate;

  @override
  Future<void> play(String filePath) async {
    expect(await File(filePath).exists(), isTrue);
    filePaths.add(filePath);
    playedBytes.add(await File(filePath).readAsBytes());
    final gate = playGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final gate = playGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> dispose() async { disposals++; }
}

class _DeferredDisposeOutput extends _FakeWaveOutput {
  final completion = Completer<void>();
  @override
  Future<void> dispose() async {
    disposals++;
    await completion.future;
  }
}

class _FailedDisposeOutput extends _FakeWaveOutput {
  @override
  Future<void> dispose() async {
    disposals++;
    throw StateError('Native audio disposal failed');
  }
}

/// 0.25-second PCM16 mono WAV for integrity tests. No native or paid TTS.
List<int> _validPcmWav() {
  const frames = 4000;
  const rate = 16000;
  const pcmBytes = frames * 2;
  final bytes = Uint8List(44 + pcmBytes);
  final header = ByteData.sublistView(bytes);
  void tag(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }
  tag(0, 'RIFF');
  header.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, pcmBytes, Endian.little);
  return bytes;
}

void main() {
  late Directory root;
  late InstalledOfflineVoicePack pack;
  late _FakeWaveOutput output;
  late List<double> speeds;
  late List<String> texts;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-sherpa-test-');
    output = _FakeWaveOutput();
    speeds = [];
    texts = [];
    final manifest = OfflineVoicePackManifest(
      id: 'piper-test',
      displayName: 'Dummy',
      locale: 'en-US',
      licenseId: 'MIT',
      modelSha256: 'a' * 64,
      tokensSha256: 'b' * 64,
    );
    pack = InstalledOfflineVoicePack(
      manifest: manifest,
      modelPath: p.join(root.path, 'model.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> fakeSynthesize({
    required String text,
    required String modelPath,
    required String tokensPath,
    required String dataDir,
    required String wavPath,
    required double speed,
  }) async {
    expect(modelPath, pack.modelPath);
    expect(tokensPath, pack.tokensPath);
    expect(dataDir, isEmpty);
    texts.add(text);
    speeds.add(speed);
    await File(wavPath).writeAsBytes([82, 73, 70, 70]);
  }

  SherpaVitsSpeechEngine engine(
          {OfflineWaveSynthesizer? synthesizer}) =>
      SherpaVitsSpeechEngine(
        pack: pack,
        synthesizer: synthesizer ?? fakeSynthesize,
        output: output,
        temporaryDirectory: () async => root,
      );

  test('owned WAV session metadata is removed on settled Dispose',
      () async {
    final synth = engine();
    await synth.speak('One', language: 'en-US', rate: 0.5, pitch: 1);
    final sessions = await root.list().toList();
    expect(sessions, hasLength(1),
        reason: 'One live OS-leased private staging session');
    expect(sessions.single, isA<Directory>());
    await synth.dispose();
    expect(await root.list().toList(), isEmpty,
        reason: 'No stale marker/lock when every WAV was cleaned');
  });

  test('parallel Dispose callers await one native shutdown', () async {
    final blocked = _DeferredDisposeOutput();
    final synth = SherpaVitsSpeechEngine(
      pack: pack, synthesizer: fakeSynthesize,
      output: blocked, temporaryDirectory: () async => root,
    );
    await synth.speak('Once', language: 'en-US', rate: 0.5, pitch: 1);
    final first = synth.dispose();
    final second = synth.dispose();
    expect(identical(first, second), isTrue,
        reason: 'Both callers must observe the same incomplete shutdown');
    expect(blocked.disposals, 1);
    var finished = false;
    first.then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    blocked.completion.complete();
    await Future.wait([first, second]);
    expect(blocked.disposals, 1);
    expect(await root.list().toList(), isEmpty);
  });

  test('Dispose failure still releases WAV session metadata', () async {
    final broken = _FailedDisposeOutput();
    final synth = SherpaVitsSpeechEngine(
      pack: pack, synthesizer: fakeSynthesize,
      output: broken, temporaryDirectory: () async => root,
    );
    await synth.speak('One', language: 'en-US', rate: 0.5, pitch: 1);
    final disposing = synth.dispose();
    await expectLater(disposing, throwsStateError);
    expect(broken.disposals, 1);
    expect(await root.list().toList(), isEmpty,
        reason: 'OS session lease cannot leak after output failure');
    await expectLater(synth.dispose(), throwsStateError,
        reason: 'Repeated Dispose shares the original native failure');
  });

  test('offline speech exposes only installed local voice and WAV playback',
      () async {
    final synth = engine();
    final voices = await synth.listVoices();
    expect(voices, hasLength(1));
    expect(voices.single.key, 'piper-test@@en-US');
    await synth.chooseVoice(voices.single);
    await synth.speak('Local words', language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, ['Local words']);
    expect(speeds, [1]);
    expect(output.playedBytes, [[82, 73, 70, 70]]);
    expect(await File(output.filePaths.single).exists(), isFalse);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
    expect(output.disposals, 1);
  });

  test('offline engine records local numeric performance without book text',
      () async {
    final synth = engine();
    expect(synth.offlineVoiceStatistics.syntheses, 0);
    await synth.speak('Private book words', language: 'en-US',
        rate: 0.5, pitch: 1);
    final stats = synth.offlineVoiceStatistics;
    expect(stats.syntheses, 1);
    expect(stats.aheadSyntheses, 0);
    expect(stats.modelLoads, 0,
        reason: 'This test uses a mock, not a native ONNX model');
    expect(stats.lastSynthesisMs, greaterThanOrEqualTo(0));
    expect(stats.lastDecoderHandoffMs, greaterThanOrEqualTo(0));
    expect(stats.lastWholeProcessRssMiB, greaterThanOrEqualTo(0));
    await synth.dispose();
  });

  test('speech rate maps to engine speed and never calls a cloud service',
      () async {
    final synth = engine();
    await synth.speak('Faster', language: 'en_us', rate: 1.0, pitch: 1);
    await synth.speak('Slower', language: 'en-US', rate: 0.2, pitch: 1);
    expect(speeds, [2, 0.4]);
    expect(texts, ['Faster', 'Slower']);
    await synth.dispose();
  });

  test('unsupported voice/language/pitch and overlong text fail closed',
      () async {
    final synth = engine();
    await expectLater(synth.chooseVoice(
        const SpeechVoice(name: 'other', locale: 'en-US')),
        throwsFormatException);
    await expectLater(synth.speak('hello', language: 'it-IT',
        rate: 0.5, pitch: 1), throwsFormatException);
    await expectLater(synth.speak('hello', language: 'en-US',
        rate: 0.5, pitch: 1.1), throwsUnsupportedError);
    await expectLater(synth.speak('hello', language: 'en-US',
        rate: 0.1, pitch: 1), throwsFormatException);
    await expectLater(synth.speak('x' * 2049, language: 'en-US',
        rate: 0.5, pitch: 1), throwsFormatException);
    expect(texts, isEmpty);
    expect(output.filePaths, isEmpty);
    await synth.dispose();
  });

  test('stop while native synthesis is pending never plays delayed WAV',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void> delayed({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      entered.complete();
      await release.future;
      await File(wavPath).writeAsBytes([1, 2, 3]);
    }

    final synth = engine(synthesizer: delayed);
    final play = synth.speak('late', language: 'en-US',
        rate: 0.5, pitch: 1);
    await entered.future;
    await synth.stop();
    release.complete();
    await play;
    expect(output.stops, 1);
    expect(output.playedBytes, isEmpty);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('dispose during synthesis suppresses late playback and closes audio',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void> delayed({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      entered.complete();
      await release.future;
      await File(wavPath).writeAsBytes([1, 2, 3]);
    }
    final synth = engine(synthesizer: delayed);
    final play = synth.speak('late', language: 'en-US',
        rate: 0.5, pitch: 1);
    await entered.future;
    await synth.dispose();
    release.complete();
    await play;
    expect(output.disposals, 1);
    expect(output.playedBytes, isEmpty);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await expectLater(synth.speak('again', language: 'en-US',
        rate: 0.5, pitch: 1), throwsStateError);
  });

  test('locked WAV is retained and retried before the next utterance',
      () async {
    var locked = true;
    final cleaner = OfflineWavCleanup(
      maxPending: 2,
      deleteDirectory: (folder) async {
        if (locked) throw const FileSystemException('locked WAV');
        if (await folder.exists()) await folder.delete(recursive: true);
      },
    );
    final synth = SherpaVitsSpeechEngine(
      pack: pack,
      synthesizer: fakeSynthesize,
      output: output,
      wavCleanup: cleaner,
      temporaryDirectory: () async => root,
    );
    await synth.speak('First', language: 'en-US', rate: 0.5, pitch: 1);
    expect(cleaner.pendingCount, 1);
    expect(synth.offlineVoiceStatistics.pendingWaveFolders, 1);
    locked = false;
    await synth.speak('Next', language: 'en-US', rate: 0.5, pitch: 1);
    expect(cleaner.pendingCount, 0);
    expect(synth.offlineVoiceStatistics.pendingWaveFolders, 0);
    expect(texts, ['First', 'Next']);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('locked WAVs cause a bounded fail-closed refusal to synthesize',
      () async {
    var locked = true;
    final cleaner = OfflineWavCleanup(
      maxPending: 1,
      deleteDirectory: (folder) async {
        if (locked) throw const FileSystemException('locked WAV');
        if (await folder.exists()) await folder.delete(recursive: true);
      },
    );
    final synth = SherpaVitsSpeechEngine(
      pack: pack,
      synthesizer: fakeSynthesize,
      output: output,
      wavCleanup: cleaner,
      temporaryDirectory: () async => root,
    );
    await synth.speak('One', language: 'en-US', rate: 0.5, pitch: 1);
    expect(cleaner.pendingCount, 1);
    await expectLater(synth.speak('Blocked', language: 'en-US',
        rate: 0.5, pitch: 1), throwsStateError);
    expect(texts, ['One'],
        reason: 'Do not generate another WAV when orphan cap is reached');
    locked = false;
    await synth.speak('Allowed', language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, ['One', 'Allowed']);
    expect(cleaner.pendingCount, 0);
    await synth.dispose();
  });

  test('production PCM validator accepts correct WAV before audio output',
      () async {
    Future<void> valid({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      await File(wavPath).writeAsBytes(_validPcmWav());
    }
    final synth = SherpaVitsSpeechEngine(
      pack: pack,
      synthesizer: valid,
      validateNativeWaveOutput: true,
      output: output,
      temporaryDirectory: () async => root,
    );
    await synth.speak('valid', language: 'en-US', rate: 0.5, pitch: 1);
    expect(output.playedBytes, hasLength(1));
    expect(output.playedBytes.single, _validPcmWav());
    expect(synth.offlineVoiceStatistics.syntheses, 1);
    await synth.dispose();
    expect(await root.list().toList(), isEmpty);
  });

  test('malformed native WAV fails before decoder and removes staging',
      () async {
    Future<void> invalid({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      await File(wavPath).writeAsBytes([82, 73, 70, 70]);
    }
    final synth = SherpaVitsSpeechEngine(
      pack: pack,
      synthesizer: invalid,
      validateNativeWaveOutput: true,
      output: output,
      temporaryDirectory: () async => root,
    );
    await expectLater(synth.speak('corrupt', language: 'en-US',
        rate: 0.5, pitch: 1), throwsFormatException);
    expect(output.filePaths, isEmpty);
    expect(synth.offlineVoiceStatistics.syntheses, 0);
    expect(synth.offlineVoiceStatistics.failures, 1);
    await synth.dispose();
    expect(await root.list().toList(), isEmpty);
  });

  test('invalid prepared WAV is discarded and audible speech regenerates',
      () async {
    var secondAttempts = 0;
    Future<void> invalidAhead({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      if (text == 'Second') secondAttempts++;
      if (text == 'Second' && secondAttempts == 1) {
        await File(wavPath).writeAsBytes([82, 73, 70, 70]);
      } else {
        await File(wavPath).writeAsBytes(_validPcmWav());
      }
    }
    final synth = SherpaVitsSpeechEngine(
      pack: pack,
      synthesizer: invalidAhead,
      validateNativeWaveOutput: true,
      output: output,
      temporaryDirectory: () async => root,
    );
    final playing = Completer<void>();
    output.playGate = playing;
    final first = synth.speak('First',
        language: 'en-US', rate: 0.5, pitch: 1);
    for (var i = 0; i < 50 && output.filePaths.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(output.filePaths, hasLength(1));
    await synth.prepareOfflineSpeech('Second',
        voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    expect(synth.offlineVoiceStatistics.failures, 1);
    output.playGate = null;
    playing.complete();
    await first;
    await synth.speak('Second',
        language: 'en-US', rate: 0.5, pitch: 1);
    expect(secondAttempts, 2);
    expect(output.filePaths, hasLength(2));
    expect(synth.offlineVoiceStatistics.syntheses, 2);
    await synth.dispose();
    expect(await root.list().toList(), isEmpty);
  });

  test('native synthesis failure does not leak temporary voice audio',
      () async {
    Future<void> fails({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async => throw StateError('Native engine unavailable');

    final synth = engine(synthesizer: fails);
    await expectLater(synth.speak('bad', language: 'en-US',
        rate: 0.5, pitch: 1), throwsStateError);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    expect(output.filePaths, isEmpty);
    await synth.dispose();
  });

  test('one-ahead local synthesis runs while the first WAV plays and is reused',
      () async {
    final synth = engine();
    final gate = Completer<void>();
    output.playGate = gate;
    final first = synth.speak(
        'First', language: 'en-US', rate: 0.5, pitch: 1);
    for (var n = 0; n < 50 && output.filePaths.isEmpty; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(output.filePaths, hasLength(1));
    await synth.prepareOfflineSpeech(
      'Second', voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, ['First', 'Second']);
    expect(output.filePaths, hasLength(1),
        reason: 'Warming must never start audible output');
    await synth.prepareOfflineSpeech(
      'Second', voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, hasLength(2),
        reason: 'At most one speculative synthesis for a repeated request');

    output.playGate = null;
    gate.complete();
    await first;
    await synth.speak(
        'Second', language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, ['First', 'Second'],
        reason: 'Prepared WAV must be reused without re-synthesis');
    expect(output.filePaths, hasLength(2));
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('wrong speculative next text is discarded before real synthesis',
      () async {
    final synth = engine();
    final gate = Completer<void>();
    output.playGate = gate;
    final first = synth.speak(
        'First', language: 'en-US', rate: 0.5, pitch: 1);
    for (var n = 0; n < 50 && output.filePaths.isEmpty; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(output.filePaths, hasLength(1));
    await synth.prepareOfflineSpeech(
      'Predicted', voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, ['First', 'Predicted']);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isNotEmpty);
    output.playGate = null;
    gate.complete();
    await first;
    await synth.speak('Actual', language: 'en-US', rate: 0.5, pitch: 1);
    expect(texts, ['First', 'Predicted', 'Actual']);
    expect(output.filePaths, hasLength(2));
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('changed speed waits for unfinished speculative synthesis', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void> slowNext({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      texts.add(text);
      speeds.add(speed);
      if (text == 'Next') {
        entered.complete();
        await release.future;
      }
      await File(wavPath).writeAsBytes([82, 73, 70, 70]);
    }

    final synth = engine(synthesizer: slowNext);
    final gate = Completer<void>();
    output.playGate = gate;
    final first = synth.speak(
        'First', language: 'en-US', rate: 0.5, pitch: 1);
    for (var n = 0; n < 50 && output.filePaths.isEmpty; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(output.filePaths, hasLength(1));
    final preparing = synth.prepareOfflineSpeech(
      'Next', voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    await entered.future;
    output.playGate = null;
    gate.complete();
    await first;

    final real = synth.speak(
        'Next', language: 'en-US', rate: 0.8, pitch: 1);
    // A second synthesis must not start while the prior WAV is pending.
    await Future<void>.delayed(Duration.zero);
    expect(texts, ['First', 'Next']);
    release.complete();
    await preparing;
    await real;
    expect(texts, ['First', 'Next', 'Next']);
    expect(speeds, [1, 1, 1.6]);
    expect(output.filePaths, hasLength(2));
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('stop discards a completed lookahead WAV without playing it',
      () async {
    final synth = engine();
    output.playGate = Completer<void>();
    final first = synth.speak(
        'First', language: 'en-US', rate: 0.5, pitch: 1);
    for (var n = 0; n < 50 && output.filePaths.isEmpty; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(output.filePaths, hasLength(1));
    await synth.prepareOfflineSpeech(
      'Second', voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    await synth.stop();
    await first;
    expect(output.filePaths, hasLength(1));
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('stop during speculative synthesis invalidates late WAV and cleans it',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void> slowNext({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {
      texts.add(text);
      if (text == 'Second') {
        entered.complete();
        await release.future;
      }
      await File(wavPath).writeAsBytes([82, 73, 70, 70]);
    }
    final synth = engine(synthesizer: slowNext);
    output.playGate = Completer<void>();
    final first = synth.speak(
        'First', language: 'en-US', rate: 0.5, pitch: 1);
    for (var n = 0; n < 50 && output.filePaths.isEmpty; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    final speculative = synth.prepareOfflineSpeech(
      'Second', voice: null, language: 'en-US', rate: 0.5, pitch: 1);
    await entered.future;
    await synth.stop();
    release.complete();
    await speculative;
    await first;
    expect(output.filePaths, hasLength(1));
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });

  test('missing WAV fails safely without attempting output playback',
      () async {
    Future<void> empty({
      required String text,
      required String modelPath,
      required String tokensPath,
      required String dataDir,
      required String wavPath,
      required double speed,
    }) async {}
    final synth = engine(synthesizer: empty);
    await expectLater(synth.speak('missing', language: 'en-US',
        rate: 0.5, pitch: 1), throwsStateError);
    expect((await root.list(recursive: true, followLinks: false).toList())
        .where((f) => f is File && f.path.endsWith('speech.wav')).toList(), isEmpty);
    await synth.dispose();
  });
}
