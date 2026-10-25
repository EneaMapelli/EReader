import 'dart:io';

import 'package:ereader/data/picked_book_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-picker-test-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('existing desktop path avoids copying the file or opening SAF stream',
      () async {
    final source = File('${root.path}${Platform.pathSeparator}original.epub');
    await source.writeAsString('Offline reading source');
    var streamCalls = 0;
    final imported = await importPickedBook<String>(
      originalName: 'Actual title.EPUB',
      pickedPath: source.path,
      stagingParent: root,
      readAsByteStream: () {
        streamCalls++;
        throw StateError('Existing file must not open stream');
      },
      importFile: (path, {originalName}) async {
        expect(path, source.path);
        expect(originalName, 'Actual title.EPUB');
        return File(path).readAsString();
      },
    );
    expect(imported, 'Offline reading source');
    expect(streamCalls, 0);
    expect(await root.list().length, 1);
  });

  test('stream-only Android selection stages bytes and removes temp files',
      () async {
    String? stagedPath;
    final imported = await importPickedBook<String>(
      originalName: 'Reading.epub',
      pickedPath: null,
      stagingParent: root,
      readAsByteStream: () => Stream<List<int>>.fromIterable([
        [1, 2], [], [3, 4, 5],
      ]),
      importFile: (path, {originalName}) async {
        stagedPath = path;
        expect(originalName, 'Reading.epub');
        expect(await File(path).readAsBytes(), [1, 2, 3, 4, 5]);
        return 'imported';
      },
    );
    expect(imported, 'imported');
    expect(await File(stagedPath!).exists(), isFalse);
    expect(await root.list().toList(), isEmpty);
  });

  test('missing cached path falls back to provider byte stream', () async {
    final imported = await importPickedBook<int>(
      originalName: 'Poem.txt',
      pickedPath: '${root.path}${Platform.pathSeparator}missing.txt',
      stagingParent: root,
      readAsByteStream: () => Stream<List<int>>.value([65, 66, 67]),
      importFile: (path, {originalName}) async =>
          (await File(path).readAsBytes()).length,
    );
    expect(imported, 3);
    expect(await root.list().toList(), isEmpty);
  });

  test('oversized streams reject before crossing the bound and clean up',
      () async {
    var importerCalls = 0;
    await expectLater(importPickedBook<int>(
      originalName: 'Limit.pdf',
      pickedPath: null,
      stagingParent: root,
      maxBytes: 5,
      readAsByteStream: () => Stream<List<int>>.fromIterable([
        [1, 2, 3], [4, 5, 6],
      ]),
      importFile: (path, {originalName}) async {
        importerCalls++;
        return 1;
      },
    ), throwsFormatException);
    expect(importerCalls, 0);
    expect(await root.list().toList(), isEmpty);
  });

  test('empty streams and import errors also remove their temporary source',
      () async {
    await expectLater(importPickedBook<int>(
      originalName: 'Empty.txt',
      pickedPath: null,
      stagingParent: root,
      readAsByteStream: () => const Stream<List<int>>.empty(),
      importFile: (path, {originalName}) async => 1,
    ), throwsFormatException);
    expect(await root.list().toList(), isEmpty);

    await expectLater(importPickedBook<int>(
      originalName: 'Broken.epub',
      pickedPath: null,
      stagingParent: root,
      readAsByteStream: () => Stream<List<int>>.value([1, 2, 3]),
      importFile: (path, {originalName}) async =>
          throw const FormatException('Invalid format'),
    ), throwsFormatException);
    expect(await root.list().toList(), isEmpty);
  });

  test('unsupported extensions and invalid budgets fail before reading',
      () async {
    var reads = 0;
    Stream<List<int>> stream() {
      reads++;
      return Stream<List<int>>.value([1, 2, 3]);
    }
    Future<int> unused(String path, {String? originalName}) async => 1;

    await expectLater(importPickedBook<int>(
      originalName: 'Archive.zip', pickedPath: null,
      stagingParent: root, readAsByteStream: stream,
      importFile: unused,
    ), throwsFormatException);
    await expectLater(importPickedBook<int>(
      originalName: 'Book.txt', pickedPath: null,
      stagingParent: root, maxBytes: 100 * 1024 * 1024 + 1,
      readAsByteStream: stream, importFile: unused,
    ), throwsArgumentError);
    expect(reads, 0);
    expect(await root.list().toList(), isEmpty);
  });
}
