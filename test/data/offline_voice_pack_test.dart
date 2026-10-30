import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:ereader/data/offline_voice_install_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('offline install diagnostics distinguish integrity and recoverable IO',
      () {
    OfflineVoiceFailure report(Object error,
        [OfflineVoiceOperation operation =
            OfflineVoiceOperation.installFolder]) =>
        diagnoseOfflineVoiceFailure(error, operation: operation);

    expect(report(const FormatException('Offline voice SHA-256 mismatch'))
        .kind, OfflineVoiceFailureKind.integrity);
    expect(report(const FormatException('Piper archive checksum mismatch'),
        OfflineVoiceOperation.installPaola).kind,
        OfflineVoiceFailureKind.integrity);
    expect(report(const FormatException('Windows tar could not unpack Piper voice'),
        OfflineVoiceOperation.installPaola).kind,
        OfflineVoiceFailureKind.extraction);
    expect(report(const FormatException('Piper archive is missing model assets'))
        .kind, OfflineVoiceFailureKind.incomplete);
    expect(report(const FormatException('Unexpected file in offline voice pack'))
        .kind, OfflineVoiceFailureKind.unsafeFiles);
    expect(report(const FormatException('Offline voice file exceeds size budget'))
        .kind, OfflineVoiceFailureKind.sizeLimit);
    expect(report(FileSystemException('disk full', '/private/user/token',
        const OSError('private', 28))).kind, OfflineVoiceFailureKind.noSpace);
    expect(report(FileSystemException('access', '/private/user/token',
        const OSError('private', 13))).kind, OfflineVoiceFailureKind.accessDenied);
    expect(report(FileSystemException('busy', '/private/user/token',
        const OSError('private', 32))).kind, OfflineVoiceFailureKind.lockedFiles);
  });

  test('Paola network, extractor and Windows failure advice is sanitized',
      () {
    final cases = <(Object, OfflineVoiceFailureKind)>[
      (const SocketException('Secret DNS endpoint'),
          OfflineVoiceFailureKind.download),
      (TimeoutException('Private URL timeout'),
          OfflineVoiceFailureKind.download),
      (const FormatException('Piper download unavailable or unsafe'),
          OfflineVoiceFailureKind.download),
      (ProcessException('tar.exe', ['/private/voice.tar.bz2'],
          'Private source path'), OfflineVoiceFailureKind.extraction),
      (const FormatException('Windows tar could not unpack Piper voice'),
          OfflineVoiceFailureKind.extraction),
      (UnsupportedError('Private platform details'),
          OfflineVoiceFailureKind.unsupported),
      (FileSystemException('Private storage', '/private/voice',
          const OSError('Private', 112)), OfflineVoiceFailureKind.noSpace),
    ];
    for (final (error, expected) in cases) {
      final diagnosis = diagnoseOfflineVoiceFailure(
          error, operation: OfflineVoiceOperation.installPaola);
      expect(diagnosis.kind, expected);
      expect(diagnosis.message, startsWith('Paola could not be installed.'));
      expect(diagnosis.message, isNot(contains('/private/')));
      expect(diagnosis.message, isNot(contains('Secret DNS')));
    }
  });

  test('offline voice failure messages cannot reveal OS paths or source text',
      () {
    const secret = '/private/user/secret-wallet.txt';
    for (final error in <Object>[
      FileSystemException('private model path', secret,
          const OSError('SECRET', 28)),
      const FormatException('Failed import from $secret'),
      StateError('The private source is $secret'),
      Exception('User book contents $secret'),
    ]) {
      for (final operation in OfflineVoiceOperation.values) {
        final diagnosis = diagnoseOfflineVoiceFailure(
            error, operation: operation);
        expect(diagnosis.message, isNot(contains(secret)));
        expect(diagnosis.message, isNot(contains('secret-wallet')));
        expect(diagnosis.nextStep, isNotEmpty);
      }
    }
    expect(diagnoseOfflineVoiceFailure(
      const FormatException('Unknown invalid voice'),
      operation: OfflineVoiceOperation.inspectFolder,
    ).message, startsWith('Cannot inspect this voice folder.'));
  });


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

  test('offline catalog filters only verified locale, keeps corrupt warnings',
      () {
    InstalledOfflineVoicePack voice(String id, String locale) =>
        InstalledOfflineVoicePack(
          manifest: OfflineVoicePackManifest(
            id: id, displayName: id, locale: locale,
            licenseId: 'MIT',
            modelSha256: List.filled(64, 'a').join(),
            tokensSha256: List.filled(64, 'b').join(),
          ),
          modelPath: '/virtual/$id/model.onnx',
          tokensPath: '/virtual/$id/tokens.txt',
        );
    final entries = [
      OfflineVoicePackInspection(id: 'it-one', ready: true,
          installed: voice('it-one', 'it-IT')),
      const OfflineVoicePackInspection(id: 'broken', ready: false),
      OfflineVoicePackInspection(id: 'en-one', ready: true,
          installed: voice('en-one', 'en_US')),
    ];
    expect(installedOfflineVoiceLanguages(entries), ['en', 'it']);
    expect(filterInstalledOfflineVoicePacks(entries, 'it')
        .map((e) => e.id), ['it-one', 'broken']);
    expect(filterInstalledOfflineVoicePacks(entries, 'en')
        .map((e) => e.id), ['broken', 'en-one']);
    expect(filterInstalledOfflineVoicePacks(entries, null), entries);
    expect(() => filterInstalledOfflineVoicePacks(entries, 'it').clear(),
        throwsUnsupportedError);
    expect(offlinePackLanguage(entries[1]), isNull);
  });

  test('single-pack reconciliation preserves other voices and sorting',
      () async {
    final first = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    final otherManifest = OfflineVoicePackManifest(
      id: 'another-voice',
      displayName: 'Second narrator', locale: 'it-IT',
      licenseId: 'MIT',
      modelSha256: manifest.modelSha256,
      tokensSha256: manifest.tokensSha256,
    );
    final original = await inspectOfflineVoicePacks(
        modelsDirectory: installed);
    expect(original.map((entry) => entry.id),
        ['piper-en-test']);

    await installOfflineVoicePack(
      manifest: otherManifest,
      sourceDirectory: input, modelsDirectory: installed,
    );
    final changed = await inspectSingleOfflineVoicePack(
      packId: 'another-voice', modelsDirectory: installed,
    );
    expect(changed?.ready, isTrue);
    expect(changed?.verifiedDiskBytes, greaterThan(0));
    final merged = mergeOfflineVoicePackInspection(
        original, 'another-voice', changed);
    expect(merged.map((entry) => entry.id),
        ['another-voice', manifest.id]);
    expect(identical(merged.last, original.single), isTrue,
        reason: 'Unchanged models retain their prior verification result');
    expect(original, hasLength(1),
        reason: 'Merge cannot modify previous snapshots');
    expect(verifiedOfflineVoiceTotalBytes(merged),
        original.single.verifiedDiskBytes! + changed!.verifiedDiskBytes!);
    expect(() => merged.clear(), throwsUnsupportedError);

    final removed = await removeInstalledOfflineVoicePack(
      packId: otherManifest.id, modelsDirectory: installed,
    );
    expect(removed, isTrue);
    final missing = await inspectSingleOfflineVoicePack(
      packId: otherManifest.id, modelsDirectory: installed,
    );
    expect(missing, isNull);
    final afterRemoval = mergeOfflineVoicePackInspection(
        merged, otherManifest.id, missing);
    expect(afterRemoval.map((entry) => entry.id), [manifest.id]);
    expect(identical(afterRemoval.single, original.single), isTrue);
    expect(await File(first.modelPath).exists(), isTrue);
  });

  test('targeted verification demotes changed pack and preserves warnings',
      () async {
    final voice = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    final legacy = await Directory(
        p.join(installed.path, 'broken-voice')).create();
    await File(p.join(legacy.path, 'garbage.txt'))
        .writeAsBytes([1, 2]);
    final baseline = await inspectOfflineVoicePacks(
        modelsDirectory: installed);
    expect(baseline.map((e) => e.ready), [false, true]);
    await File(voice.tokensPath).writeAsBytes([0]);

    final damaged = await inspectSingleOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    );
    expect(damaged?.ready, isFalse);
    expect(damaged?.installed, isNull);
    expect(damaged?.verifiedDiskBytes, isNull);
    final snapshot = mergeOfflineVoicePackInspection(
        baseline, manifest.id, damaged);
    expect(snapshot.map((e) => e.ready), [false, false]);
    expect(identical(snapshot.first, baseline.first), isTrue);
    expect(verifiedOfflineVoiceTotalBytes(snapshot), 0);
    await expectLater(inspectSingleOfflineVoicePack(
      packId: '../wrong', modelsDirectory: installed,
    ), throwsFormatException);
    expect(() => mergeOfflineVoicePackInspection(
        baseline, manifest.id,
        const OfflineVoicePackInspection(id: 'wrong', ready: false)),
        throwsArgumentError);
  });

  test('verified catalog measures only manifest-approved model files',
      () async {
    final pack = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input,
      modelsDirectory: installed,
    );
    final broken = await Directory(
        p.join(installed.path, 'broken-voice')).create();
    await File(p.join(broken.path, 'unknown.dat'))
        .writeAsBytes(List.filled(1000, 7));

    final listed = await inspectOfflineVoicePacks(
        modelsDirectory: installed);
    final valid = listed.singleWhere((entry) => entry.id == manifest.id);
    final corrupt = listed.singleWhere(
        (entry) => entry.id == 'broken-voice');
    final expected = await File(pack.modelPath).length() +
        await File(pack.tokensPath).length() +
        await File(p.join(installed.path, manifest.id, 'voice-pack.json'))
            .length();
    expect(valid.ready, isTrue);
    expect(valid.verifiedDiskBytes, expected);
    expect(corrupt.ready, isFalse);
    expect(corrupt.verifiedDiskBytes, isNull,
        reason: 'Unknown files must not be counted as verified assets');
    expect(verifiedOfflineVoiceTotalBytes(listed), expected);
    expect(offlineVoiceSizeLabel(expected), endsWith(' B'));
    expect(offlineVoiceSizeLabel(1024), '1.0 KiB');
    expect(offlineVoiceSizeLabel(1024 * 1024), '1.0 MiB');
    expect(offlineVoiceSizeLabel(1024 * 1024 * 1024), '1.00 GiB');
    expect(() => offlineVoiceSizeLabel(-1), throwsArgumentError);
  });

  test('phonemizer assets contribute to reported size; damage hides total',
      () async {
    const phonemes = [1, 4, 2, 8, 16, 32, 64];
    final phonemizer = await Directory(
        p.join(input.path, 'espeak-ng-data')).create();
    await File(p.join(phonemizer.path, 'phonemes'))
        .writeAsBytes(phonemes);
    final enriched = OfflineVoicePackManifest(
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
    final pack = await installOfflineVoicePack(
      manifest: enriched, sourceDirectory: input,
      modelsDirectory: installed,
    );
    var catalog = await inspectOfflineVoicePacks(
        modelsDirectory: installed);
    final expected = await File(pack.modelPath).length() +
        await File(pack.tokensPath).length() +
        await File(p.join(installed.path, enriched.id, 'voice-pack.json'))
            .length() + phonemes.length;
    expect(catalog.single.verifiedDiskBytes, expected);
    expect(verifiedOfflineVoiceTotalBytes(catalog), expected);

    // A file that changes after installation must never be counted
    // as verified storage or silently passed to native model loading.
    await File(p.join(pack.phonemizerDataDir!, 'phonemes'))
        .writeAsBytes([0]);
    catalog = await inspectOfflineVoicePacks(modelsDirectory: installed);
    expect(catalog.single.ready, isFalse);
    expect(catalog.single.verifiedDiskBytes, isNull);
    expect(verifiedOfflineVoiceTotalBytes(catalog), 0);
  });

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


  test('persisted model manifest survives reopening after restart', () async {
    final first = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    final manifestFile = File(p.join(
        installed.path, manifest.id, 'voice-pack.json'));
    expect(await manifestFile.exists(), isTrue);
    final reopened = await loadInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    );
    expect(reopened.modelPath, first.modelPath);
    expect(reopened.manifest.displayName, manifest.displayName);
    expect(reopened.manifest.modelSha256, manifest.modelSha256);
    expect(reopened.manifest.phonemizerResources, isEmpty);
    expect(await folderContents(), [manifest.id]);
  });

  test('reinstall refuses a changed stored identity and metadata', () async {
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    final metadata = File(p.join(installed.path, manifest.id,
        'voice-pack.json'));
    final rewritten = manifest.toJson()
      ..['displayName'] = 'Unexpected changed voice';
    await metadata.writeAsString(jsonEncode(rewritten));
    await expectLater(loadInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
      expectedManifest: manifest,
    ), throwsFormatException);
    // The folder alone cannot authenticate a changed display name: without
    // an independent expected manifest, both data and hashes are self-supplied.
    final reopenedWithoutTrust = await loadInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    );
    expect(reopenedWithoutTrust.manifest.displayName,
        'Unexpected changed voice');
    await expectLater(installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    ), throwsFormatException);
  });

  test('unlisted files cannot hide inside an installed phonemizer tree',
      () async {
    final pack = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    final injected = File(p.join(p.dirname(pack.modelPath), 'extra.onnx'));
    await injected.writeAsBytes([8]);
    await expectLater(loadInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    ), throwsFormatException);
    expect(await injected.exists(), isTrue,
        reason: 'Verification must not delete or overwrite tampered sources');
  });

  test('corrupted voice metadata and unsafe reopen IDs fail closed',
      () async {
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    await expectLater(loadInstalledOfflineVoicePack(
      packId: '../unsafe', modelsDirectory: installed,
    ), throwsFormatException);
    final file = File(p.join(installed.path, manifest.id, 'voice-pack.json'));
    await file.writeAsString('not valid JSON');
    await expectLater(loadInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    ), throwsFormatException);
    expect(await folderContents(), [manifest.id]);
  });


  test('local catalog distinguishes verified voices from corrupt folders',
      () async {
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    await Directory(p.join(installed.path, 'broken-voice')).create();
    await Directory(p.join(installed.path, '.install-unfinished')).create();
    final scan = await inspectOfflineVoicePacks(modelsDirectory: installed);
    expect(scan.map((x) => x.id), ['broken-voice', manifest.id]);
    expect(scan.map((x) => x.ready), [false, true]);
    expect(scan.first.installed, isNull);
    expect(scan.last.installed?.manifest.modelSha256,
        manifest.modelSha256);
    expect(await Directory(p.join(installed.path, 'broken-voice')).exists(),
        isTrue, reason: 'Inspection must never delete a damaged model');
  });

  test('catalog bounds model count and never loads an unknown pack',
      () async {
    await Directory(p.join(installed.path, 'voice-a')).create(recursive: true);
    await Directory(p.join(installed.path, 'voice-b')).create(recursive: true);
    await expectLater(inspectOfflineVoicePacks(
      modelsDirectory: installed, maxEntries: 1,
    ), throwsFormatException);
    await expectLater(inspectOfflineVoicePacks(
      modelsDirectory: installed, maxEntries: 0,
    ), throwsArgumentError);
    expect(await inspectOfflineVoicePacks(
      modelsDirectory: Directory(p.join(root.path, 'not-installed')),
    ), isEmpty);
  });


  test('removal clears one installed pack and is idempotent', () async {
    final original = await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    expect(await File(original.modelPath).exists(), isTrue);
    expect(await removeInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    ), isTrue);
    expect(await File(original.modelPath).exists(), isFalse);
    expect(await inspectOfflineVoicePacks(modelsDirectory: installed), isEmpty);
    expect(await removeInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    ), isFalse);
    expect(await installed.list().toList(), isEmpty);
  });

  test('removal refuses traversal and foreign files', () async {
    final unrelated = File(p.join(root.path, 'do-not-delete.txt'));
    await unrelated.writeAsString('unchanged');
    for (final name in ['../do-not-delete', '/absolute', '..', 'A', '.hidden']) {
      await expectLater(removeInstalledOfflineVoicePack(
        packId: name, modelsDirectory: installed,
      ), throwsFormatException);
    }
    await installed.create();
    final wrongType = File(p.join(installed.path, 'not-a-folder'));
    await wrongType.writeAsString('not a voice');
    await expectLater(removeInstalledOfflineVoicePack(
      packId: 'not-a-folder', modelsDirectory: installed,
    ), throwsFormatException);
    expect(await wrongType.exists(), isTrue);
    expect(await unrelated.readAsString(), 'unchanged');
  });

  test('deletion removes only selected pack and leaves other voices', () async {
    await installOfflineVoicePack(
      manifest: manifest, sourceDirectory: input, modelsDirectory: installed,
    );
    final second = OfflineVoicePackManifest(
      id: 'second-model', displayName: 'Second voice', locale: 'en-US',
      licenseId: manifest.licenseId,
      modelSha256: manifest.modelSha256,
      tokensSha256: manifest.tokensSha256,
    );
    await installOfflineVoicePack(
      manifest: second, sourceDirectory: input, modelsDirectory: installed,
    );
    expect(await removeInstalledOfflineVoicePack(
      packId: manifest.id, modelsDirectory: installed,
    ), isTrue);
    final survivors = await inspectOfflineVoicePacks(modelsDirectory: installed);
    expect(survivors.map((x) => x.id), ['second-model']);
    expect(survivors.single.ready, isTrue);
  });


  Future<void> writeSourceManifest(OfflineVoicePackManifest voice) async {
    await File(p.join(input.path, 'voice-pack.json'))
        .writeAsString(jsonEncode(voice.toJson()));
  }

  test('folder preview describes a source without installing it', () async {
    await writeSourceManifest(manifest);
    final preview = await inspectOfflineVoiceImportFolder(
      sourceDirectory: input,
    );
    expect(preview.manifest.id, manifest.id);
    expect(preview.manifest.licenseId, 'MIT');
    expect(preview.totalBytes, 12);
    expect(await installed.exists(), isFalse,
        reason: 'Preview must not stage, install, or run inference');
    final pack = await installPreviewedOfflineVoicePack(
      preview: preview, modelsDirectory: installed,
    );
    expect(await File(pack.modelPath).readAsBytes(), [1, 2, 3, 4, 5, 6]);
    expect(await folderContents(), [manifest.id]);
  });

  test('preview refuses unknown files and missing manifest', () async {
    await expectLater(inspectOfflineVoiceImportFolder(
      sourceDirectory: input,
    ), throwsFormatException);
    await writeSourceManifest(manifest);
    await File(p.join(input.path, 'extra.dll')).writeAsBytes([0]);
    await expectLater(inspectOfflineVoiceImportFolder(
      sourceDirectory: input,
    ), throwsFormatException);
    expect(await installed.exists(), isFalse);
  });

  test('changed manifest after approval rejects install without staging',
      () async {
    await writeSourceManifest(manifest);
    final preview = await inspectOfflineVoiceImportFolder(
      sourceDirectory: input,
    );
    final changed = manifest.toJson()..['displayName'] = 'Changed name';
    await File(p.join(input.path, 'voice-pack.json'))
        .writeAsString(jsonEncode(changed));
    await expectLater(installPreviewedOfflineVoicePack(
      preview: preview, modelsDirectory: installed,
    ), throwsFormatException);
    expect(await installed.exists(), isFalse);
  });

  test('changed model bytes after preview never installs a corrupt voice',
      () async {
    await writeSourceManifest(manifest);
    final preview = await inspectOfflineVoiceImportFolder(
      sourceDirectory: input,
    );
    await File(p.join(input.path, 'model.onnx')).writeAsBytes([2, 2, 2]);
    await expectLater(installPreviewedOfflineVoicePack(
      preview: preview, modelsDirectory: installed,
    ), throwsFormatException);
    expect(await folderContents(), isEmpty);
  });

  test('source preview rejects an unsafe source without following links',
      () async {
    await expectLater(inspectOfflineVoiceImportFolder(
      sourceDirectory: Directory(p.join(root.path, 'absent')),
    ), throwsFormatException);
    await writeSourceManifest(manifest);
    await File(p.join(input.path, 'tokens.txt')).delete();
    await expectLater(inspectOfflineVoiceImportFolder(
      sourceDirectory: input,
    ), throwsFormatException);
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
