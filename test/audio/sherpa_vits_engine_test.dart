import 'dart:async';
import 'dart:io';

import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeWaveOutput implements OfflineWaveOutput {
  final playedBytes = <List<int>>[];
  final filePaths = <String>[];
  int stops = 0;
  int disposals = 0;

  @override
  Future<void> play(String filePath) async {
    expect(await File(filePath).exists(), isTrue);
    filePaths.add(filePath);
    playedBytes.add(await File(filePath).readAsBytes());
  }

  @override
  Future<void> stop() async { stops++; }

  @override
  Future<void> dispose() async { disposals++; }
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
    expect(await root.list().toList(), isEmpty);
    await synth.dispose();
    expect(output.disposals, 1);
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
    expect(await root.list().toList(), isEmpty);
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
    expect(await root.list().toList(), isEmpty);
    await expectLater(synth.speak('again', language: 'en-US',
        rate: 0.5, pitch: 1), throwsStateError);
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
    expect(await root.list().toList(), isEmpty);
    expect(output.filePaths, isEmpty);
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
    expect(await root.list().toList(), isEmpty);
    await synth.dispose();
  });
}
