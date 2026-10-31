import 'dart:io';
import 'dart:isolate';

import 'package:pdfrx/pdfrx.dart';

import '../domain/book.dart';
import '../domain/reading_anchor.dart';
import '../domain/epub_anchor_context.dart';
import 'epub_text_extractor.dart';
import 'plain_text_decoder.dart';
import 'epub_bounded_file.dart';
import 'epub_inline_style.dart';
import 'epub_embedded_content.dart';
import 'epub_navigation.dart';
import 'epub_import_diagnostics.dart';
import 'epub_speech_note_filter.dart';

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
    this.epubFigureCaptions = const [],
    this.epubNavigation = const [],
    this.epubFootnotePreviews = const [],
    this.epubSpokenNoteRanges = const [],
    this.epubAuxiliaryFootnotePreviews = const [],
    this.epubDiagnostics = const [],
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
  final List<EpubFigureCaption> epubFigureCaptions;
  final List<EpubNavigationEntry> epubNavigation;
  final List<EpubFootnotePreview> epubFootnotePreviews;
  /// Source-verified, in-spine EPUB notes; not excluded from visual reading.
  final List<EpubSpokenNoteRange> epubSpokenNoteRanges;
  /// Local-only auxiliary note text, with *no* position in the TTS spine.
  final List<EpubAuxiliaryFootnotePreview> epubAuxiliaryFootnotePreviews;
  final List<EpubImportDiagnostic> epubDiagnostics;

  // Weakly held per-document index: lookup caches disappear with the
  // decoded document, avoiding an unbounded global index across a library.
  // EPUB extracted spine IDs are structurally unique; preserve the first
  // match for older synthetic/caller-provided documents as well.
  static final Expando<Map<String, EpubSpineRange>> _spineById =
      Expando<Map<String, EpubSpineRange>>('ereader_epub_spine');

  EpubSpineRange? _sourceRangeForId(String id) {
    var index = _spineById[this];
    if (index == null) {
      index = <String, EpubSpineRange>{};
      for (final range in epubSpineRanges) {
        index.putIfAbsent(range.idref, () => range);
      }
      _spineById[this] = index;
    }
    return index[id];
  }

  /// Converts the global reader offset to a document-relative source address.
  /// No anchoring to an EPUB TOC entry or PDF visual coordinate is implied.
  ReadingAnchor anchorAt(BookFormat format, int offset) {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (format == BookFormat.txt) {
      return ReadingAnchor(kind: AnchorKind.text, sourceId: 'body',
          localOffset: offset.clamp(0, text.length).toInt());
    }
    if (format == BookFormat.epub && epubSpineRanges.isNotEmpty) {
      // OPF spine ranges are sorted by original UTF-16 source position.
      // Use the first chapter whose *end* exceeds the offset: this
      // deliberately assigns synthetic separator positions to the NEXT
      // readable chapter, preserving the earlier linear-scan behavior.
      var low = 0;
      var high = epubSpineRanges.length;
      while (low < high) {
        final mid = low + (high - low) ~/ 2;
        if (epubSpineRanges[mid].end <= offset) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      final entry = low < epubSpineRanges.length
          ? epubSpineRanges[low] : epubSpineRanges.last;
      final inside = (offset - entry.start)
          .clamp(0, entry.end - entry.start).toInt();
      final absolute = entry.start + inside;
      final fingerprint = EpubAnchorContext.capture(
          text, entry.start, entry.end, absolute);
      return ReadingAnchor(kind: AnchorKind.epubSpine,
          sourceId: entry.idref, localOffset: inside,
          contextBefore: fingerprint.before,
          contextAfter: fingerprint.after);
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
      final entry = _sourceRangeForId(anchor.sourceId);
      if (entry == null) return null;
      final length = entry.end - entry.start;
      // A stale local offset must never be silently mapped to another
      // character or to the next chapter's separator.
      if (anchor.localOffset > length) return null;
      final absolute = entry.start + anchor.localOffset;
      if (absolute > 0 && absolute < text.length) {
        final left = text.codeUnitAt(absolute - 1);
        final right = text.codeUnitAt(absolute);
        if (left >= 0xd800 && left <= 0xdbff &&
            right >= 0xdc00 && right <= 0xdfff) {
          return null;
        }
      }
      if (anchor.hasContext &&
          !EpubAnchorContext.matches(
              text, entry.start, entry.end, absolute, anchor)) {
        // A valid integer offset can still point to the wrong sentence
        // after newly recognized <br> tags or other parser changes.
        return null;
      }
      return absolute;
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

/// The exact metadata adapter for foreground consumer reads and the reader
/// preparation worker. Keeping one implementation prevents note, TOC, style
/// or diagnostic fields from silently disappearing in background parsing.
DocumentContent documentFromExtractedEpub(EpubTextResult content) =>
    DocumentContent(
      title: content.title,
      text: content.text,
      epubSpineRanges: content.ranges,
      epubInlineStyles: content.styles,
      epubImages: content.images,
      epubLinks: content.links,
      epubTables: content.tables,
      epubFigureCaptions: content.figureCaptions,
      epubNavigation: content.navigation,
      epubFootnotePreviews: content.footnotePreviews,
      epubSpokenNoteRanges: content.spokenNoteRanges,
      epubAuxiliaryFootnotePreviews: content.auxiliaryFootnotePreviews,
      epubDiagnostics: content.diagnostics,
    );

/// Worker-side only: no Flutter widgets/plugins, SQLite connection, network,
/// TTS engine or user-specific credentials cross the isolate boundary.
EpubTextResult _extractEpubFile(String localPath) {
  final bytes = readBoundedEpubFile(localPath);
  return const EpubTextExtractor().extract(bytes);
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
        // Decode in a worker instead of allocating a potentially large
        // TXT buffer on the UI isolate. Reader and FTS indexer share this
        // exact canonical text/UTF-16 offset representation.
        final text = await Isolate.run(
          () => decodePlainTextFile(record.localPath),
          debugName: 'EReader TXT decode',
        );
        return DocumentContent(title: record.title, text: text);
      case BookFormat.epub:
        // EPUB ZIP decompression, XHTML parsing and source annotation are
        // CPU-heavy. Keep them off the Flutter UI isolate. The worker reads
        // the file itself, avoiding a second compressed archive copy on
        // the UI thread; its result is a sendable, pure-Dart data object.
        final content = await Isolate.run(
          () => _extractEpubFile(record.localPath),
          debugName: 'EReader EPUB import',
        );
        return documentFromExtractedEpub(content);
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
