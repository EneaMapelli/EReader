import 'dart:io';

import 'package:ereader/data/epub_bounded_file.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-bounded-zip-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('small archive bytes are read without modification', () async {
    final file = File(p.join(root.path, 'source.epub'));
    const bytes = [0x50, 0x4b, 0x03, 0x04, 0x01, 0x02, 0x03];
    await file.writeAsBytes(bytes);
    expect(readBoundedEpubFile(file.path, maxBytes: bytes.length), bytes);
    expect(readBoundedEpubFile(file.path), bytes);
  });

  test('oversized ZIP is rejected from file size before decompression', () async {
    final file = File(p.join(root.path, 'oversized.epub'));
    await file.writeAsBytes(List.filled(80, 0x41));
    expect(() => readBoundedEpubFile(file.path, maxBytes: 40),
        throwsFormatException);
  });

  test('worker may not override the global compressed ZIP safety quota',
      () {
    expect(() => readBoundedEpubFile('anything', maxBytes: 0),
        throwsArgumentError);
    expect(() => readBoundedEpubFile('anything',
        maxBytes: EpubTextExtractor.maxCompressedLength + 1),
        throwsArgumentError);
  });

  test('missing local file still reports an actionable filesystem error', () {
    expect(() => readBoundedEpubFile(p.join(root.path, 'missing.epub')),
        throwsA(isA<FileSystemException>()));
  });
}
