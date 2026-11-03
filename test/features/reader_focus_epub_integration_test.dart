import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Two navigable, source-distinct OPF sections with real publisher TOC
/// entries. No external files or platform TTS voices are required.
Uint8List _fixture() {
  final longOpening = List<String>.filled(
      24, 'Opening narrative paragraph for reading position. ').join();
  final longSecond = List<String>.filled(
      24, 'Second narrative paragraph for reading position. ').join();
  final archive = Archive()
    ..add(ArchiveFile.noCompress('mimetype',
        'application/epub+zip'.length, utf8.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
        '</rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/book.opf', '''
<package xmlns="http://www.idpf.org/2007/opf"
    xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0"
    unique-identifier="uid">
  <metadata>
    <dc:identifier id="uid">focus-header-fixture</dc:identifier>
    <dc:title>Focus Header Test</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="first" href="first.xhtml"
        media-type="application/xhtml+xml"/>
    <item id="second" href="second.xhtml"
        media-type="application/xhtml+xml"/>
    <item id="toc" href="nav.xhtml" properties="nav"
        media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="first"/><itemref idref="second"/></spine>
</package>
'''))
    ..add(ArchiveFile.string('OPS/first.xhtml',
        '<html><body><h1 id="opening">Opening</h1><p>$longOpening</p>'
        '</body></html>'))
    ..add(ArchiveFile.string('OPS/second.xhtml',
        '<html><body><h1 id="second">Second chapter</h1>'
        '<p>$longSecond</p></body></html>'))
    ..add(ArchiveFile.string('OPS/nav.xhtml',
        '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol>'
        '<li><a href="first.xhtml#opening">Opening</a></li>'
        '<li><a href="second.xhtml#second">Second chapter</a></li>'
        '</ol></nav></body></html>'));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late Directory home;
  late LibraryStore store;
  late String bookId;
  late int nextChapterStart;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-focus-epub-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    final bytes = _fixture();
    final extracted = const EpubTextExtractor().extract(bytes);
    expect(extracted.navigation.map((entry) => entry.label),
        ['Opening', 'Second chapter']);
    nextChapterStart = extracted.navigation[1].offset;
    final source = File(p.join(home.path, 'focus-reader.epub'));
    await source.writeAsBytes(bytes);
    bookId = (await store.importFile(source.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  testWidgets('immersive EPUB header provides independent visual navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(book: store.getBook(bookId)!, store: store),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 650));
    final revision = store.manualPositionRevision(bookId);
    final offset = store.getBook(bookId)!.progressOffset;

    await tester.tap(find.byKey(const ValueKey('reader-tools-menu')));
    await tester.pumpAndSettle();
    final focus = find.byKey(const ValueKey('organized-action-reading-focus'));
    await tester.scrollUntilVisible(
        focus, 160, scrollable: find.byType(Scrollable).last);
    await tester.tap(focus);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing);
    expect(find.byKey(const ValueKey('reader-focus-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-section')), findsOneWidget);
    expect(find.text('Opening'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-focus-section-go')), findsOneWidget);
    expect(store.manualPositionRevision(bookId), revision,
        reason: 'Entering focus is presentation-only');

    await tester.tap(find.byKey(const ValueKey('reader-focus-section')));
    await tester.pumpAndSettle();
    expect(find.text('Book table of contents'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-directory-entry-0')), findsOneWidget);
    await tester.tapAt(const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revision,
        reason: 'Opening and dismissing chapter directory does not seek');

    await tester.tap(find.byKey(const ValueKey('reader-focus-section-go')));
    await tester.pumpAndSettle();
    expect(find.text('Go to section position'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revision);
    expect(store.getBook(bookId)!.progressOffset, offset);

    await tester.tap(find.byKey(const ValueKey('reader-focus-progress')));
    await tester.pumpAndSettle();
    expect(find.text('Go to book position'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.manualPositionRevision(bookId), revision,
        reason: 'Global and section Go dialogs never persist on cancellation');

    await tester.tap(find.byKey(const ValueKey('reader-focus-section-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-progress-preset-75')));
    await tester.tap(find.byKey(const ValueKey('reader-progress-confirm')));
    await tester.pumpAndSettle();
    final persisted = store.getBook(bookId)!.progressOffset;
    expect(persisted, greaterThan(offset));
    expect(persisted, lessThan(nextChapterStart),
        reason: 'Local 75% may not cross into the next EPUB chapter');
    expect(find.byKey(const ValueKey('reader-compact-transport')), findsNothing,
        reason: 'Seeking inside a chapter does not exit immersive mode');
    expect(find.byKey(const ValueKey('reader-focus-section')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
