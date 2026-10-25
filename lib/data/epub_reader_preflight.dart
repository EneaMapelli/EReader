import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../domain/dialogue_segmenter.dart';
import '../domain/reading_anchor.dart';
import 'epub_progress_recovery.dart';
import 'book_decoder.dart';
import 'epub_text_extractor.dart';
import 'epub_bounded_file.dart';
import '../features/reader/epub_chapter_navigation.dart';
import '../features/reader/epub_visual_layout.dart';

/// Only the persisted source-relative checkpoint is transferred to the EPUB
/// worker. The worker has no database access and never receives credentials.
class EpubResumeRequest {
  const EpubResumeRequest({
    required this.anchor,
    required this.legacyOffset,
  });

  final ReadingAnchor? anchor;
  final int legacyOffset;
}

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
    this.resumeRecoveryUs,
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
  /// Null when no recovery was requested, including standalone preflights.
  final int? resumeRecoveryUs;

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
    if (resumeRecoveryUs != null) 'resumeRecoveryUs': resumeRecoveryUs!,
  };
}

/// Immutable source-only metadata prepared off the Flutter UI isolate.
class EpubReaderPreflight {
  const EpubReaderPreflight({
    required this.document,
    required this.quoted,
    required this.hardBoundaries,
    required this.timings,
    this.resumeRecovery,
  });

  final DocumentContent document;
  final List<QuotedSpeechChunk> quoted;
  final List<int> hardBoundaries;
  final EpubPreflightTimings timings;
  /// Computed on the worker before transferring the document to Flutter.
  final EpubProgressRecovery? resumeRecovery;
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
  CancellableEpubPreflight._(String localPath, EpubResumeRequest? resume) {
    _messages = ReceivePort();
    _listener = _messages.listen(_handleMessage);
    unawaited(_spawn(localPath, resume));
  }

  late final ReceivePort _messages;
  late final StreamSubscription<dynamic> _listener;
  final Completer<EpubReaderPreflight> _completion =
      Completer<EpubReaderPreflight>();
  Isolate? _isolate;
  Timer? _exitGraceTimer;
  bool _finished = false;

  Future<EpubReaderPreflight> get result => _completion.future;
  bool get isFinished => _finished;

  Future<void> _spawn(String localPath, EpubResumeRequest? resume) async {
    try {
      final isolate = await Isolate.spawn<(SendPort, String, EpubResumeRequest?)>(
        _workerMain,
        (_messages.sendPort, localPath, resume),
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
      // An onExit notification may precede the Isolate.exit(finalResponse)
      // payload, particularly while a large EPUB model is transferred under
      // CPU pressure. Do not turn that delivery-order race into a false
      // failure. Keep a single bounded fallback for genuinely dead workers.
      // The timer is cancelled immediately when a valid reply arrives.
      _exitGraceTimer ??= Timer(const Duration(seconds: 3), () {
        if (!_finished) {
          _fail(StateError('EPUB preparation worker exited without a result'));
        }
      });
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
    _exitGraceTimer?.cancel();
    _exitGraceTimer = null;
    unawaited(_listener.cancel());
    _messages.close();
    _isolate = null;
  }

  void cancel() => _fail(const EpubPreflightCancelled());
}

/// Returns immediately, allowing callers to retain a cancellation handle
/// even while spawning the isolate is still in progress.
CancellableEpubPreflight startEpubReaderPreflight(
  String localPath, {EpubResumeRequest? resume}
) => CancellableEpubPreflight._(localPath, resume);

/// Existing one-shot API remains backward compatible with old callers.
Future<EpubReaderPreflight> prepareEpubReader(
  String localPath, {EpubResumeRequest? resume}
) => startEpubReaderPreflight(localPath, resume: resume).result;

/// Worker receives only its send port and local path. It never opens SQLite,
/// talks to network providers, accesses Flutter plugins or starts narration.
/// The result and fixed error codes are ordinary isolate-sendable objects.
void _workerMain((SendPort, String, EpubResumeRequest?) message) {
  Object response;
  try {
    response = [0, _prepareEpubFile(message.$2, resume: message.$3)];
  } on FormatException {
    response = [1, 'format'];
  } on FileSystemException {
    response = [1, 'file'];
  } catch (_) {
    response = [1, 'other'];
  }
  // The isolate is done with the large source model: exit and transfer
  // ownership of the result, avoiding an extra deep copy of the entire EPUB.
  Isolate.exit(message.$1, response);
}

EpubReaderPreflight _prepareEpubFile(String localPath, {EpubResumeRequest? resume}) {
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

  EpubProgressRecovery? resumeRecovery;
  int? resumeRecoveryUs;
  if (resume != null) {
    // A bounded v2 fingerprint relocation can hash thousands of candidate
    // offsets. Perform it here while the canonical source is still owned
    // by this isolate; never copy the whole book into a second worker.
    measureStart = stopwatch.elapsedMicroseconds;
    resumeRecovery = resolveEpubReadingProgress(
      document, anchor: resume.anchor, legacyOffset: resume.legacyOffset,
    );
    resumeRecoveryUs = stopwatch.elapsedMicroseconds - measureStart;
  }

  return EpubReaderPreflight(
    document: document,
    quoted: quoted,
    hardBoundaries: boundaries,
    resumeRecovery: resumeRecovery,
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
      resumeRecoveryUs: resumeRecoveryUs,
    ),
  );
}
