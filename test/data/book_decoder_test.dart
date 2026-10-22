import 'dart:io';

import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/domain/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-decoder-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  BookRecord record(String path, BookFormat format) => BookRecord(
    id: 'file',
    title: 'A book',
    localPath: path,
    format: format,
    importedAt: DateTime.utc(2026, 10, 22),
  );

  test('TXT UTF-8 BOM is removed while Unicode text is preserved', () async {
    final file = File(p.join(root.path, 'unicode.txt'));
    await file.writeAsBytes([
      0xEF, 0xBB, 0xBF, // UTF-8 BOM
      0x43, 0x69, 0x61, 0x6F, 0x20, // "Ciao "
      0xF0, 0x9F, 0x93, 0x96, // book emoji
    ]);
    final data = await PrototypeDocumentDecoder().read(
      record(file.path, BookFormat.txt),
    );
    expect(data.title, 'A book');
    expect(data.text, 'Ciao 📖');
    expect(data.pdfPageRanges, isEmpty);
  });

  test('missing source reports a filesystem error', () async {
    final file = File(p.join(root.path, 'missing.txt'));
    await expectLater(
      PrototypeDocumentDecoder().read(record(file.path, BookFormat.txt)),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('page offsets retain exact correspondence with extracted string', () {
    const content = DocumentContent(
      text: 'A page\n\nSecond',
      title: 'Sample',
      pdfPageRanges: [
        PdfPageRange(1, 0, 6),
        PdfPageRange(2, 8, 14),
      ],
    );
    expect(
      content.text.substring(content.pdfPageRanges.last.start),
      'Second',
    );
  });
}
