import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_catalog_metadata.dart';
import 'package:ereader/data/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final Uint8List _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mP8/x8AAwMCAO+jX6kAAAAASUVORK5CYII=',
));

Uint8List _fixture({bool epub3 = true, bool declared = true,
    String href = 'images/cover.png', Uint8List? image}) {
  final metadata = declared && !epub3
      ? '<meta name="cover" content="front"/>' : '';
  final properties = declared && epub3 ? ' properties="cover-image"' : '';
  final bytes = image ?? _png;
  final zip = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OPS/content.opf"/>'
      '</rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/content.opf', '''
      <package xmlns="http://www.idpf.org/2007/opf"
          xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0">
        <metadata><dc:title>Cover Test</dc:title>$metadata</metadata>
        <manifest>
          <item id="front" href="$href" media-type="image/png"$properties/>
          <item id="chapter" href="body.xhtml"
                media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="chapter"/></spine>
      </package>
    '''))
    ..add(ArchiveFile.string('OPS/body.xhtml',
      '<html><body><p>Public cover test passage.</p></body></html>'))
    ..add(ArchiveFile('OPS/images/cover.png', bytes.length, bytes));
  return ZipEncoder().encodeBytes(zip);
}

void main() {
  const reader = EpubCatalogMetadataReader();
  test('EPUB3 manifest cover property selects validated bytes', () {
    final info = reader.read(_fixture());
    expect(info.coverBytes, orderedEquals(_png));
    expect(info.coverExtension, 'png');
  });
  test('EPUB2 metadata cover ID selects validated bytes', () {
    final info = reader.read(_fixture(epub3: false));
    expect(info.coverBytes, orderedEquals(_png));
    expect(info.coverExtension, 'png');
  });
  test('images without explicit cover declaration are ignored', () {
    expect(reader.read(_fixture(declared: false)).coverBytes, isNull);
  });
  test('bad raster and remote URLs are rejected without losing OPF title', () {
    final bad = Uint8List.fromList(_png);
    bad[19] = 255;
    final result = reader.read(_fixture(image: bad));
    expect(result.coverBytes, isNull);
    expect(result.title, 'Cover Test');
    expect(reader.read(_fixture(
      href: 'https://example.invalid/cover.png')).coverBytes, isNull);
  });

  group('SQLite private covers', () {
    late Directory home;
    late LibraryStore store;
    late File source;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('ereader-cover-test-');
      store = LibraryStore(homeDirectory: home);
      await store.initialize();
      source = File(p.join(home.path, 'example.epub'));
      await source.writeAsBytes(_fixture());
    });
    tearDown(() async {
      store.dispose();
      if (await home.exists()) await home.delete(recursive: true);
    });

    test('import persists cover and reading offset across restart', () async {
      final book = await store.importFile(source.path);
      final cover = store.coverFile(book.id);
      expect(cover, isNotNull);
      expect(await cover!.readAsBytes(), orderedEquals(_png));
      expect(p.basename(cover.path), '${book.id}.png');
      await store.savePosition(book.id, 8);
      store.dispose();
      store = LibraryStore(homeDirectory: home);
      await store.initialize();
      expect(store.coverFile(book.id), isNotNull);
      expect(store.getBook(book.id)!.progressOffset, 8);
    });

    test('explicit recovery restores a missing cover file', () async {
      final book = await store.importFile(source.path);
      await store.coverFile(book.id)!.delete();
      expect(store.coverFile(book.id), isNull);
      await store.fillMissingEpubMetadata(book.id);
      expect(await store.coverFile(book.id)!.readAsBytes(),
          orderedEquals(_png));
    });

    test('deleting one book removes only its derived cover', () async {
      final book = await store.importFile(source.path);
      final cover = store.coverFile(book.id)!;
      final unrelated = File(p.join(home.path, 'unrelated.txt'));
      await unrelated.writeAsString('preserved');
      await store.removeBook(book.id);
      expect(await cover.exists(), isFalse);
      expect(await unrelated.readAsString(), 'preserved');
    });

    test('cover lookup rejects non-digest identifiers', () {
      expect(store.coverFile('../../escape'), isNull);
      expect(store.coverFile(List.filled(64, 'A').join()), isNull);
    });
  });
}
