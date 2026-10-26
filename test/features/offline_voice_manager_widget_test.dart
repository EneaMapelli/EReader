import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:ereader/features/reader/offline_voice_manager_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory source;
  late Directory models;
  late OfflineVoicePackManifest manifest;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-voice-ui-');
    source = await Directory(p.join(root.path, 'src')).create();
    models = Directory(p.join(root.path, 'models'));
    final model = [3, 1, 4];
    final tokens = [10, 20, 30];
    await File(p.join(source.path, 'model.onnx')).writeAsBytes(model);
    await File(p.join(source.path, 'tokens.txt')).writeAsBytes(tokens);
    manifest = OfflineVoicePackManifest(
      id: 'local-test', displayName: 'Local test voice',
      locale: 'en-US', licenseId: 'MIT',
      modelSha256: sha256.convert(model).toString(),
      tokensSha256: sha256.convert(tokens).toString(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OfflineVoiceManagerScreen(modelsDirectory: () async => models),
    ));
    // File-system futures run in real time, outside Flutter's fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> letIoSettle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('empty catalog explains why offline synthesis stays disabled',
      (tester) async {
    await mount(tester);
    expect(find.text('No local neural voices installed.'), findsOneWidget);
    expect(find.textContaining('not yet enabled for reading'), findsOneWidget);
    expect(find.textContaining('Downloads and playback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved voice shows source metadata, not an enable button',
      (tester) async {
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    );
    await mount(tester);
    expect(find.text('Local test voice'), findsOneWidget);
    expect(find.textContaining('Verified files'), findsOneWidget);
    expect(find.textContaining('MIT'), findsOneWidget);
    expect(find.text('Enable neural narration'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled deletion leaves the voice files intact',
      (tester) async {
    final pack = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Remove voice local-test'));
    await tester.pumpAndSettle();
    expect(find.text('Remove offline voice?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await File(pack.modelPath).exists(), isTrue);
    expect(find.text('Local test voice'), findsOneWidget);
  });

  testWidgets('confirmed removal updates catalog without changing books',
      (tester) async {
    final pack = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Remove voice local-test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove voice'));
    await letIoSettle(tester);
    expect(await File(pack.modelPath).exists(), isFalse);
    expect(find.text('No local neural voices installed.'), findsOneWidget);
    expect(find.text('Local voice removed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupted pack is marked unavailable rather than activated',
      (tester) async {
    await Directory(p.join(models.path, 'broken-voice'))
        .create(recursive: true);
    await mount(tester);
    expect(find.text('broken-voice'), findsOneWidget);
    expect(find.textContaining('Unavailable: missing or damaged'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
