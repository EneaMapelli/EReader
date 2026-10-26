import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final Uint8List _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mP8/x8AAwMCAO+jX6kAAAAASUVORK5CYII=',
));

Uint8List _sampleEpub() {
  final zip = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/content.opf"/>'
        '</rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/content.opf', '''
      <package xmlns="http://www.idpf.org/2007/opf"
          xmlns:dc="http://purl.org/dc/elements/1.1/">
        <metadata><dc:title>Illustrated EPUB</dc:title></metadata>
        <manifest>
          <item id="cover" href="front.png" media-type="image/png"
                properties="cover-image"/>
          <item id="chapter" href="body.xhtml"
                media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="chapter"/></spine>
      </package>
    '''))
    ..add(ArchiveFile.string('OPS/body.xhtml',
        '<html><body><p>Simple local illustration test.</p></body></html>'))
    ..add(ArchiveFile('OPS/front.png', _png.length, _png));
  return ZipEncoder().encodeBytes(zip);
}

void main() {
  late Directory home;
  late LibraryStore store;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-cover-ui-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  testWidgets('books with a valid declared cover have a thumbnail',
      (tester) async {
    final source = File(p.join(home.path, 'illustration.epub'));
    await source.writeAsBytes(_sampleEpub());
    final book = await store.importFile(source.path);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    expect(find.byKey(ValueKey('library-cover-${book.id}')),
        findsOneWidget);
    expect(find.text('Illustrated EPUB'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('PDFs display a cached first-page thumbnail after rendering',
      (tester) async {
    store.dispose();
    store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) async => _png,
    );
    await store.initialize();
    final source = File(p.join(home.path, 'illustration.pdf'));
    await source.writeAsString('%PDF-1.4\nPDF thumbnail fixture');
    final book = await store.importFile(source.path);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('library-cover-${book.id}')),
        findsOneWidget);
    expect(store.coverFile(book.id), isNotNull);
  });

  testWidgets('unrenderable PDFs retain the PDF format icon',
      (tester) async {
    store.dispose();
    store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) async => null,
    );
    await store.initialize();
    final source = File(p.join(home.path, 'unrenderable.pdf'));
    await source.writeAsString('%PDF-1.4\nunrenderable fixture');
    final book = await store.importFile(source.path);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('library-cover-${book.id}')),
        findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
  });

  testWidgets('plain books keep their native format icon', (tester) async {
    final text = File(p.join(home.path, 'plain.txt'));
    await text.writeAsString('A readable plain text sample.');
    await store.importFile(text.path);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.menu_book_outlined), findsWidgets);
  });
}
