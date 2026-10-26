import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A prior source-edit accidentally appended a duplicate, malformed
/// declaration tail. Guard the shape of this critical offline model module
/// independently of analyzer output to make that regression explicit.
void main() {
  test('Windows voice manifest generator cannot overwrite or download',
      () async {
    final source =
        await File('tool/prepare-offline-voice-pack.ps1').readAsString();
    expect(source, contains('[IO.FileMode]::CreateNew'));
    expect(source, contains('Get-FileHash'));
    expect(source, contains('voice-pack.json already exists'));
    expect(source, contains('GetPathRoot'));
    expect(source, isNot(contains('Invoke-WebRequest')));
    expect(source, isNot(contains('Start-BitsTransfer')));
    expect(source, isNot(contains('curl.exe')));
  });

  test('voice pack declarations are unique in the checked-in source', () async {
    final text = await File('lib/data/offline_voice_pack.dart').readAsString();
    for (final declaration in [
      r'^class OfflineVoicePackManifest\b',
      r'^class InstalledOfflineVoicePack\b',
      r'^Future<InstalledOfflineVoicePack> installOfflineVoicePack\(',
      r'^Future<InstalledOfflineVoicePack> loadInstalledOfflineVoicePack\(',
      r'^Future<List<OfflineVoicePackInspection>> inspectOfflineVoicePacks\(',
    ]) {
      final matches =
          RegExp(declaration, multiLine: true).allMatches(text).length;
      expect(matches, 1, reason: 'Duplicated or missing: $declaration');
    }
  });
}
