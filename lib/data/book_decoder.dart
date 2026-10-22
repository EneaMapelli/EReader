import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../domain/book.dart';
import 'epub_text_extractor.dart';

class DocumentContent {
  const DocumentContent({
    required this.text,
    required this.title,
    this.pdfPageRanges = const [],
    this.epubSpineRanges = const [],
  });
  final String text;
  final String title;
  final List<PdfPageRange> pdfPageRanges;
  final List<EpubSpineRange> epubSpineRanges;
}

/// Maps extracted text offsets back to an originating PDF page.
class PdfPageRange {
  const PdfPageRange(this.pageNumber, this.start, this.end);
  final int pageNumber;
  final int start;
  final int end;
}

abstract interface class DocumentDecoder {
  Future<DocumentContent> read(BookRecord record);
}

/// An initial extraction POC. EPUB3 spine ordering, images, footnotes,
/// stable CFI anchors, ZIP bomb handling and PDF text layer remain open M0/M1
/// gates. In particular, this is not a full-fidelity EPUB renderer.
class PrototypeDocumentDecoder implements DocumentDecoder {
  @override
  Future<DocumentContent> read(BookRecord record) async {
    final file = File(record.localPath);
    if (!await file.exists()) {
      throw FileSystemException('Book file not found', file.path);
    }
    switch (record.format) {
      case BookFormat.txt:
        final bytes = await file.readAsBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        return DocumentContent(
          title: record.title,
          text: text.startsWith('\uFEFF') ? text.substring(1) : text,
        );
      case BookFormat.epub:
        final bytes = await file.readAsBytes();
        final content = const EpubTextExtractor().extract(
          Uint8List.fromList(bytes),
        );
        return DocumentContent(
          title: content.title,
          text: content.text,
          epubSpineRanges: content.ranges,
        );
      case BookFormat.pdf:
        return _readPdfText(record);
    }
  }

  /// POC: extracts a text-layer PDF in file/page order. Multi-column reading
  /// order and physical page highlighting still require dedicated tests.
  Future<DocumentContent> _readPdfText(BookRecord record) async {
    final document = await PdfDocument.openFile(record.localPath);
    try {
      if (document.pages.length > 3000) {
        throw const FormatException('PDF has too many pages for text preview');
      }
      final buffer = StringBuffer();
      final ranges = <PdfPageRange>[];
      for (final page in document.pages) {
        final raw = await page.loadText();
        final content = raw?.fullText.trim() ?? '';
        if (content.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.write('\n\n');
        final start = buffer.length;
        buffer.write(content);
        ranges.add(PdfPageRange(page.pageNumber, start, buffer.length));
        if (buffer.length > 25000000) {
          throw const FormatException('PDF text too large for preview');
        }
      }
      if (ranges.isEmpty) {
        throw const FormatException(
          'No selectable text in this PDF. Scanned pages require OCR.',
        );
      }
      return DocumentContent(
        title: record.title,
        text: buffer.toString(),
        pdfPageRanges: ranges,
      );
    } finally {
      await document.dispose();
    }
  }

}
