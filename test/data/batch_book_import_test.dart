import 'dart:io';

import 'package:ereader/data/batch_book_import.dart';
import 'package:ereader/domain/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ereader-batch-import-');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  BookRecord record(String id, String title) => BookRecord(
    id: id, title: title, localPath: '/managed/$id.txt',
    format: BookFormat.txt, importedAt: DateTime.utc(2026, 10, 27),
    progressOffset: 42,
  );

  BatchPickedBook streamed(String name, List<int> data) =>
      BatchPickedBook(
        name: name,
        pickedPath: null,
        readAsByteStream: () => Stream<List<int>>.value(data),
      );

  test('many stream-only SAF imports are isolated, ordered and cleaned up',
      () async {
    final progress = <String>[];
    final seen = <String>[];
    final result = await importPickedBooks(
      selections: [
        streamed('one.txt', [65]),
        streamed('invalid.epub', [1, 2]),
        streamed('two.txt', [66]),
        streamed('one-again.txt', [65]),
      ],
      knownBookIds: const [],
      stagingParent: temp,
      onProgress: (done, total) => progress.add('$done/$total'),
      importFile: (path, {originalName}) async {
        seen.add(originalName ?? '');
        final contents = await File(path).readAsBytes();
        if (originalName == 'invalid.epub') {
          throw const FormatException('Bad EPUB — no OPF document');
        }
        return record(String.fromCharCodes(contents), originalName!);
      },
    );
    expect(progress, ['1/4', '2/4', '3/4', '4/4']);
    expect(seen, ['one.txt', 'invalid.epub', 'two.txt', 'one-again.txt']);
    expect(result.selectedCount, 4);
    expect(result.completedCount, 4);
    expect(result.addedCount, 2);
    expect(result.existingCount, 1);
    expect(result.failedCount, 1);
    expect(result.notProcessedCount, 0);
    expect(result.entries.map((x) => x.outcome), [
      BookImportOutcome.added,
      BookImportOutcome.invalid,
      BookImportOutcome.added,
      BookImportOutcome.alreadyPresent,
    ]);
    expect(result.entries.last.book!.progressOffset, 42);
    expect(await temp.list().toList(), isEmpty,
        reason: 'Every SAF staging directory must be deleted');
  });

  test('preexisting content hashes never reset reading progress', () async {
    final old = record('A', 'Previously imported');
    final result = await importPickedBooks(
      selections: [streamed('duplicate.txt', [65])],
      knownBookIds: [old.id],
      stagingParent: temp,
      importFile: (path, {originalName}) async => old,
    );
    expect(result.addedCount, 0);
    expect(result.existingCount, 1);
    expect(result.onlySuccessfulBook, same(old));
    expect(result.onlySuccessfulBook!.progressOffset, 42);
  });

  test('one item failing IO does not abort later imports', () async {
    var count = 0;
    final result = await importPickedBooks(
      selections: [
        BatchPickedBook(
          name: 'offline.pdf',
          pickedPath: null,
          readAsByteStream: () => Stream<List<int>>.error(
              const FileSystemException('Unavailable provider file')),
        ),
        streamed('good.txt', [72, 105]),
      ],
      stagingParent: temp,
      knownBookIds: const [],
      importFile: (path, {originalName}) async {
        count++;
        return record('good', originalName!);
      },
    );
    expect(result.entries.map((e) => e.outcome), [
      BookImportOutcome.unavailable,
      BookImportOutcome.added,
    ]);
    expect(count, 1);
    expect(await temp.list().toList(), isEmpty);
  });

  test('Cancel stops only later files and preserves already imported books',
      () async {
    var cancel = false;
    var count = 0;
    final result = await importPickedBooks(
      selections: [
        streamed('one.txt', [1]), streamed('two.txt', [2]),
        streamed('three.txt', [3]),
      ],
      knownBookIds: const [],
      stagingParent: temp,
      cancelRemaining: () => cancel,
      onProgress: (done, _) {
        if (done == 1) cancel = true;
      },
      importFile: (path, {originalName}) async {
        count++;
        return record('id-$count', originalName!);
      },
    );
    expect(count, 1);
    expect(result.addedCount, 1);
    expect(result.notProcessedCount, 2);
    expect(result.completedCount, 1);
    expect(await temp.list().toList(), isEmpty);
  });

  test('batch limit rejects all selections before any file read or write',
      () async {
    var touched = false;
    final files = List.generate(51, (index) => BatchPickedBook(
      name: 'book-$index.txt', pickedPath: null,
      readAsByteStream: () {
        touched = true;
        return Stream<List<int>>.value([1]);
      },
    ));
    await expectLater(importPickedBooks(
      selections: files,
      knownBookIds: const [],
      stagingParent: temp,
      importFile: (path, {originalName}) async => record('one', 'One'),
    ), throwsFormatException);
    expect(touched, isFalse);
    expect(await temp.list().toList(), isEmpty);
    await expectLater(importPickedBooks(
      selections: const [],
      knownBookIds: const [],
      maxSelections: 51,
      importFile: (path, {originalName}) async => record('one', 'One'),
    ), throwsArgumentError);
  });

  test('unexpected import failures are classified without exposing secrets',
      () async {
    final result = await importPickedBooks(
      selections: [streamed('secret-book.txt', [2, 3])],
      knownBookIds: const [],
      stagingParent: temp,
      importFile: (path, {originalName}) async =>
          throw StateError('private path /Users/owner/secret-book.txt'),
    );
    expect(result.entries.single.outcome, BookImportOutcome.failed);
    expect(result.entries.single.book, isNull);
    expect(result.failedCount, 1);
    expect(result.onlySuccessfulBook, isNull);
    expect(await temp.list().toList(), isEmpty);
  });

  test('empty picker selection is a harmless no-op', () async {
    final result = await importPickedBooks(
      selections: const [],
      knownBookIds: const [],
      stagingParent: temp,
      importFile: (path, {originalName}) async =>
          throw StateError('must not call importer'),
    );
    expect(result.completedCount, 0);
    expect(result.selectedCount, 0);
    expect(result.failedCount, 0);
    expect(result.notProcessedCount, 0);
  });
}
