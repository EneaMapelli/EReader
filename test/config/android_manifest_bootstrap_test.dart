import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// These checks validate committed bootstrap configuration only.
/// They do not replace an Android manifest-merger/device smoke test.
void main() {
  test('tracked Android media manifest declares required service and controls',
      () async {
    final manifest = await File('tool/android/AndroidManifest.xml')
        .readAsString();
    for (final required in [
      'android:name=".MainActivity"',
      'com.ryanheise.audioservice.AudioService',
      'com.ryanheise.audioservice.MediaButtonReceiver',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      'android.permission.WAKE_LOCK',
      'android:foregroundServiceType="mediaPlayback"',
    ]) {
      expect(manifest, contains(required), reason: required);
    }
  });

  test('local bootstraps and Android CI all install the same media manifest',
      () async {
    final scriptWindows = await File('tool/bootstrap.ps1').readAsString();
    final scriptUnix = await File('tool/bootstrap.sh').readAsString();
    final ci = await File('.github/workflows/manual-verify.yml')
        .readAsString();

    expect(scriptWindows, contains('tool/android/AndroidManifest.xml'));
    expect(scriptWindows,
        contains('android/app/src/main/AndroidManifest.xml'));
    expect(scriptWindows, contains('tool/android/MainActivity.kt'));
    expect(scriptUnix, contains('tool/android/AndroidManifest.xml'));
    expect(scriptUnix,
        contains('android/app/src/main/AndroidManifest.xml'));
    expect(scriptUnix, contains('tool/android/MainActivity.kt'));
    expect(ci, contains('tool/android/AndroidManifest.xml'));
    expect(ci, contains('tool/android/MainActivity.kt'));
    expect(ci, contains('android/app/src/main/AndroidManifest.xml'));

    final copyIndex = ci.indexOf('cp tool/android/AndroidManifest.xml');
    final buildIndex = ci.indexOf('run: flutter build apk --debug');
    expect(copyIndex, greaterThan(0));
    expect(buildIndex, greaterThan(copyIndex),
        reason: 'CI must apply the media manifest before compiling Android');
  });
}
