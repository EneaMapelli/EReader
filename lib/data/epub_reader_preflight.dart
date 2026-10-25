import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../domain/dialogue_segmenter.dart';
import 'book_decoder.dart';
import 'epub_text_extractor.dart';
import 'epub_bounded_file.dart';
import '../features/reader/epub_chapter_navigation.dart';
import '../features/reader/epub_visual_layout.dart';

/// Fixed-size, numeric timing data: never records book text, filenames,
/// URLs, cloud account details or voice identities.
class EpubPreflightTimings {
  const EpubPreflightTimings({
    required this.archiveReadUs,
    required this.xhtmlExtractionUs,
    required this.speechSegmentationUs,
    required this.quoteGroupingUs,
    required this.paragraphBoundariesUs,
    required this.workerTotalUs,
    required this.compressedBytes,
    required this.sourceCodeUnits,
    required this.spineItems,
    required this.speechSegments,
  });

  final int archiveReadUs;
  final int xhtmlExtractionUs;
  final int speechSegmentationUs;
  final int quoteGroupingUs;
  final int paragraphBoundariesUs;
  final int workerTotalUs;
  final int compressedBytes;
  final int sourceCodeUnits;
  final int spineItems;
  final int speechSegments;

  Map<String, int> toJson() => {
    'archiveReadUs': archiveReadUs,
    'xhtmlExtractionUs': xhtmlExtractionUs,
    'speechSegmentationUs': speechSegmentationUs,
    'quoteGroupingUs': quoteGroupingUs,
    'paragraphBoundariesUs': paragraphBoundariesUs,
    'workerTotalUs': workerTotalUs,
    'compressedBytes': compressedBytes,
    'sourceCodeUnits': sourceCodeUnits,
    'spineItems': spineItems,
    'speechSegments': speechSegments,
  };
}

/// Immutable source-only metadata prepared off the Flutter UI isolate.
class EpubReaderPreflight {
  const EpubReaderPreflight({
    required this.document,
    required this.quoted,
    required this.hardBoundaries,
    required this.timings,
  });

  final DocumentContent document;
  final List<QuotedSpeechChunk> quoted;
  final List<int> hardBoundaries;
  final EpubPreflightTimings timings;
}

class EpubPreflightCancelled implements Exception {
  const EpubPreflightCancelled();
  @override
  String toString() => 'EPUB preparation cancelled';
}

/// A cancellable one-shot worker. Calling cancel() kills the isolate, rather
/// than allowing EPUB decompression and parsing to consume CPU after closing
/// the reader. No shared database, cloud operations or native TTS state is
/// ever passed to the worker.
class CancellableEpubPreflight {
  CancellableEpubPreflight._(String localPath) {
    _messages = ReceivePort();
    _listener = _messages.listen(_handleMessage);
    unawaited(_spawn(localPath));
  }

  late final ReceivePort _messages;
  late final StreamSubscription<dynamic> _listener;
  final Completer<EpubReaderPreflight> _completion =
      Completer<EpubReaderPreflight>();
  Isolate? _isolate;
  bool _finished = false;

  Future<EpubReaderPreflight> get result => _completion.future;
  bool get isFinished => _finished;

  Future<void> _spawn(String localPath) async {
    try {
      final isolate = await Isolate.spawn<(SendPort, String)>(
        _workerMain,
        (_messages.sendPort, localPath),
        onExit: _messages.sendPort,
        debugName: 'EReader EPUB reader preparation',
      );
      if (_finished) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _handleMessage(dynamic message) {
    if (_finished) return;
    if (message == null) {
      _fail(StateError('EPUB preparation worker exited without a result'));
      return;
    }
    if (message is! List || message.length != 2 || message[0] is! int) {
      _fail(const FormatException('Invalid EPUB worker response'));
      return;
    }
    if (message[0] == 0 && message[1] is EpubReaderPreflight) {
      _finished = true;
      _close();
      _completion.complete(message[1] as EpubReaderPreflight);
      return;
    }
    if (message[0] == 1 && message[1] == 'format') {
      _fail(const FormatException('EPUB format or safety limit failed'));
    } else if (message[0] == 1 && message[1] == 'file') {
      _fail(const FileSystemException('EPUB local file cannot be read'));
    } else {
      _fail(StateError('EPUB background preparation failed'));
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_finished) return;
    _finished = true;
    _isolate?.kill(priority: Isolate.immediate);
    _close();
    _completion.completeError(error, stack ?? StackTrace.current);
  }

  void _close() {
    unawaited(_listener.cancel());
    _messages.close();
    _isolate = null;
  }

  void cancel() => _fail(const EpubPreflightCancelled());
}

/// Returns immediately, allowing callers to retain a cancellation handle
/// even while spawning the isolate is still in progress.
CancellableEpubPreflight startEpubReaderPreflight(String localPath) =>
    CancellableEpubPreflight._(localPath);

/// Existing one-shot API remains backward compatible with old callers.
Future<EpubReaderPreflight> prepareEpubReader(String localPath) =>
    startEpubReaderPreflight(localPath).result;

/// Worker receives only its send port and local path. It never opens SQLite,
/// talks to network providers, accesses Flutter plugins or starts narration.
/// The result and fixed error codes are ordinary isolate-sendable objects.
void _workerMain((SendPort, String) message) {
  try {
    final result = _prepareEpubFile(message.$2);
    message.$1.send([0, result]);
  } on FormatException {
    message.$1.send([1, 'format']);
  } on FileSystemException {
    message.$1.send([1, 'file']);
  } catch (_) {
    message.$1.send([1, 'other']);
  }
}

EpubReaderPreflight _prepareEpubFile(String localPath) {
  final stopwatch = Stopwatch()..start();
  int measureStart = 0;
  final bytes = readBoundedEpubFile(localPath);
  final archiveReadUs = stopwatch.elapsedMicroseconds - measureStart;

  measureStart = stopwatch.elapsedMicroseconds;
  final extracted = const EpubTextExtractor().extract(bytes);
  final document = documentFromExtractedEpub(extracted);
  final extractionUs = stopwatch.elapsedMicroseconds - measureStart;

  measureStart = stopwatch.elapsedMicroseconds;
  final base = segmentEpubSpine(document);
  final segmentationUs = stopwatch.elapsedMicroseconds - measureStart;

  measureStart = stopwatch.elapsedMicroseconds;
  final quoted = splitQuotedSegmentsWithRegions(base);
  final quoteUs = stopwatch.elapsedMicroseconds - measureStart;

  measureStart = stopwatch.elapsedMicroseconds;
  final boundaries = epubParagraphHardBoundaries(document);
  final boundariesUs = stopwatch.elapsedMicroseconds - measureStart;

  return EpubReaderPreflight(
    document: document,
    quoted: quoted,
    hardBoundaries: boundaries,
    timings: EpubPreflightTimings(
      archiveReadUs: archiveReadUs,
      xhtmlExtractionUs: extractionUs,
      speechSegmentationUs: segmentationUs,
      quoteGroupingUs: quoteUs,
      paragraphBoundariesUs: boundariesUs,
      workerTotalUs: stopwatch.elapsedMicroseconds,
      compressedBytes: bytes.length,
      sourceCodeUnits: document.text.length,
      spineItems: document.epubSpineRanges.length,
      speechSegments: base.length,
    ),
  );
}
