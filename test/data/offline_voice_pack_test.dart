import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory input;
  late Directory installed;
  late OfflineVoicePackManifest manifest;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-offline-voice-');
    input = await Directory(p.join(root.path, 'input')).create();
    installed = Directory(p.join(root.path, 'installed'));
    final model = [1, 2, 3, 4, 5, 6];
    final tokens = [97, 98, 10, 99, 100, 10];
    await File(p.join(input.path, 'model.onnx')).writeAsBytes(model);
    await File(p.join(input.path, 'tokens.txt')).writeAsBytes(tokens);
    manifest = OfflineVoicePackManifest(
      id: 'piper-en-test',
      displayName: 'Local sample',
      locale: 'en-US',
      licenseId: 'MIT',
      modelSha256: sha256.convert(model).toString(),
      tokensSha256: sha256.convert(tokens).toString(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<List<String>> folderContents() async =>
      (await installed.exists())
          ? (await installed.list().map((e) => p.basename(e.path)).toList())
          : const [];

  test('verified two-file model installs into a private pack directory',
      () async {
    final pack = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    expect(p.basename(p.dirname(pack.modelPath)), manifest.id);
    expect(await File(pack.modelPath).readAsBytes(), [1, 2, 3, 4, 5, 6]);
    expect(await File(pack.tokensPath).readAsBytes(), [97, 98, 10, 99, 100, 10]);
    expect(await folderContents(), ['piper-en-test']);
  });

  test('same manifest can be reinstalled without changing existing files',
      () async {
    final first = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    final originalModified = await File(first.modelPath).lastModified();
    final second = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    expect(second.modelPath, first.modelPath);
    expect(await File(second.modelPath).lastModified(), originalModified);
    expect(await folderContents(), ['piper-en-test']);
  });

  test('corrupt installed model is rejected without replacement', () async {
    final pack = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    await File(pack.modelPath).writeAsBytes([8, 7, 6]);
    await expectLater(
      installOfflineVoicePack(
        manifest: manifest, sourceDirectory: input,
        modelsDirectory: installed,
      ),
      throwsFormatException,
    );
    expect(await File(pack.modelPath).readAsBytes(), [8, 7, 6]);
    expect(await folderContents(), ['piper-en-test']);
  });

  test('digest mismatch rejects a new pack and removes its staging directory',
      () async {
    await File(p.join(input.path, 'tokens.txt')).writeAsString('altered');
    await expectLater(
      installOfflineVoicePack(
        manifest: manifest, sourceDirectory: input,
        modelsDirectory: installed,
      ),
      throwsFormatException,
    );
    expect(await folderContents(), isEmpty);
  });

  test('byte ceilings prevent oversized model and tokens installation',
      () async {
    await expectLater(installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed, maxModelBytes: 5,
    ), throwsFormatException);
    expect(await folderContents(), isEmpty);
    await expectLater(installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed, maxTokensBytes: 5,
    ), throwsFormatException);
    expect(await folderContents(), isEmpty);
  });


  test('verified eSpeak phonemizer resources install and reverify',
      () async {
    final relative = 'espeak-ng-data/voices/en';
    final resource = [115, 112, 101, 97, 107];
    final folder = Directory(p.join(input.path, 'espeak-ng-data', 'voices'));
    await folder.create(recursive: true);
    await File(p.join(folder.path, 'en')).writeAsBytes(resource);
    final enriched = OfflineVoicePackManifest(
      id: manifest.id,
      displayName: manifest.displayName,
      locale: manifest.locale,
      licenseId: manifest.licenseId,
      modelSha256: manifest.modelSha256,
      tokensSha256: manifest.tokensSha256,
      phonemizerResources: [
        OfflineVoiceResource(
          relativePath: relative,
          sha256: sha256.convert(resource).toString(),
        ),
      ],
    );
    final pack = await installOfflineVoicePack(
      manifest: enriched, sourceDirectory: input,
      modelsDirectory: installed,
    );
    expect(pack.phonemizerDataDir,
        p.join(installed.path, enriched.id, 'espeak-ng-data'));
    expect(await File(p.join(pack.phonemizerDataDir!, 'voices', 'en'))
        .readAsBytes(), resource);

    final same = await installOfflineVoicePack(
      manifest: enriched, sourceDirectory: input,
      modelsDirectory: installed,
    );
    expect(same.phonemizerDataDir, pack.phonemizerDataDir);
    expect(await folderContents(), ['piper-en-test']);
  });

  test('tampered phonemizer data blocks reinstall without replacement',
      () async {
    final content = [1, 2, 3];
    final relative = 'espeak-ng-data/phonemes';
    final dir = Directory(p.join(input.path, 'espeak-ng-data'));
    await dir.create();
    await File(p.join(dir.path, 'phonemes')).writeAsBytes(content);
    final voiceManifest = OfflineVoicePackManifest(
      id: 'piper-phoneme',
      displayName: manifest.displayName,
      locale: manifest.locale,
      licenseId: manifest.licenseId,
      modelSha256: manifest.modelSha256,
      tokensSha256: manifest.tokensSha256,
      phonemizerResources: [
        OfflineVoiceResource(
          relativePath: relative,
          sha256: sha256.convert(content).toString(),
        ),
      ],
    );
    final pack = await installOfflineVoicePack(
      manifest: voiceManifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    await File(p.join(pack.phonemizerDataDir!, 'phonemes'))
        .writeAsBytes([9, 9, 9]);
    await expectLater(installOfflineVoicePack(
      manifest: voiceManifest, sourceDirectory: input,
      modelsDirectory: installed,
    ), throwsFormatException);
    expect(await folderContents(), ['piper-phoneme']);
  });

  test('resource paths, case duplicates and overall byte budget fail closed',
      () async {
    OfflineVoicePackManifest withResources(
            List<OfflineVoiceResource> resources) =>
        OfflineVoicePackManifest(
          id: 'piper-safe',
          displayName: manifest.displayName,
          locale: manifest.locale,
          licenseId: manifest.licenseId,
          modelSha256: manifest.modelSha256,
          tokensSha256: manifest.tokensSha256,
          phonemizerResources: resources,
        );
    final checksum = sha256.convert([1, 2]).toString();
    for (final name in [
      '../model.onnx',
      'espeak-ng-data/../unsafe',
      'espeak-ng-data//empty',
      'espeak-ng-data/..',
      'espeak-ng-data/evil\\name',
      'unapproved/other',
      'espeak-ng-data/NUL',
      'espeak-ng-data/CON.txt',
      'espeak-ng-data/COM1',
      'espeak-ng-data/trailing.',
    ]) {
      expect(() => withResources([
        OfflineVoiceResource(relativePath: name, sha256: checksum),
      ]).validate(), throwsFormatException);
    }
    expect(() => withResources([
      OfflineVoiceResource(
          relativePath: 'espeak-ng-data/EN', sha256: checksum),
      OfflineVoiceResource(
          relativePath: 'espeak-ng-data/en', sha256: checksum),
    ]).validate(), throwsFormatException);

    final dir = await Directory(
        p.join(input.path, 'espeak-ng-data')).create();
    await File(p.join(dir.path, 'voices')).writeAsBytes([1, 2]);
    final overBudget = withResources([
      OfflineVoiceResource(
        relativePath: 'espeak-ng-data/voices',
        sha256: checksum,
      ),
    ]);
    await expectLater(installOfflineVoicePack(
      manifest: overBudget, sourceDirectory: input,
      modelsDirectory: installed, maxPhonemizerBytes: 1,
    ), throwsFormatException);
    expect(await folderContents(), isEmpty);
  });

  test('invalid IDs and untrusted manifest data never create installation',
      () async {
    for (final id in ['../escape', 'UPPER', 'a/b', '.hidden']) {
      final bad = OfflineVoicePackManifest(
        id: id, displayName: 'Invalid', locale: 'en-US',
        licenseId: 'MIT',
        modelSha256: manifest.modelSha256,
        tokensSha256: manifest.tokensSha256,
      );
      await expectLater(installOfflineVoicePack(
        manifest: bad, sourceDirectory: input,
        modelsDirectory: installed,
      ), throwsFormatException);
    }
    final badDigest = OfflineVoicePackManifest(
      id: 'legitimate', displayName: 'Invalid', locale: 'en-US',
      licenseId: 'MIT', modelSha256: 'not-a-digest',
      tokensSha256: manifest.tokensSha256,
    );
    await expectLater(installOfflineVoicePack(
      manifest: badDigest, sourceDirectory: input,
      modelsDirectory: installed,
    ), throwsFormatException);
    expect(await folderContents(), isEmpty);
  });
}
