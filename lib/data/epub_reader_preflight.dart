import 'dart:io';
import 'dart:isolate';

import '../domain/dialogue_segmenter.dart';
import 'book_decoder.dart';
import 'epub_text_extractor.dart';
import '../features/reader/epub_chapter_navigation.dart';
import '../features/reader/epub_visual_layout.dart';

/// Immutable, precomputed *source-only* EPUB reading metadata. The caller
/// still resolves private user cast assignments on the UI isolate before
/// voice synthesis, and no cloud work is ever performed by this worker.
class EpubReaderPreflight {
  const EpubReaderPreflight({
    required this.document,
    required this.quoted,
    required this.hardBoundaries,
  });

  final DocumentContent document;
  final List<QuotedSpeechChunk> quoted;
  final List<int> hardBoundaries;
}

/// ZIP extraction, XHTML projection, initial speech splitting, quote markers
/// and paragraph hard boundaries all run off the Flutter UI isolate.
/// Read the file *inside* the worker: do not transfer a second compressed
/// archive copy to the main isolate.
Future<EpubReaderPreflight> prepareEpubReader(String localPath) =>
    Isolate.run(
      () => _prepareEpubFile(localPath),
      debugName: 'EReader EPUB reader preparation',
    );

EpubReaderPreflight _prepareEpubFile(String localPath) {
  final bytes = File(localPath).readAsBytesSync();
  final extracted = const EpubTextExtractor().extract(bytes);
  final document = documentFromExtractedEpub(extracted);
  final base = segmentEpubSpine(document);
  final quoted = splitQuotedSegmentsWithRegions(base);
  final boundaries = epubParagraphHardBoundaries(document);
  return EpubReaderPreflight(
    document: document,
    quoted: quoted,
    hardBoundaries: boundaries,
  );
}
