import 'package:flutter_test/flutter_test.dart';

import 'offline_vits_soak.dart' as soak;

/// Explicit manual harness outside the regular test/ suite:
///   flutter test tool/offline_vits_soak_test.dart
///   flutter test tool/offline_vits_soak_test.dart --dart-define=EREADER_SOAK_ITERATIONS=500
///
/// Flutter-test supplies the dart:ui runtime used by plugin imports.
/// It does not compile EReader's Windows executable or launch Actions.
void main() {
  const iterations = int.fromEnvironment(
    'EREADER_SOAK_ITERATIONS', defaultValue: 200,
  );
  test('manual synthetic VITS long-session cleanup', () async {
    await soak.main(['--iterations', iterations.toString()]);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
