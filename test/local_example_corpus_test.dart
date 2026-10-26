import 'dart:convert';
import 'dart:io';

import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_reader_preflight.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Local-only real-book suite. Enabled exclusively by the dedicated runner.
/// Normal flutter test/CI runs skip it and never disclose private filenames.
const bool _enabled =
    bool.fromEnvironment('EREADER_EXAMPLE_CORPUS', defaultValue: false);
const bool _deep =
    bool.fromEnvironment('EREADER_EXAMPLE_DEEP', defaultValue: false);

void main() {
  final folder = Directory(p.join(Directory.current.path, 'example'));
  if (!_enabled) {
    test('example corpus is local-only and opt-in', () {},
        skip: 'Run tool/run-example-corpus.ps1 locally');
    return;
  }
  // Required when the native PDF backend uses Flutter's test services.
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!folder.existsSync()) {
    test('example corpus directory exists', () =>
        fail('Create example/ in the repo root and add EPUB/PDF files.'));
    return;
  }

  final List<FileSystemEntity> entries;
  try {
    entries = folder.listSync(recursive: true, followLinks: false);
  } on FileSystemException {
    test('example corpus directory is readable',
        () => fail('Cannot enumerate the local example directory.'));
    return;
  }
  if (entries.any((entity) => entity is Link)) {
    test('example corpus refuses symlinks', () =>
        fail('Do not put symlinks or junctions in example/.'));
    return;
  }
  final files = entries.whereType<File>().where((file) {
    final ext = p.extension(file.path).toLowerCase();
    return ext == '.epub' || ext == '.pdf';
  }).toList();
  files.sort((a, b) {
    final x = p.relative(a.path, from: folder.path);
    final y = p.relative(b.path, from: folder.path);
    final folded = x.toLowerCase().compareTo(y.toLowerCase());
    return folded == 0 ? x.compareTo(y) : folded;
  });
  if (files.isEmpty || files.length > 100) {
    test('example corpus has 1 to 100 EPUB/PDF files', () =>
        fail('Provide 1–100 EPUB/PDF files; split larger sets into batches.'));
    return;
  }

  final outcomes = <Map<String, Object?>>[];
  tearDownAll(() async {
    // This file may contain book filenames: .local-test-results/ is ignored.
    final report = File(p.join(Directory.current.path,
        '.local-test-results', 'example-corpus', 'latest.json'));
    await report.parent.create(recursive: true);
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'kind': 'local-book-corpus',
        'deepEpubPreflight': _deep,
        'totalFiles': files.length,
        'entries': outcomes,
      }),
      flush: true,
    );
  });

  for (var i = 0; i < files.length; i++) {
    final source = files[i];
    final relative = p.relative(source.path, from: folder.path);
    final format = p.extension(source.path).toLowerCase() == '.epub'
        ? BookFormat.epub : BookFormat.pdf;

    test('[${i + 1}/${files.length}] ${format.name.toUpperCase()}: $relative',
        () async {
      final clock = Stopwatch()..start();
      final result = <String, Object?>{
        'file': relative, 'format': format.name,
        'outcome': 'failed', 'deep': _deep,
      };
      Directory? sandbox;
      LibraryStore? library;
      try {
        final size = await source.length();
        result['sizeBytes'] = size;
        expect(size, inInclusiveRange(1, 100 * 1024 * 1024),
            reason: 'File cannot be imported within EReader size limits');
        sandbox = await Directory.systemTemp.createTemp('ereader-corpus-');
        library = LibraryStore(homeDirectory: sandbox);
        await library.initialize();

        // A copy enters a fresh private library. The original is read-only.
        final first = await library.importFile(source.path,
            originalName: p.basename(source.path));
        expect(first.format, format);
        expect(library.books, hasLength(1));
        final duplicate = await library.importFile(source.path,
            originalName: p.basename(source.path));
        expect(duplicate.id, first.id);
        expect(library.books, hasLength(1));
        // Only boolean discovery statistics; do not echo book title,
        // author, series or language into any shareable summary.
        if (format == BookFormat.epub) {
          result['opfAuthorDetected'] = first.author != null;
          result['opfSeriesDetected'] = first.series != null;
          result['opfLanguageDetected'] = first.language != null;
          result['opfCoverDetected'] = library.coverFile(first.id) != null;
          result['opfTitleDetected'] =
              first.title != p.basenameWithoutExtension(source.path);
        }
        result['importAndDedupMs'] = clock.elapsedMilliseconds;

        if (format == BookFormat.pdf) {
          // This exercises the real native PDF backend, even for scanned
          // pages whose content is not usable by TTS until OCR exists.
          final pdf = await PdfDocument.openFile(first.localPath);
          try {
            expect(pdf.pages.length, inInclusiveRange(1, 3000));
            result['pages'] = pdf.pages.length;
          } finally {
            await pdf.dispose();
          }
        }

        DocumentContent? document;
        try {
          document = await PrototypeDocumentDecoder().read(first);
        } on FormatException catch (error) {
          if (format != BookFormat.pdf ||
              !error.message.contains('No selectable text')) {
            rethrow;
          }
          result['classification'] = 'scanned-or-no-text-needs-ocr';
        }

        if (document != null) {
          expect(document.text.trim(), isNotEmpty);
          result['textCodeUnits'] = document.text.length;
          result['classification'] = 'text-readable';
          final ranges = format == BookFormat.epub
              ? [
                  for (final r in document.epubSpineRanges)
                    (start: r.start, end: r.end),
                ]
              : [
                  for (final r in document.pdfPageRanges)
                    (start: r.start, end: r.end),
                ];
          expect(ranges, isNotEmpty, reason: 'Missing source ranges');
          result['sourceRanges'] = ranges.length;
          var previousEnd = -1;
          for (final range in ranges) {
            expect(range.start, greaterThanOrEqualTo(previousEnd));
            expect(range.end, greaterThanOrEqualTo(range.start));
            expect(range.end, lessThanOrEqualTo(document.text.length));
            previousEnd = range.end;
          }
          final nonempty = ranges.where((r) => r.end > r.start).toList();
          expect(nonempty, isNotEmpty, reason: 'No readable source range');
          final sampleIndices = <int>{0, nonempty.length ~/ 2,
              nonempty.length - 1};
          for (final sample in sampleIndices) {
            final range = nonempty[sample];
            final offset =
                range.start + (range.end - range.start) ~/ 2;
            final anchor = document.anchorAt(format, offset);
            expect(document.offsetOf(anchor), offset,
                reason: 'Source anchor round-trip changed the position');
          }
          final middle = nonempty[nonempty.length ~/ 2];
          final target = middle.start + (middle.end - middle.start) ~/ 2;
          await library.savePosition(first.id, target,
              anchor: document.anchorAt(format, target));

          if (format == BookFormat.epub) {
            result['spines'] = document.epubSpineRanges.length;
            result['tocEntries'] = document.epubNavigation.length;
            result['images'] = document.epubImages.length;
            result['diagnostics'] = document.epubDiagnostics.length;
            if (_deep) {
              final prepared = await prepareEpubReader(first.localPath);
              if (prepared.document.text != document.text) {
                fail('Background EPUB preparation changed the source text');
              }
              expect(prepared.document.epubSpineRanges.length,
                  document.epubSpineRanges.length);
              for (final quoted in prepared.quoted) {
                final segment = quoted.segment;
                expect(segment.start, greaterThanOrEqualTo(0));
                expect(segment.end, lessThanOrEqualTo(document.text.length));
                if (document.text.substring(segment.start, segment.end) !=
                    segment.text) {
                  fail('Narration segment text diverges from EPUB source');
                }
              }
              result['speechSegments'] = prepared.timings.speechSegments;
              result['epubPreflightMs'] =
                  prepared.timings.workerTotalUs ~/ 1000;
            }
          }
        } else {
          // PDFs without a text layer still support visual resume.
          expect(format, BookFormat.pdf);
          library.savePdfVisualPage(first.id, 1);
        }
        library.dispose();
        library = LibraryStore(homeDirectory: sandbox);
        await library.initialize();
        final reopened = library.getBook(first.id)!;
        expect(reopened.id, first.id);
        expect(library.books, hasLength(1));
        if (document == null) {
          expect(library.getPdfVisualPage(first.id), 1);
          expect(reopened.progressAnchor, isNull);
        } else {
          expect(reopened.progressAnchor, isNotNull);
          expect(document.offsetOf(reopened.progressAnchor!),
              reopened.progressOffset);
        }
        result['outcome'] = 'passed';
      } catch (error) {
        // Classification only in JSON; no source excerpts, private audio,
        // passwords, or API keys ever leave the machine.
        result['failureType'] = error.runtimeType.toString();
        rethrow;
      } finally {
        clock.stop();
        result['elapsedMs'] = clock.elapsedMilliseconds;
        outcomes.add(result);
        library?.dispose();
        if (sandbox != null) {
          // Native PDF/EPUB handles may be released just after the last
          // isolate/result completes on Windows. Retry only lock code 32.
          for (var attempt = 0; attempt < 12; attempt++) {
            if (!await sandbox.exists()) break;
            try {
              await sandbox.delete(recursive: true);
              break;
            } on FileSystemException catch (error) {
              if (!Platform.isWindows ||
                  error.osError?.errorCode != 32 || attempt == 11) {
                result['outcome'] = 'failed';
                result['failureType'] = 'cleanup';
                rethrow;
              }
              await Future<void>.delayed(
                Duration(milliseconds: 25 * (attempt + 1)),
              );
            }
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  }
}
