import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ereader/data/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The injected renderer stands in for native PDFium. The small signature
// fixture is enough to exercise the library without a native PDF engine.
final Uint8List _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mP8/x8AAwMCAO+jX6kAAAAASUVORK5CYII=',
));

void main() {
  late Directory home;
  late File source;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-pdf-cover-');
    source = File(p.join(home.path, 'first.pdf'));
    await source.writeAsString('%PDF-1.4\nsynthetic native-free fixture');
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test('PDF cover is generated once, private, persistent and removable',
      () async {
    var renderCount = 0;
    final store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (path) async {
        renderCount++;
        expect(path, contains('books'));
        return _png;
      },
    );
    await store.initialize();
    final book = await store.importFile(source.path);
    expect(store.coverFile(book.id), isNull);
    final first = await store.ensurePdfCover(book.id);
    expect(first, isNotNull);
    expect(await first!.readAsBytes(), orderedEquals(_png));
    expect(p.basename(first.path), '${book.id}.png');
    expect((await store.ensurePdfCover(book.id))?.path, first.path);
    expect(renderCount, 1);
    store.dispose();

    final reopened = LibraryStore(homeDirectory: home);
    await reopened.initialize();
    expect(reopened.coverFile(book.id), isNotNull);
    await reopened.removeBook(book.id);
    expect(await first.exists(), isFalse);
    reopened.dispose();
  });

  test('parallel thumbnail requests share one native render', () async {
    final rendering = Completer<Uint8List?>();
    var renderCount = 0;
    final store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) {
        renderCount++;
        return rendering.future;
      },
    );
    await store.initialize();
    final book = await store.importFile(source.path);
    final a = store.ensurePdfCover(book.id);
    final b = store.ensurePdfCover(book.id);
    expect(identical(a, b), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(renderCount, 1);
    rendering.complete(_png);
    expect(await a, isNotNull);
    expect(await b, isNotNull);
    store.dispose();
  });

  test('bad renderer output and invalid id never create images', () async {
    var attempts = 0;
    final store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) async {
        attempts++;
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    await store.initialize();
    final book = await store.importFile(source.path);
    expect(await store.ensurePdfCover('../unsafe'), isNull);
    expect(await store.ensurePdfCover(book.id), isNull);
    expect(await store.ensurePdfCover(book.id), isNull);
    expect(attempts, 1);
    expect(store.coverFile(book.id), isNull);
    store.dispose();
  });

  test('removing a book while render is pending leaves no orphan', () async {
    final rendering = Completer<Uint8List?>();
    final store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) => rendering.future,
    );
    await store.initialize();
    final book = await store.importFile(source.path);
    final pending = store.ensurePdfCover(book.id);
    await Future<void>.delayed(Duration.zero);
    await store.removeBook(book.id);
    rendering.complete(_png);
    expect(await pending, isNull);
    expect(store.coverFile(book.id), isNull);
    expect(await File(p.join(home.path, 'covers', '${book.id}.png'))
        .exists(), isFalse);
    store.dispose();
  });

  test('disposing the database during a render cannot leak an error',
      () async {
    final rendering = Completer<Uint8List?>();
    final store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) => rendering.future,
    );
    await store.initialize();
    final book = await store.importFile(source.path);
    final pending = store.ensurePdfCover(book.id);
    await Future<void>.delayed(Duration.zero);
    store.dispose();
    rendering.complete(_png);
    expect(await pending, isNull);
    expect(await File(p.join(home.path, 'covers', '${book.id}.png'))
        .exists(), isFalse);
  });

  test('PDF rendering error is non-fatal and memoized for this session',
      () async {
    var attempts = 0;
    final store = LibraryStore(
      homeDirectory: home,
      pdfCoverRenderer: (_) async {
        attempts++;
        throw const FormatException('Password required');
      },
    );
    await store.initialize();
    final book = await store.importFile(source.path);
    expect(await store.ensurePdfCover(book.id), isNull);
    expect(await store.ensurePdfCover(book.id), isNull);
    expect(attempts, 1);
    expect(store.getBook(book.id), isNotNull);
    store.dispose();
  });
}
