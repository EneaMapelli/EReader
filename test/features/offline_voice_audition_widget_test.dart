import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ereader/audio/offline_voice_audition.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:ereader/features/reader/offline_voice_manager_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _AuditionFakeEngine implements SpeechEngine {
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  final finish = Completer<void>();

  @override
  Future<List<SpeechVoice>> listVoices() async => const [];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}

  @override
  Future<void> speak(String text, {required String language,
      required double rate, required double pitch}) async {
    starts++;
    await finish.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!finish.isCompleted) finish.complete();
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  late Directory temporary;
  late Directory source;
  late Directory models;
  late OfflineVoicePackManifest manifest;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('ereader-preview-ui-');
    source = await Directory(p.join(temporary.path, 'source')).create();
    models = Directory(p.join(temporary.path, 'models'));
    final model = [1, 2, 3];
    final tokens = [4, 5, 6];
    await File(p.join(source.path, 'model.onnx')).writeAsBytes(model);
    await File(p.join(source.path, 'tokens.txt')).writeAsBytes(tokens);
    manifest = OfflineVoicePackManifest(
      id: 'preview-it',
      displayName: 'Italian preview',
      locale: 'it-IT',
      licenseId: 'MIT',
      modelSha256: sha256.convert(model).toString(),
      tokensSha256: sha256.convert(tokens).toString(),
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('incomplete model cannot be previewed even with fake audio',
      (tester) async {
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    );
    final audition = OfflineVoiceAudition(
      loadPack: (id) => loadInstalledOfflineVoicePack(
        packId: id, modelsDirectory: models),
      createEngine: (_) => _AuditionFakeEngine(),
    );
    await tester.pumpWidget(MaterialApp(home: OfflineVoiceManagerScreen(
      modelsDirectory: () async => models, audition: audition,
    )));
    await settle(tester);
    expect(find.text('Italian preview'), findsOneWidget);
    expect(find.byTooltip('Preview voice preview-it'), findsNothing);
  });

  testWidgets('preview requires consent, then native Stop cancels sample',
      (tester) async {
    final phonemes = [11, 22, 33];
    await Directory(p.join(source.path, 'espeak-ng-data')).create();
    await File(p.join(source.path, 'espeak-ng-data', 'phonemes'))
        .writeAsBytes(phonemes);
    manifest = OfflineVoicePackManifest(
      id: manifest.id,
      displayName: manifest.displayName,
      locale: manifest.locale,
      licenseId: manifest.licenseId,
      modelSha256: manifest.modelSha256,
      tokensSha256: manifest.tokensSha256,
      phonemizerResources: [
        OfflineVoiceResource(
          relativePath: 'espeak-ng-data/phonemes',
          sha256: sha256.convert(phonemes).toString(),
        ),
      ],
    );
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    );
    final fake = _AuditionFakeEngine();
    final audition = OfflineVoiceAudition(
      loadPack: (id) => loadInstalledOfflineVoicePack(
        packId: id, modelsDirectory: models),
      createEngine: (_) => fake,
    );
    await tester.pumpWidget(MaterialApp(home: OfflineVoiceManagerScreen(
      modelsDirectory: () async => models, audition: audition,
    )));
    await settle(tester);
    var button = find.byTooltip('Preview voice preview-it');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Play experimental offline voice sample?'),
        findsOneWidget);
    expect(fake.starts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.starts, 0);

    button = find.byTooltip('Preview voice preview-it');
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play sample'));
    await tester.runAsync(() async {
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (fake.starts == 0 && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(fake.starts, 1);
    await tester.tap(find.byTooltip('Stop sample preview-it'));
    await settle(tester);
    expect(fake.stops, 1);
    expect(fake.disposals, 1);
    expect(find.textContaining('sample stopped'), findsOneWidget);
    expect(find.byTooltip('Remove voice preview-it'), findsOneWidget);
  });
}
