import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for a previous downgrade to file_picker 3.0.4.
/// Android storage providers must be able to return stream-only files.
void main() {
  test('file picker v13 streams provider books and preserves batch safety',
      () async {
    final manifest = await File('pubspec.yaml').readAsString();
    final library =
        await File('lib/features/library/library_screen.dart').readAsString();
    final voices =
        await File('lib/features/reader/offline_voice_manager_screen.dart')
            .readAsString();

    expect(manifest, contains('file_picker: ^13.1.0'));
    expect(library, contains('FilePicker.pickFiles('));
    expect(library, contains('readAsByteStream: item.readAsByteStream'));
    expect(library, contains('allowedExtensions: const'));
    expect(library, isNot(contains('Stream<List<int>>.empty()')));
    expect(library, isNot(contains('FilePicker.platform.')));
    expect(voices, contains('FilePicker.getDirectoryPath()'));
    expect(library, contains('FilePicker.getDirectoryPath()'));
  });
}
