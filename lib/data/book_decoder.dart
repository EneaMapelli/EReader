import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../domain/book.dart';
import '../domain/reading_anchor.dart';
import 'epub_text_extractor.dart';
import 'epub_inline_style.dart';
import 'epub_embedded_content.dart';
import 'epub_navigation.dart';

class DocumentContent {
  const DocumentContent({
    required this.text,
    required this.title,
    this.pdfPageRanges = const [],
    this.epubSpineRanges = const [],
    this.epubInlineStyles = const [],
    this.epubImages = const [],
    this.epubLinks = const [],
    this.epubTables = const [],
    this.epubNavigation = const [],
    this.epubFootnotePreviews = const [],
  });
  final String text;
  final String title;
  final List<PdfPageRange> pdfPageRanges;
  final List<EpubSpineRange> epubSpineRanges;
  /// Pure visual EPUB annotations, measured against [text] and never stored
  /// as reading progress, voice text or user-attributed dialogue.
  final List<EpubInlineStyleSpan> epubInlineStyles;
  /// Non-executable visual resources; none affect the persisted anchor or TTS.
  final List<EpubEmbeddedImage> epubImages;
  final List<EpubInternalLink> epubLinks;
  final List<EpubTablePreview> epubTables;
  final List<EpubNavigationEntry> epubNavigation;
  final List<EpubFootnotePreview> epubFootnotePreviews;

  /// Converts the global reader offset to a document-relative source address.
  /// No anchoring to an EPUB TOC entry or PDF visual coordinate is implied.
  ReadingAnchor anchorAt(BookFormat format, int offset) {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (format == BookFormat.txt) {
      return ReadingAnchor(kind: AnchorKind.text, sourceId: 'body',
          localOffset: offset.clamp(0, text.length).toInt());
    }
    if (format == BookFormat.epub && epubSpineRanges.isNotEmpty) {
      for (final entry in epubSpineRanges) {
        if (offset < entry.end) {
          final inside = (offset - entry.start)
              .clamp(0, entry.end - entry.start).toInt();
          return ReadingAnchor(kind: AnchorKind.epubSpine,
              sourceId: entry.idref, localOffset: inside);
        }
      }
      final last = epubSpineRanges.last;
      return ReadingAnchor(kind: AnchorKind.epubSpine,
          sourceId: last.idref, localOffset: last.end - last.start);
    }
    if (format == BookFormat.pdf && pdfPageRanges.isNotEmpty) {
      for (final entry in pdfPageRanges) {
        if (offset < entry.end) {
          return ReadingAnchor(kind: AnchorKind.pdfPage,
              sourceId: entry.pageNumber.toString(),
              localOffset: (offset - entry.start)
                  .clamp(0, entry.end - entry.start).toInt());
        }
      }
      final last = pdfPageRanges.last;
      return ReadingAnchor(kind: AnchorKind.pdfPage,
          sourceId: last.pageNumber.toString(),
          localOffset: last.end - last.start);
    }
    throw StateError('No source ranges available for this format');
  }

  /// Returns null for incompatible/stale anchors, so the caller can fall back
  /// to the saved absolute offset from older database versions.
  int? offsetOf(ReadingAnchor anchor) {
    if (anchor.kind == AnchorKind.text) {
      if (anchor.sourceId != 'body') return null;
      return anchor.localOffset.clamp(0, text.length).toInt();
    }
    if (anchor.kind == AnchorKind.epubSpine) {
      for (final entry in epubSpineRanges) {
        if (entry.idref == anchor.sourceId) {
          return entry.start +
              anchor.localOffset.clamp(0, entry.end - entry.start).toInt();
        }
      }
    }
    if (anchor.kind == AnchorKind.pdfPage) {
      for (final entry in pdfPageRanges) {
        if (entry.pageNumber.toString() == anchor.sourceId) {
          return entry.start +
              anchor.localOffset.clamp(0, entry.end - entry.start).toInt();
        }
      }
    }
    return null;
  }
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
          epubInlineStyles: content.styles,
          epubImages: content.images,
          epubLinks: content.links,
          epubTables: content.tables,
          epubNavigation: content.navigation,
          epubFootnotePreviews: content.footnotePreviews,
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
