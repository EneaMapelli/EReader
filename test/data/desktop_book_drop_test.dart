import 'dart:io';

import 'package:ereader/data/batch_book_import.dart';
import 'package:ereader/data/desktop_book_drop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BatchPickedBook candidate(String name, {String? path,
      void Function()? onRead}) => BatchPickedBook(
    name: name,
    pickedPath: path,
    readAsByteStream: () {
      onRead?.call();
      return Stream<List<int>>.value([0x42]);
    },
  );

  test('Windows multi-drop selects only supported formats in original order',
      () {
    final chosen = classifyDesktopBookDrop([
      candidate('Alice.EPUB'),
      candidate('cover.jpg'),
      candidate('report.pdf'),
      candidate('README.TXT'),
      candidate('website.url'),
    ]);
    expect(chosen.accepted.map((item) => item.name).toList(),
        ['Alice.EPUB', 'report.pdf', 'README.TXT']);
    expect(chosen.unsupportedNames, ['cover.jpg', 'website.url']);
    expect(chosen.rejectedCount, 2);
  });

  test('dropped file source path is NEVER trusted for reading', () {
    final chosen = classifyDesktopBookDrop([
      candidate('story.epub', path: r'C:\Users\Alice\story.epub'),
      candidate(r'C:\Shared\book.txt',
          path: 'https://example.invalid/private'),
    ]);
    expect(chosen.accepted.map((item) => item.name),
        ['story.epub', 'book.txt']);
    expect(chosen.accepted.every((item) => item.pickedPath == null), isTrue);
  });

  test('no dropped file stream is opened while filtering or preflighting',
      () {
    var reads = 0;
    final chosen = classifyDesktopBookDrop([
      candidate('a.epub', onRead: () => reads++),
      candidate('notes.md', onRead: () => reads++),
    ]);
    expect(reads, 0);
    expect(chosen.accepted, hasLength(1));
    final stream = chosen.accepted.single.readAsByteStream();
    expect(stream, isA<Stream<List<int>>>());
    expect(reads, 1);
  });

  test('trailing whitespace and Windows path separators are sanitized', () {
    expect(safeDroppedBookName(r'C:\Private\A reader.TXT '),
        'A reader.TXT');
    expect(safeDroppedBookName('/private/user/Story.epub'),
        'Story.epub');
    expect(safeDroppedBookName('hello\n.pdf'), 'hello .pdf');
    expect(safeDroppedBookName('    '), isEmpty);
    expect(safeDroppedBookName('..'), isEmpty);
  });

  test('unsupported filenames never reach the import pipeline', () {
    final chosen = classifyDesktopBookDrop([
      candidate('malware.exe'),
      candidate('book.epub.exe'),
      candidate('book.epub?download=1'),
      candidate('book.epub'),
      candidate('README'),
    ]);
    expect(chosen.accepted, hasLength(1));
    expect(chosen.accepted.single.name, 'book.epub');
    expect(chosen.rejectedCount, 4);
  });

  test('50-file limit rejects the entire drop before touching streams',
      () {
    var touched = false;
    final many = List.generate(51, (i) => candidate(
        'book-$i.txt', onRead: () => touched = true));
    expect(() => classifyDesktopBookDrop(many), throwsFormatException);
    expect(touched, isFalse);
    expect(classifyDesktopBookDrop(many.take(50).toList()).accepted,
        hasLength(50));
    expect(() => classifyDesktopBookDrop([], maxFiles: 51),
        throwsArgumentError);
  });

  test('empty/all unsupported selections are safe no-ops', () {
    final empty = classifyDesktopBookDrop([]);
    expect(empty.accepted, isEmpty);
    expect(empty.unsupportedNames, isEmpty);
    final nonbooks = classifyDesktopBookDrop([
      candidate('folder'),
      candidate('https://example.com/book'),
    ]);
    expect(nonbooks.accepted, isEmpty);
    expect(nonbooks.rejectedCount, 2);
  });

  test('format name case is preserved, path is removed and unsupported ignored',
      () {
    final chosen = classifyDesktopBookDrop([
      candidate(r'D:\Work\Novel.PDF'),
      candidate('archive.zip'),
      candidate('.epub'),
    ]);
    expect(chosen.accepted.map((item) => item.name).toList(),
        ['Novel.PDF', '.epub']);
    expect(chosen.unsupportedNames, ['archive.zip']);
  });

  test('mixed dropped batch remains compatible with standard batch importer',
      () async {
    final staging = await Directory.systemTemp
        .createTemp('ereader-desktop-drop-test-');
    try {
      final selection = classifyDesktopBookDrop([
        candidate('first.txt'),
        candidate('bad.exe'),
        candidate('duplicate.txt'),
      ]);
      var index = 0;
      final result = await importPickedBooks(
        selections: selection.accepted,
        stagingParent: staging,
        knownBookIds: const [],
        importFile: (path, {originalName}) async {
          // Verify stages rather than the dropped absolute Windows paths
          // are read. The actual importer performs content hash/signature.
          expect(await File(path).exists(), isTrue);
          index++;
          throw const FormatException('Deliberately invalid fixture');
        },
      );
      expect(index, 2);
      expect(result.failedCount, 2);
      expect(selection.unsupportedNames, ['bad.exe']);
    } finally {
      await staging.delete(recursive: true);
    }
  });
}
