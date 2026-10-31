import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_text_extractor.dart';

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

  test('TXT UTF-16 LE and BE open through the normal reader decoder',
      () async {
    const source = 'Capitolo 📖: “Pronto?”\nSì, disse Maria.';
    for (final littleEndian in [true, false]) {
      final file = File(p.join(root.path,
          littleEndian ? 'utf16-le.txt' : 'utf16-be.txt'));
      await file.writeAsBytes(<int>[
        ...littleEndian ? [0xff, 0xfe] : [0xfe, 0xff],
        for (final unit in source.codeUnits) ...[
          if (littleEndian) unit & 0xff else unit >> 8,
          if (littleEndian) unit >> 8 else unit & 0xff,
        ],
      ]);
      final result = await PrototypeDocumentDecoder().read(
          record(file.path, BookFormat.txt));
      expect(result.text, source);
      final bookmark = result.anchorAt(BookFormat.txt, source.indexOf('Sì'));
      expect(bookmark.localOffset, source.indexOf('Sì'));
      expect(result.offsetOf(bookmark), source.indexOf('Sì'));
    }
  });

  test('TXT Windows-1252 opens with exact punctuation and apostrophes',
      () async {
    final file = File(p.join(root.path, 'legacy-win.txt'));
    await file.writeAsBytes(<int>[
      0x93, 0x43, 0x69, 0x61, 0x6f, 0x94,
      0x20, 0x97, 0x20, 0x6c, 0x92, 0x61, 0x6d, 0x69, 0x63, 0x6f,
    ]);
    final result = await PrototypeDocumentDecoder().read(
        record(file.path, BookFormat.txt));
    expect(result.text, '“Ciao” — l’amico');
    expect(result.epubSpineRanges, isEmpty);
    expect(result.pdfPageRanges, isEmpty);
  });

  test('TXT binary content is rejected before reader or TTS can speak it',
      () async {
    final file = File(p.join(root.path, 'binary.txt'));
    await file.writeAsBytes(List.filled(64, 0));
    await expectLater(
      PrototypeDocumentDecoder().read(record(file.path, BookFormat.txt)),
      throwsFormatException,
    );
  });

  test('background EPUB decoding preserves the direct extractor model',
      () async {
    final archive = Archive()
      ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..add(ArchiveFile.string('META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OPS/content.opf"/>'
          '</rootfiles></container>'))
      ..add(ArchiveFile.string('OPS/content.opf',
          '<package><metadata><title>Background Test</title></metadata>'
          '<manifest><item id="a" href="Text/chapter.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="a"/></spine></package>'))
      ..add(ArchiveFile.string('OPS/Text/chapter.xhtml',
          '<html><body><h2>Chapter 📖</h2>'
          '<p>Unicode text <em>with style</em>.</p>'
          '<p>Another paragraph.</p></body></html>'));
    final zip = ZipEncoder().encodeBytes(archive);
    final file = File(p.join(root.path, 'background.epub'));
    await file.writeAsBytes(zip);
    final direct = const EpubTextExtractor().extract(zip);
    final decoded = await PrototypeDocumentDecoder().read(
        record(file.path, BookFormat.epub));
    expect(decoded.title, direct.title);
    expect(decoded.text, direct.text);
    expect(decoded.epubSpineRanges.length, direct.ranges.length);
    expect(decoded.epubSpineRanges.single.idref, direct.ranges.single.idref);
    expect(decoded.epubSpineRanges.single.start, direct.ranges.single.start);
    expect(decoded.epubSpineRanges.single.end, direct.ranges.single.end);
    expect(decoded.epubInlineStyles.length, direct.styles.length);
    expect(decoded.epubInlineStyles
        .any((style) => style.italic), isTrue);
    expect(decoded.epubDiagnostics.map((d) => d.code),
        direct.diagnostics.map((d) => d.code));
    expect(decoded.text, contains('Chapter 📖'));
  });

  test('background EPUB worker rejects invalid archives without fallback',
      () async {
    final file = File(p.join(root.path, 'unsafe.epub'));
    await file.writeAsBytes(utf8.encode('not a zip archive'));
    await expectLater(
      PrototypeDocumentDecoder().read(
          record(file.path, BookFormat.epub)),
      throwsFormatException,
    );
  });

  test('two EPUB decodes have isolated independent result objects',
      () async {
    final archive = Archive()
      ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..add(ArchiveFile.string('META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OPS/content.opf"/>'
          '</rootfiles></container>'))
      ..add(ArchiveFile.string('OPS/content.opf',
          '<package><manifest><item id="a" href="chapter.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="a"/></spine></package>'))
      ..add(ArchiveFile.string('OPS/chapter.xhtml',
          '<html><body><p>Chapter A 📖</p></body></html>'));
    final file = File(p.join(root.path, 'reopen.epub'));
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
    final decoder = PrototypeDocumentDecoder();
    final first = await decoder.read(record(file.path, BookFormat.epub));
    final second = await decoder.read(record(file.path, BookFormat.epub));
    expect(first.text, second.text);
    expect(first.epubSpineRanges.single.href,
        second.epubSpineRanges.single.href);
    expect(first.text, contains('📖'));
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
