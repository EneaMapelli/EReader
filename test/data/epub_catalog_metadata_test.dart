import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_catalog_metadata.dart';
import 'package:ereader/data/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Uint8List _epub(String metadata, {String opfPath = 'OPS/content.opf'}) {
  final archive = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="$opfPath"/>'
      '</rootfiles></container>'))
    ..add(ArchiveFile.string(opfPath, '''
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0"
        xmlns:dc="http://purl.org/dc/elements/1.1/">
        <metadata>$metadata</metadata>
        <manifest><item id="chapter" href="chapter.xhtml"
          media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="chapter"/></spine>
      </package>
    '''))
    ..add(ArchiveFile.string('OPS/chapter.xhtml',
        '<html><body><p>A public test sentence.</p></body></html>'));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  const reader = EpubCatalogMetadataReader();

  test('EPUB2-style DC fields and Calibre series are read without XHTML',
      () {
    final result = reader.read(_epub('''
      <dc:title> An  Example  Novel </dc:title>
      <dc:creator>Mario Rossi</dc:creator>
      <dc:language>it_IT</dc:language>
      <meta name="calibre:series" content="La Saga Stellare"/>
    '''));
    expect(result.title, 'An Example Novel');
    expect(result.author, 'Mario Rossi');
    expect(result.language, 'it-IT');
    expect(result.series, 'La Saga Stellare');
  });

  test('EPUB3 collection metadata requires a series refinement', () {
    final result = reader.read(_epub('''
      <dc:title>A collection example</dc:title>
      <dc:creator>Alice Writer</dc:creator>
      <dc:creator>Bob Illustrator</dc:creator>
      <dc:language>en-US</dc:language>
      <meta property="belongs-to-collection" id="group">Cycle One</meta>
      <meta refines="#group" property="collection-type">series</meta>
    '''));
    expect(result.author, 'Alice Writer, Bob Illustrator');
    expect(result.series, 'Cycle One');
    expect(result.language, 'en-US');
  });

  test('unrelated EPUB3 collection is not treated as a series', () {
    final result = reader.read(_epub('''
      <dc:title>Standalone work</dc:title>
      <meta id="coll" property="belongs-to-collection">Imprint</meta>
      <meta refines="#coll" property="collection-type">set</meta>
    '''));
    expect(result.title, 'Standalone work');
    expect(result.series, isNull);
    expect(result.author, isNull);
  });

  test('invalid or oversized OPF fields are ignored rather than persisted',
      () {
    final result = reader.read(_epub('''
      <dc:title>  </dc:title>
      <dc:creator>NaN</dc:creator>
      <dc:language>../../private</dc:language>
      <meta name="calibre:series" content=""/>
    '''));
    expect(result.title, isNull);
    expect(result.author, isNull);
    expect(result.series, isNull);
    expect(result.language, isNull);
  });

  test('untrusted OPF root path and external entity are blocked', () {
    expect(() => reader.read(_epub('<dc:title>Title</dc:title>',
      opfPath: '../escape.opf')), throwsFormatException);
    final invalidXml = Archive()
      ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..add(ArchiveFile.string('META-INF/container.xml',
          '<!DOCTYPE foo [<!ENTITY xx SYSTEM "file:///etc/passwd">]>'
          '<container><rootfiles><rootfile full-path="OPS/content.opf"/>'
          '</rootfiles></container>'));
    expect(() => reader.read(ZipEncoder().encodeBytes(invalidXml)),
        throwsFormatException);
  });

  test('missing XML metadata fails safely', () {
    expect(() => reader.read(_epub('<dc:title>Book</dc:title>',
       opfPath: 'OPS/missing.opf')), returnsNormally);
    final malformed = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]);
    expect(() => reader.read(malformed), throwsA(isA<Exception>()));
  });

  group('SQLite book import integration', () {
    late Directory folder;
    late LibraryStore store;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('ereader-opf-import-');
      store = LibraryStore(homeDirectory: folder);
      await store.initialize();
    });
    tearDown(() async {
      store.dispose();
      if (await folder.exists()) await folder.delete(recursive: true);
    });

    test('import fills author, series, locale and title from OPF', () async {
      final source = File(p.join(folder.path, 'opaque_filename.epub'));
      await source.writeAsBytes(_epub('''
        <dc:title>OPF Actual Title</dc:title>
        <dc:creator>Test Author</dc:creator>
        <dc:language>it-IT</dc:language>
        <meta name="calibre:series" content="Test Series"/>
      '''));
      final book = await store.importFile(source.path);
      expect(book.title, 'OPF Actual Title');
      expect(book.author, 'Test Author');
      expect(book.series, 'Test Series');
      expect(book.language, 'it-IT');
      expect(store.getBook(book.id)!.author, 'Test Author');
      expect(store.books, hasLength(1));
    });

    test('dedup preserves manual metadata and reading progress', () async {
      final source = File(p.join(folder.path, 'first.epub'));
      await source.writeAsBytes(_epub('''
        <dc:title>Automatic title</dc:title>
        <dc:creator>Original Author</dc:creator>
      '''));
      final book = await store.importFile(source.path);
      final manuallyEdited = store.updateBookMetadata(book.id,
        title: 'My title', author: 'My author', series: 'My series',
        language: 'fr-FR');
      await store.savePosition(book.id, 15);
      final duplicate = await store.importFile(source.path);
      expect(duplicate.id, manuallyEdited.id);
      expect(duplicate.title, 'My title');
      expect(duplicate.author, 'My author');
      expect(duplicate.series, 'My series');
      expect(duplicate.language, 'fr-FR');
      expect(duplicate.progressOffset, 15);
    });

    test('damaged EPUB metadata falls back to the filename on import',
        () async {
      final file = File(p.join(folder.path, 'Fallback Name.epub'));
      await file.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4]);
      final book = await store.importFile(file.path);
      expect(book.title, 'Fallback Name');
      expect(book.author, isNull);
      expect(book.series, isNull);
      expect(book.language, isNull);
    });
  });
}
