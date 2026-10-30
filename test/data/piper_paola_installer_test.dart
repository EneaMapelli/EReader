import 'dart:io';

import 'package:ereader/data/piper_paola_installer.dart';
import 'package:ereader/data/curated_voice_staging.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Curated Paola crash-safe temporary recovery', () {
    late Directory root;
    late Directory staging;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ereader-paola-staging-');
      staging = await Directory(p.join(root.path, 'voice-downloads'))
          .create();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<Directory> candidate({bool marked = true}) async {
      final folder = await staging.createTemp(CuratedVoiceStaging.prefix);
      await File(p.join(folder.path,
          CuratedVoiceStaging.leaseName)).create();
      if (marked) {
        await File(p.join(folder.path, CuratedVoiceStaging.markerName))
            .writeAsString(CuratedVoiceStaging.markerContent);
      }
      await File(p.join(folder.path, PiperPaolaCatalog.archiveName))
          .writeAsBytes([1, 2, 3]);
      return folder;
    }

    test('old marked session is removed but unmarked and unrelated remain',
        () async {
      final abandoned = await candidate();
      final unmarked = await candidate(marked: false);
      final unrelated = await Directory(p.join(staging.path, 'user-files'))
          .create();
      await File(p.join(unrelated.path, 'keep.txt'))
          .writeAsString('private');
      final removed = await CuratedVoiceStaging.recoverAbandoned(
          staging, minimumAge: Duration.zero);
      expect(removed, 1);
      expect(await abandoned.exists(), isFalse);
      expect(await unmarked.exists(), isTrue);
      expect(await File(p.join(unrelated.path, 'keep.txt'))
          .readAsString(), 'private');
    });

    test('a live marked session and freshly created stage are not removed',
        () async {
      final live = await CuratedVoiceStaging.create(staging);
      final crashed = await candidate();
      expect(await CuratedVoiceStaging.recoverAbandoned(
          staging, minimumAge: Duration.zero), 1);
      expect(await live.directory.exists(), isTrue);
      expect(await crashed.exists(), isFalse);
      final recent = await candidate();
      expect(await CuratedVoiceStaging.recoverAbandoned(staging), 0);
      expect(await recent.exists(), isTrue);
      await live.finish();
      await live.finish();
      expect(await live.directory.exists(), isFalse);
    });

    test('expired staging is eligible while a recent copy is protected',
        () async {
      final old = await candidate();
      final fresh = await candidate();
      await File(p.join(old.path, CuratedVoiceStaging.markerName))
          .setLastModified(DateTime.now().subtract(
              const Duration(days: 3)));
      expect(await CuratedVoiceStaging.recoverAbandoned(staging), 1);
      expect(await old.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
    });

    test('wrong marker and unexpected nested files fail closed',
        () async {
      final malformed = await candidate();
      await File(p.join(malformed.path, CuratedVoiceStaging.markerName))
          .writeAsString('UNTRUSTED');
      final unexpected = await candidate();
      await File(p.join(unexpected.path, 'unknown.txt'))
          .writeAsString('leave alone');
      final removed = await CuratedVoiceStaging.recoverAbandoned(
          staging, minimumAge: Duration.zero);
      expect(removed, 0);
      expect(await malformed.exists(), isTrue);
      expect(await unexpected.exists(), isTrue);
    });

    test('marked extraction tree is deleted only within the owned stage',
        () async {
      final owned = await candidate();
      final generated = await Directory(p.join(
          owned.path, 'unpacked', 'vits-piper-it_IT-paola-medium',
          'espeak-ng-data', 'voices')).create(recursive: true);
      await File(p.join(generated.path, 'it'))
          .writeAsString('test phoneme data');
      expect(await CuratedVoiceStaging.recoverAbandoned(
          staging, minimumAge: Duration.zero), 1);
      expect(await owned.exists(), isFalse);
    });

    test('symlink in staging cannot trigger recursive deletion', () async {
      if (Platform.isWindows) return;
      final external = File(p.join(root.path, 'outside.txt'));
      await external.writeAsString('safe');
      final stage = await candidate();
      await Link(p.join(stage.path, 'prepared'))
          .create(external.path);
      expect(await CuratedVoiceStaging.recoverAbandoned(
          staging, minimumAge: Duration.zero), 0);
      expect(await stage.exists(), isTrue);
      expect(await external.readAsString(), 'safe');
    });
  });

  group('Curated Piper Paola model integrity', () {
    test('fixed official archive URL and digest cannot be swapped at runtime',
        () {
      expect(PiperPaolaCatalog.archiveUrl,
          startsWith('https://github.com/k2-fsa/sherpa-onnx/releases/'));
      expect(PiperPaolaCatalog.archiveUrl,
          endsWith('vits-piper-it_IT-paola-medium.tar.bz2'));
      expect(PiperPaolaCatalog.archiveName,
          'vits-piper-it_IT-paola-medium.tar.bz2');
      expect(PiperPaolaCatalog.sha256Digest, hasLength(64));
      expect(PiperPaolaCatalog.verifyArchiveDigest(
          PiperPaolaCatalog.sha256Digest), isTrue);
      expect(PiperPaolaCatalog.verifyArchiveDigest(List<String>.filled(64, '0').join()), isFalse);
      expect(PiperPaolaCatalog.locale, 'it-IT');
    });

    test('allowed paths include official eSpeak voice variants but no escape',
        () {
      for (final name in [
        'espeak-ng-data/it_dict',
        'espeak-ng-data/voices/!v/f1',
        'espeak-ng-data/lang/roa/it',
        'espeak-ng-data/phontab',
        'espeak-ng-data/lang/en/en-us',
      ]) {
        expect(PiperPaolaCatalog.allowedPhonemizerPath(name), isTrue,
            reason: name);
      }
      for (final name in [
        '../voice',
        '/absolute',
        'espeak-ng-data/../model.onnx',
        'espeak-ng-data/../../unsafe',
        'espeak-ng-data//it_dict',
        'espeak-ng-data/C:/windows',
        'espeak-ng-data/NUL.txt',
        'espeak-ng-data/COM1',
        'espeak-ng-data/.',
        'espeak-ng-data/it_dict.',
        'espeak-ng-data/it\\_dict',
        'other-folder/it_dict',
      ]) {
        expect(PiperPaolaCatalog.allowedPhonemizerPath(name), isFalse,
            reason: name);
      }
    });

    test('small and corrupted downloads rejected before any extraction',
        () async {
      final directory = await Directory.systemTemp
          .createTemp('ereader-paola-corrupt-');
      try {
        final archive = File('${directory.path}/broken.tar.bz2');
        await archive.writeAsBytes([1, 2, 3]);
        await expectLater(verifyPiperPaolaArchive(archive),
            throwsFormatException);
        await archive.writeAsBytes(List<int>.filled(1024 * 1024 + 1, 0));
        await expectLater(verifyPiperPaolaArchive(archive),
            throwsFormatException);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('large archive is rejected before hashing or native decompression',
        () async {
      final dir = await Directory.systemTemp
          .createTemp('ereader-paola-too-large-');
      try {
        final archive = File('${dir.path}/large.tar.bz2');
        final handle = await archive.open(mode: FileMode.write);
        try {
          await handle.truncate(PiperPaolaCatalog.maxDownloadBytes + 1);
        } finally {
          await handle.close();
        }
        await expectLater(verifyPiperPaolaArchive(archive),
            throwsFormatException);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
