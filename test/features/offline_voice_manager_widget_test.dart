import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:ereader/features/reader/offline_voice_manager_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../support/windows_temp_cleanup.dart';

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
    await deleteOwnedTestTemp(root);
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


  Future<void> putVoiceManifest() async {
    await File(p.join(source.path, 'voice-pack.json'))
        .writeAsString(jsonEncode(manifest.toJson()));
  }

  Future<void> mountWithPicker(
      WidgetTester tester, Future<String?> Function() picker) async {
    await tester.pumpWidget(MaterialApp(
      home: OfflineVoiceManagerScreen(
        modelsDirectory: () async => models,
        pickSourceDirectory: picker,
      ),
    ));
    await letIoSettle(tester);
  }

  testWidgets('folder import needs explicit review before local copy',
      (tester) async {
    await putVoiceManifest();
    await mountWithPicker(tester, () async => source.path);
    await tester.tap(find.text('Import local voice folder'));
    await letIoSettle(tester);
    expect(find.text('Local test voice'), findsNothing);
    expect(find.text('Declared license: MIT'), findsOneWidget);
    expect(find.text('Language: en-US'), findsOneWidget);
    expect(find.textContaining('Review offline voice before installation'),
        findsOneWidget);
    final install = find.widgetWithText(
        FilledButton, 'Verify and install locally');
    expect(tester.widget<FilledButton>(install).onPressed, isNull);
    expect(await models.exists(), isFalse);

    await tester.ensureVisible(find.byKey(
        const ValueKey('offline-voice-license-approval')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('offline-voice-license-approval')));
    await tester.pump();
    expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
    await tester.ensureVisible(install);
    await tester.pumpAndSettle();
    await tester.tap(install);
    await letIoSettle(tester);
    expect(find.text('Local test voice'), findsOneWidget);
    expect(find.textContaining('Local voice installed.'), findsOneWidget);
    expect((await inspectOfflineVoicePacks(modelsDirectory: models)).single.ready,
        isTrue);
  });

  testWidgets('a folder picker cancel makes no changes',
      (tester) async {
    await mountWithPicker(tester, () async => null);
    await tester.tap(find.text('Import local voice folder'));
    await letIoSettle(tester);
    expect(find.byKey(
        const ValueKey('offline-voice-import-preview')), findsNothing);
    expect(await models.exists(), isFalse);
    expect(find.text('No local neural voices installed.'), findsOneWidget);
  });

  testWidgets('bad manifest produces safe error and installs nothing',
      (tester) async {
    await mountWithPicker(tester, () async => source.path);
    await tester.tap(find.text('Import local voice folder'));
    await letIoSettle(tester);
    expect(find.textContaining('Cannot inspect this voice folder.'),
        findsOneWidget);
    expect(find.byKey(
        const ValueKey('offline-voice-import-preview')), findsNothing);
    expect(await models.exists(), isFalse);
  });

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

  testWidgets('installed language filter retains corrupted-pack warnings',
      (tester) async {
    await installOfflineVoicePack(
      manifest: manifest,
      sourceDirectory: source,
      modelsDirectory: models,
    );
    await installOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: 'italian-model',
        displayName: 'Italian local voice',
        locale: 'it-IT',
        licenseId: 'MIT',
        modelSha256: manifest.modelSha256,
        tokensSha256: manifest.tokensSha256,
      ),
      sourceDirectory: source,
      modelsDirectory: models,
    );
    await Directory(p.join(models.path, 'broken-voice'))
        .create(recursive: true);
    await mount(tester);
    expect(find.text('Local test voice'), findsOneWidget);
    expect(find.text('Italian local voice'), findsOneWidget);
    expect(find.text('broken-voice'), findsOneWidget);

    await tester.ensureVisible(find.byKey(
        const ValueKey('offline-model-language-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('offline-model-language-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IT').last);
    await tester.pumpAndSettle();
    expect(find.text('Italian local voice'), findsOneWidget);
    expect(find.text('Local test voice'), findsNothing);
    expect(find.text('broken-voice'), findsOneWidget,
        reason: 'Damaged models must not disappear behind a filter');
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
