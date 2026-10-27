import 'dart:io';

import 'package:ereader/data/piper_paola_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
