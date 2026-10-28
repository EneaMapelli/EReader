import 'dart:async';
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

  test('SAF content URI is consumed only through provider byte stream',
      () async {
    var calls = 0;
    final result = await importPickedBook<String>(
      originalName: 'Private.pdf',
      pickedPath: 'content://documents/document/private-epub',
      stagingParent: root,
      readAsByteStream: () {
        calls++;
        return Stream<List<int>>.fromIterable([[37, 80], [68, 70]]);
      },
      importFile: (path, {originalName}) async {
        expect(path, isNot(contains('content://')));
        expect(await File(path).readAsBytes(), [37, 80, 68, 70]);
        expect(originalName, 'Private.pdf');
        return 'saved';
      },
    );
    expect(result, 'saved');
    expect(calls, 1);
    expect(await root.list().toList(), isEmpty);
  });

  test('stalled SAF/cloud stream times out, cancels and removes staging',
      () async {
    var canceled = false;
    late StreamController<List<int>> provider;
    provider = StreamController<List<int>>(onCancel: () {
      canceled = true;
    });
    var imported = false;
    await expectLater(
      importPickedBook<String>(
        originalName: 'Cloud.pdf',
        pickedPath: null,
        stagingParent: root,
        providerIdleTimeout: const Duration(milliseconds: 25),
        readAsByteStream: () => provider.stream,
        importFile: (path, {originalName}) async {
          imported = true;
          return 'unexpected';
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(canceled, isTrue);
    expect(imported, isFalse);
    expect(await root.list().toList(), isEmpty);
    await provider.close();
  });

  test('active slow provider succeeds when every chunk arrives in time',
      () async {
    final result = await importPickedBook<int>(
      originalName: 'Remote.epub',
      pickedPath: 'content://some-provider/saf',
      stagingParent: root,
      providerIdleTimeout: const Duration(milliseconds: 150),
      readAsByteStream: () async* {
        yield [1, 2];
        await Future<void>.delayed(const Duration(milliseconds: 10));
        yield [3, 4];
      },
      importFile: (path, {originalName}) async {
        expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
        return 4;
      },
    );
    expect(result, 4);
    expect(await root.list().toList(), isEmpty);
  });

  test('nonpositive idle timeout is rejected without touching provider',
      () async {
    var accessed = false;
    await expectLater(importPickedBook<int>(
      originalName: 'Idle.txt',
      pickedPath: null,
      stagingParent: root,
      providerIdleTimeout: Duration.zero,
      readAsByteStream: () {
        accessed = true;
        return const Stream<List<int>>.empty();
      },
      importFile: (path, {originalName}) async => 1,
    ), throwsArgumentError);
    expect(accessed, isFalse);
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
