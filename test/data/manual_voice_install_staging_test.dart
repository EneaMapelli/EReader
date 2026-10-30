import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ereader/data/manual_voice_install_staging.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory models;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-manual-stage-test-');
    models = await Directory(p.join(root.path, 'offline-voices')).create();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Directory> abandoned({
    bool marked = true,
    bool withAsset = true,
  }) async {
    final folder = await models.createTemp(ManualVoiceInstallStaging.prefix);
    await File(p.join(folder.path, ManualVoiceInstallStaging.leaseName))
        .create();
    if (marked) {
      await File(p.join(folder.path, ManualVoiceInstallStaging.markerName))
          .writeAsString(ManualVoiceInstallStaging.markerContent);
    }
    final payload = await Directory(p.join(
        folder.path, ManualVoiceInstallStaging.payloadName)).create();
    if (withAsset) {
      await File(p.join(payload.path, 'model.onnx'))
          .writeAsBytes([1, 2, 3]);
    }
    return folder;
  }

  test('only aged, marked incomplete payloads are reclaimed', () async {
    final old = await abandoned();
    final fresh = await abandoned();
    final legacy = await abandoned(marked: false);
    final unrelated = await Directory(p.join(models.path, 'user-notes'))
        .create();
    await File(p.join(unrelated.path, 'keep.txt')).writeAsString('keep');
    await File(p.join(old.path, ManualVoiceInstallStaging.markerName))
        .setLastModified(DateTime.now().subtract(const Duration(days: 3)));

    expect(await ManualVoiceInstallStaging.recoverAbandoned(models), 1);
    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await legacy.exists(), isTrue);
    expect(await File(p.join(unrelated.path, 'keep.txt'))
        .readAsString(), 'keep');
  });

  test('live import is ignored, and finish removes only its owned stage',
      () async {
    final stage = await ManualVoiceInstallStaging.create(models);
    await File(p.join(stage.payload.path, 'tokens.txt'))
        .writeAsString('tokens');
    expect(await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero), 0);
    expect(await stage.payload.exists(), isTrue);
    await stage.finish();
    await stage.finish();
    expect(await stage.directory.exists(), isFalse);
    expect(await models.list().toList(), isEmpty);
  });

  test('nested allowed phonemizer assets can be safely reclaimed', () async {
    final stage = await abandoned();
    final voices = await Directory(p.join(stage.path,
        ManualVoiceInstallStaging.payloadName,
        'espeak-ng-data', 'voices', '!v')).create(recursive: true);
    await File(p.join(voices.path, 'f1')).writeAsString('phonemes');
    await File(p.join(stage.path, ManualVoiceInstallStaging.payloadName,
        'tokens.txt')).writeAsBytes([8]);
    expect(await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero), 1);
    expect(await stage.exists(), isFalse);
  });

  test('malformed marker and unexpected content fail closed', () async {
    final malformed = await abandoned();
    await File(p.join(malformed.path,
        ManualVoiceInstallStaging.markerName)).writeAsString('not EReader');
    final unknown = await abandoned();
    await File(p.join(unknown.path,
        ManualVoiceInstallStaging.payloadName, 'unexpected.exe'))
        .writeAsBytes([5]);
    expect(await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero), 0);
    expect(await malformed.exists(), isTrue);
    expect(await unknown.exists(), isTrue);
    expect(await File(p.join(unknown.path,
        ManualVoiceInstallStaging.payloadName, 'unexpected.exe'))
        .readAsBytes(), [5]);
  });

  test('symlinks cannot cause deletion outside the private model directory',
      () async {
    if (Platform.isWindows) return; // restricted symlink privileges
    final external = File(p.join(root.path, 'my-book.txt'));
    await external.writeAsString('never delete');
    final stage = await abandoned(withAsset: false);
    await Link(p.join(stage.path, ManualVoiceInstallStaging.payloadName,
        'model.onnx')).create(external.path);
    expect(await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero), 0);
    expect(await external.readAsString(), 'never delete');
    expect(await stage.exists(), isTrue);
  });

  test('sixteen stages per sweep and idempotent retry', () async {
    final folders = <Directory>[];
    for (var i = 0;
        i < ManualVoiceInstallStaging.maxCandidatesPerSweep + 3; i++) {
      folders.add(await abandoned());
    }
    final first = await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero);
    expect(first, ManualVoiceInstallStaging.maxCandidatesPerSweep);
    expect((await Future.wait(folders.map((d) => d.exists())))
        .where((exists) => exists).length, 3);
    expect(await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero), 3);
    expect(await ManualVoiceInstallStaging.recoverAbandoned(
        models, minimumAge: Duration.zero), 0);
  });

  test('successful voice install promotes only the verified payload',
      () async {
    final source = await Directory(p.join(root.path, 'selected-source'))
        .create();
    final model = File(p.join(source.path, 'model.onnx'));
    final tokens = File(p.join(source.path, 'tokens.txt'));
    await model.writeAsBytes([1, 2, 3]);
    await tokens.writeAsBytes([4, 5]);
    final manifest = OfflineVoicePackManifest(
      id: 'test-voice', displayName: 'Test offline model',
      locale: 'it-IT', licenseId: 'MIT',
      modelSha256: sha256.convert([1, 2, 3]).toString(),
      tokensSha256: sha256.convert([4, 5]).toString(),
    );
    final installed = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    );
    expect(await File(installed.modelPath).readAsBytes(), [1, 2, 3]);
    expect(await File(installed.tokensPath).readAsBytes(), [4, 5]);
    final contents = await Directory(
        p.join(models.path, manifest.id)).list().toList();
    expect(contents.map((entry) => p.basename(entry.path)).toSet(),
        {'model.onnx', 'tokens.txt', 'voice-pack.json'},
        reason: 'No marker/lease is ever promoted to a playable model');
    expect((await models.list().toList()).map(
        (entry) => p.basename(entry.path)).toList(), [manifest.id]);
    final reopened = await loadInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: models);
    expect(reopened.manifest.id, manifest.id);
  });

  test('SHA mismatch clears the marked staging and installs no model',
      () async {
    final source = await Directory(p.join(root.path, 'bad-source'))
        .create();
    await File(p.join(source.path, 'model.onnx'))
        .writeAsBytes([1, 2, 3]);
    await File(p.join(source.path, 'tokens.txt'))
        .writeAsBytes([4, 5]);
    final manifest = OfflineVoicePackManifest(
      id: 'bad-voice', displayName: 'Rejected model', locale: 'en-US',
      licenseId: 'MIT',
      modelSha256: sha256.convert([1, 2, 3]).toString(),
      tokensSha256: sha256.convert([99]).toString(),
    );
    await expectLater(installOfflineVoicePack(
      manifest: manifest, sourceDirectory: source,
      modelsDirectory: models,
    ), throwsFormatException);
    expect(await models.list().toList(), isEmpty);
    expect(await File(p.join(source.path, 'model.onnx')).readAsBytes(),
        [1, 2, 3], reason: 'Failed import never deletes the user source');
  });
}
