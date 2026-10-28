import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-only bootstrap assertions; native Android share grants still need QA.
void main() {
  test('share entrypoint keeps audio_service and bounded document streaming',
      () async {
    final native = await File('tool/android/MainActivity.kt').readAsString();
    final manifest =
        await File('tool/android/AndroidManifest.xml').readAsString();
    final script = await File('tool/bootstrap.sh').readAsString();
    expect(native, contains('class MainActivity : AudioServiceActivity()'));
    expect(native, contains('Intent.ACTION_SEND'));
    expect(native, contains('Intent.ACTION_SEND_MULTIPLE'));
    expect(native, contains('contentResolver.openInputStream(item.uri)'));
    expect(native, contains('ByteArray(64 * 1024)'));
    expect(native, contains('if (sources.size < 50)'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
    expect(manifest, isNot(contains('android.permission.READ_EXTERNAL_STORAGE')));
    expect(script, contains('tool/android/MainActivity.kt'));
  });
}
