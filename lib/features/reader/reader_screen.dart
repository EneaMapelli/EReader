import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../audio/reader_player.dart';
import '../../audio/reader_media_handler.dart';
import '../../audio/narration_recovery_binding.dart';
import '../../audio/reader_lifecycle_policy.dart';
import '../../audio/speech_engine.dart';
import '../../audio/speech_engine_factory.dart';
import '../../audio/openai_speech_engine.dart';
import '../../audio/secret_vault.dart';
import 'speech_provider_screen.dart';
import '../../data/book_decoder.dart';
import '../../data/pdf_text_navigation.dart';
import 'pdf_page_navigation.dart';
import 'pdf_speech_navigation.dart';
import '../../data/epub_reader_preflight.dart';
import '../../data/epub_speech_note_filter.dart';
import '../../data/epub_progress_recovery.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/book_search.dart';
import '../../domain/speech_segment.dart';
import '../../domain/dialogue_segmenter.dart';
import '../../domain/pronunciation_rule.dart';
import '../../domain/cast_span.dart';
import 'voice_cast_screen.dart';
import 'pronunciation_screen.dart';
import 'reading_tools.dart';
import 'epub_chapter_navigation.dart';
import 'epub_link_history.dart';
import 'epub_note_preview_sheet.dart';
import '../../data/epub_navigation.dart';
import 'epub_visual_layout.dart';
import 'epub_progressive_layout.dart';
import 'epub_paragraph_tile.dart';
import 'epub_diagnostics_sheet.dart';
import 'epub_opening_performance_sheet.dart';
import 'epub_frame_sampler.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key, required this.book, required this.store, this.mediaHandler,
  });
  final BookRecord book;
  final LibraryStore store;
  final ReaderMediaHandler? mediaHandler;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final SpeechSecretVault _vault = PlatformSpeechSecretVault();
  ReaderPlayer? _player;
  NarrationRecoveryBinding? _recoveryBinding;
  DocumentContent? _document;
  List<EpubChapter> _chapters = const [];
  List<EpubNavigationEntry> _authorToc = const [];
  final EpubLinkHistory _linkHistory = EpubLinkHistory();
  EpubVisualLayout _epubLayout = const EpubVisualLayout([], []);
  Map<int, EpubChapter> _chapterStarts = const {};
  List<PronunciationRule> _pronunciationRules = const [];
  Map<String, String> _castNames = const {};
  String? _error;
  bool _loading = true;
  int _loadEpoch = 0;
  CancellableEpubPreflight? _activeEpubTask;
  EpubPreflightTimings? _epubWorkerTimings;
  int? _epubCastLayoutUs;
  int? _epubVoiceSetupUs;
  int? _epubTotalOpenUs;
  int? _epubFirstFrameUs;
  EpubFrameSampler? _activeFrameSampler;
  EpubFrameProfile? _frameProfile;
  Timer? _frameCaptureTimer;
  double _fontSize = 19;
  EpubReadingPalette _epubPalette = EpubReadingPalette.system;
  bool _pdfTextMode = false;
  bool _autoFollow = true;
  bool _skipEpubNotes = false;
  EpubSpeechNoteFilter? _epubSpeechNoteFilter;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Timer? _saveVisualPositionTimer;
  // Discard a deferred scroll write after any explicit seek, playback
  // change, reload or newer viewport event. Canceling the Timer normally
  // suffices, but the revision is a second guard for queued callbacks.
  int _visualSaveRevision = 0;

  void _cancelPendingVisualSave() {
    _visualSaveRevision++;
    _saveVisualPositionTimer?.cancel();
    _saveVisualPositionTimer = null;
  }

  Timer? _savePdfPageTimer;
  int? _pendingPdfPage;
  late int _displayPdfPage;
  int? _pdfPageCount;
  final PdfViewerController _pdfController = PdfViewerController();
  int? _visiblePositionIndex;
  // Actual EPUB source offset on screen, independent of the TTS cursor.
  // Needed to return to a footnote opened from an unspoken caption or
  // from the middle of a long audio segment.
  int? _currentEpubVisualSourceOffset;
  BookSourceMatch? _selectedSourceSearchHit;
  int? _lastVisibleEpubBlockIndex;
  // An EPUB link/footnote/verified bookmark may target unspoken text
  // inside a paragraph. Keep that exact visual source coordinate until
  // the reader visibly moves elsewhere, instead of instantly rewriting
  // its SQLite anchor to the nearest spoken segment during first layout.
  final EpubVisualSourceCheckpoint _visualCheckpoint =
      EpubVisualSourceCheckpoint();
  int _lastFollowedIndex = -1;
  Object? _lastReportedPlaybackError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _itemPositionsListener.itemPositions.addListener(_onVisiblePositions);
    _displayPdfPage = widget.book.format == BookFormat.pdf
        ? widget.store.getPdfVisualPage(widget.book.id)
        : 1;
    if (widget.book.format != BookFormat.pdf) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load({int? requestedPdfPage}) async {
    // A later reload supersedes all earlier work, including an in-flight
    // worker that would otherwise continue unpacking ZIP/XHTML offscreen.
    final epoch = ++_loadEpoch;
    _cancelPendingVisualSave();
    _activeEpubTask?.cancel();
    _activeEpubTask = null;
    _stopFrameCapture(discard: true);
    _frameProfile = null;
    final stopwatch = Stopwatch()..start();
    ReaderPlayer? provisionalPlayer;
    NarrationRecoveryBinding? provisionalBinding;
    CancellableEpubPreflight? task;
    var adoptedPlayer = false;
    try {
      // On EPUB, the background isolate prepares the immutable source,
      // initial speech chunks, quote group markers and paragraph boundaries
      // together. Only user-specific cast resolution stays in this isolate.
      // Capture the latest persisted position before the worker starts.
      // The source fingerprint lookup is CPU-heavy for long chapters, so
      // run it beside extraction instead of hashing on the Flutter isolate.
      final checkpointAtStart = widget.store.getBook(widget.book.id) ??
          widget.book;
      task = widget.book.format == BookFormat.epub
          ? startEpubReaderPreflight(
              widget.book.localPath,
              resume: EpubResumeRequest(
                anchor: checkpointAtStart.progressAnchor,
                legacyOffset: checkpointAtStart.progressOffset,
              ),
            )
          : null;
      _activeEpubTask = task;
      final preflight = task == null ? null : await task.result;
      if (identical(_activeEpubTask, task)) _activeEpubTask = null;
      final document = preflight?.document ??
          await PrototypeDocumentDecoder().read(widget.book);
      if (!mounted || epoch != _loadEpoch) return;
      final uiPreparationStartUs = stopwatch.elapsedMicroseconds;
      // Resolve both legacy and precise manual speaker tags before coalescing.
      // PDF voices and source-anchored progress may NEVER straddle a
      // physical text-layer page boundary. The EPUB worker already
      // segments per OPF spine; TXT keeps the plain source splitter.
      final quoted = preflight?.quoted ??
          splitQuotedSegmentsWithRegions(
            widget.book.format == BookFormat.pdf
                ? segmentPdfPages(document)
                : segmentSpeech(document.text),
            resetAt: widget.book.format == BookFormat.pdf
                ? pdfSpeechQuoteResetOffsets(document)
                : const [],
          );
      final people = widget.store.listCastCharacters(widget.book.id);
      final assigned = prepareCastSpeech(
        source: document.text,
        base: [for (final part in quoted) part.segment],
        annotations: widget.store.listCastSpans(widget.book.id),
        legacyAssignments: widget.store.listSegmentCast(widget.book.id),
        bookId: widget.book.id,
        knownCharacterIds: {for (final person in people) person.id},
        offsetFromAnchor: document.offsetOf,
      );
      // Narrator handoffs are reduced only within verified EPUB paragraphs.
      // Note boundaries prevent a merged clip from swallowing an otherwise
      // skippable in-spine footnote or its adjacent normal prose.
      final speechBoundaries = widget.book.format == BookFormat.epub
          ? <int>[
              ...?preflight?.hardBoundaries,
              if (preflight == null) ...epubParagraphHardBoundaries(document),
              for (final note in document.epubSpokenNoteRanges)
                ...[note.start, note.end],
            ]
          : widget.book.format == BookFormat.pdf
              ? pdfSpeechQuoteResetOffsets(document)
              : const <int>[];
      final prepared = coalesceQuotedSpeech(
        source: document.text,
        chunks: assigned.segments,
        quotedChunks: quoted,
        speakerByStart: assigned.speakerByStart,
        hardBoundaries: speechBoundaries,
        coalesceNarration: widget.book.format == BookFormat.epub,
      );
      final chunks = prepared.segments;
      final noteFilter = widget.book.format == BookFormat.epub
          ? EpubSpeechNoteFilter(
              document.text, document.epubSpokenNoteRanges)
          : null;
      final chapters = widget.book.format == BookFormat.epub
          ? buildEpubChapters(document, chunks)
          : const <EpubChapter>[];
      final visualLayout = widget.book.format == BookFormat.epub
          ? buildProgressiveEpubVisualLayout(document, chunks, chapters)
          : const EpubVisualLayout([], []);
      final uiPreparationUs =
          stopwatch.elapsedMicroseconds - uiPreparationStartUs;
      final voiceSetupStartUs = stopwatch.elapsedMicroseconds;
      final prefs = widget.store.getSpeechPreferences(bookId: widget.book.id);
      final recoveryBinding = NarrationRecoveryBinding(
        store: widget.store,
        bookId: widget.book.id,
        anchorFor: (segment) =>
            document.anchorAt(widget.book.format, segment.start),
        anchorAtOffset: (offset) =>
            document.anchorAt(widget.book.format, offset),
      );
      provisionalBinding = recoveryBinding;
      final player = ReaderPlayer(
        engineProviderId: prefs.providerId,
        engine: SpeechEngineFactory(vault: _vault).create(
          preferences: prefs,
          bookId: widget.book.id,
          store: widget.store,
        ),
        segments: chunks,
        onSegmentStarted: recoveryBinding.onSegmentStarted,
        onSegmentCompleted: recoveryBinding.onSegmentCompleted,
      );
      provisionalPlayer = player;
      // Source-only, local policy. The default is always to narrate notes,
      // and a toggle affects subsequent speech without rebuilding/casting.
      player.shouldSkipSegment = (segment) =>
          _skipEpubNotes && (noteFilter?.contains(segment) ?? false);
      final latestBook = widget.store.getBook(widget.book.id) ?? widget.book;
      final initialAnchor = checkpointAtStart.progressAnchor;
      final newestAnchor = latestBook.progressAnchor;
      final checkpointUnchanged =
          checkpointAtStart.progressOffset == latestBook.progressOffset &&
          initialAnchor?.kind == newestAnchor?.kind &&
          initialAnchor?.sourceId == newestAnchor?.sourceId &&
          initialAnchor?.localOffset == newestAnchor?.localOffset &&
          initialAnchor?.contextBefore == newestAnchor?.contextBefore &&
          initialAnchor?.contextAfter == newestAnchor?.contextAfter;
      // Another write may have reached SQLite while the worker was active.
      // Never adopt a computed result for an older checkpoint. The rare
      // changed-checkpoint case uses the conservative existing resolver.
      final EpubProgressRecovery? epubRecovery =
          widget.book.format == BookFormat.epub
              ? (checkpointUnchanged
                  ? preflight!.resumeRecovery!
                  : resolveEpubReadingProgress(
                      document,
                      anchor: latestBook.progressAnchor,
                      legacyOffset: latestBook.progressOffset,
                    ))
              : null;
      var saved = epubRecovery?.offset ??
          (latestBook.progressAnchor == null
              ? latestBook.progressOffset
              : document.offsetOf(latestBook.progressAnchor!) ??
                  latestBook.progressOffset);
      if (widget.book.format == BookFormat.pdf &&
          requestedPdfPage != null) {
        // Only an explicit "Read text aloud" action transfers the current
        // physical page into the voice cursor. Merely turning PDF pages
        // never writes or replaces the stored TTS source anchor.
        final pageOffset = pdfTextOffsetForVisualPage(
          document.pdfPageRanges, requestedPdfPage,
        );
        if (pageOffset == null) {
          // Do not fall back to an unrelated old book checkpoint, which
          // would speak text from an earlier physical PDF page.
          throw FormatException(
            'No selectable PDF text on or after page $requestedPdfPage. '
            'Return to PDF pages or select an earlier readable page.',
          );
        }
        saved = pageOffset;
      }
      // A restored checkpoint may be *after* the final utterance.
      // Preserve completed-book state on reopen rather than replaying the
      // final clip, but keep TOC/search/bookmark jumps independently
      // clamped to a real segment (speechSegmentIndexForOffset).
      final savedIndex = speechResumeIndexForOffset(chunks, saved);
      if (savedIndex >= 0) player.currentIndex = savedIndex;
      final pronunciationRules =
          widget.store.listPronunciationRules(bookId: widget.book.id);
      // The active player's rule list must not change until this new
      // session is adopted. The transform reads the committed field to
      // keep subsequent edits to pronunciations immediately effective.
      player.speechTextTransform = (original) =>
          const PronunciationTransformer().apply(
              original, _pronunciationRules, bookId: widget.book.id);
      await player.loadVoices();
      if (!mounted || epoch != _loadEpoch) return;
      await player.applyPreferences(prefs);
      if (!mounted || epoch != _loadEpoch) return;
      final voiceSetupUs = stopwatch.elapsedMicroseconds - voiceSetupStartUs;
      final castNames = _configureVoiceCast(
          player, prepared.speakerByStart);
      var recoveryWriteFailed = false;
      if (epubRecovery?.shouldPersist == true) {
        // Persist only an unambiguous recovered v2 anchor. Failure to
        // write a checkpoint must not prevent the book from opening.
        try {
          await widget.store.savePosition(
            widget.book.id, epubRecovery!.offset,
            anchor: document.anchorAt(BookFormat.epub, epubRecovery.offset),
          );
        } catch (_) {
          recoveryWriteFailed = true;
        }
        if (!mounted || epoch != _loadEpoch) return;
      }
      final previous = _player;
      if (previous != null) {
        widget.mediaHandler?.detach(previous);
        previous.removeListener(_onPlaybackChanged);
        _recoveryBinding?.dispose();
        previous.dispose();
      }
      _visualCheckpoint.hold(widget.book.format == BookFormat.epub
          && chunks.isNotEmpty && saved >= 0 && saved <= document.text.length
          ? saved : null, awaitTarget: true);
      _lastFollowedIndex = widget.book.format == BookFormat.epub
          ? (_visualCheckpoint.offset == null
              ? visualLayout.blockForSegment(player.currentIndex)
              : visualLayout.blockForSourceOffset(_visualCheckpoint.offset!))
          : player.currentIndex;
      // A completed speech cursor equals chunks.length, which is NOT a
      // visual-list index. Show the last text block without allowing its
      // initial viewport notification to rewrite an EOF bookmark.
      _visiblePositionIndex = chunks.isEmpty ? null
          : player.currentIndex.clamp(0, chunks.length - 1).toInt();
      _currentEpubVisualSourceOffset = widget.book.format == BookFormat.epub
          ? saved : null;
      _lastVisibleEpubBlockIndex = widget.book.format == BookFormat.epub
          ? _lastFollowedIndex : null;
      recoveryBinding.attach(player);
      player.addListener(_onPlaybackChanged);
      widget.mediaHandler?.attach(
        player,
        bookId: widget.book.id,
        title: widget.book.title,
        canStart: () async {
          // Check the active adapter on every external Play, not the
          // preferences snapshot captured when the screen was first built.
          if (player.currentPreferences.providerId !=
              OpenAiSpeechEngine.providerId) return true;
          return widget.store.getConsent(
            widget.book.id, OpenAiSpeechEngine.providerId,
          ).allowed;
        },
      );
      setState(() {
        _player = player;
        _recoveryBinding = recoveryBinding;
        _document = document;
        _epubSpeechNoteFilter = noteFilter;
        _chapters = chapters;
        _authorToc = document.epubNavigation;
        _linkHistory.clear();
        _epubLayout = visualLayout;
        _chapterStarts = {
          // Silent chapters share the next section's playable cursor.
          // They must not replace the real heading for that clip.
          for (final chapter in chapters)
            if (chapter.hasSpeech) chapter.segmentIndex: chapter,
        };
        _pronunciationRules = pronunciationRules;
        _castNames = castNames;
        _epubWorkerTimings = preflight?.timings;
        _epubCastLayoutUs = preflight == null ? null : uiPreparationUs;
        _epubVoiceSetupUs = preflight == null ? null : voiceSetupUs;
        _epubTotalOpenUs = preflight == null
            ? null : stopwatch.elapsedMicroseconds;
        _epubFirstFrameUs = null;
        _loading = false;
      });
      adoptedPlayer = true;
      if (preflight != null) {
        // Frame-end time is local wall clock from opening attempt, not
        // a frame-duration/FPS estimate or peak memory measurement.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _loadEpoch) return;
          setState(() => _epubFirstFrameUs = stopwatch.elapsedMicroseconds);
        });
      }
      if (epubRecovery?.needsReview == true || recoveryWriteFailed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _loadEpoch) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(recoveryWriteFailed
                ? 'Recovered EPUB position was found, but saving it failed.'
                : 'Saved EPUB position could not be verified. '
                  'Opened the beginning of its chapter; choose where to resume.')),
          );
        });
      }
    } on EpubPreflightCancelled {
      // Replaced or disposed reader; its old worker was intentionally killed.
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    } finally {
      if (identical(_activeEpubTask, task)) _activeEpubTask = null;
      if (!adoptedPlayer) {
        provisionalBinding?.dispose();
        provisionalPlayer?.dispose();
      }
    }
  }

  Map<String, String> _configureVoiceCast(
      ReaderPlayer player, Map<int, String?> speakerByStart) {
    final people = widget.store.listCastCharacters(widget.book.id);
    final voices = widget.store.listCastVoices(widget.book.id);
    final castNames = {for (final person in people) person.id: person.name};
    // Capture the verified assignments for this player only. A later
    // canceled load cannot overwrite the active player's speaker map.
    String? speakerForSegment(SpeechSegment segment) =>
        speakerByStart[segment.start];
    player.castSpeakerForSegment = speakerForSegment;
    player.castVoiceForSegment = (segment) {
      final speaker = speakerForSegment(segment);
      if (speaker == null) return null;
      for (final castVoice in voices) {
        if (castVoice.characterId != speaker ||
            castVoice.providerId != player.engineProviderId) continue;
        // Reject voices absent from the provider catalog; narrator fallback.
        for (final installed in player.availableVoices) {
          if (installed.name == castVoice.voiceName &&
              installed.locale == castVoice.voiceLocale) return installed;
        }
      }
      return null;
    };
    return castNames;
  }

  Future<void> _openCastEditor() async {
    final player = _player;
    final document = _document;
    if (player == null || document == null || player.segments.isEmpty) return;
    await player.pause();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VoiceCastScreen(
          store: widget.store,
          book: widget.book,
          document: document,
          segments: player.segments,
          providerId: player.currentPreferences.providerId,
          availableVoices: player.availableVoices,
        ),
      ),
    );
    if (!mounted || _player != player) return;
    final index = (_visiblePositionIndex ?? player.currentIndex)
        .clamp(0, player.segments.length - 1).toInt();
    final segment = player.segments[index];
    await widget.store.savePosition(
      widget.book.id, segment.start,
      anchor: document.anchorAt(widget.book.format, segment.start),
    );
    if (!mounted) return;
    // Edits can add speech boundaries, so rebuild the segment list as well.
    setState(() { _loading = true; _error = null; });
    await _load();
  }

  /// A PDF page is a visual bookmark, not an offset within extracted text.
  /// Saving this must never overwrite a scanned PDF's null TTS anchor.
  void _onPdfReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted || widget.book.format != BookFormat.pdf ||
        _pdfTextMode) return;
    final count = document.pages.length;
    if (count < 1 || count > 3000) return;
    if (_pdfPageCount != count) {
      setState(() => _pdfPageCount = count);
    }
  }

  Future<void> _goToPdfPage(int number) async {
    final count = _pdfPageCount;
    if (!mounted || widget.book.format != BookFormat.pdf ||
        _pdfTextMode || count == null || number < 1 || number > count ||
        !_pdfController.isReady) return;
    try {
      await _pdfController.goToPage(
        pageNumber: number, anchor: PdfPageAnchor.top,
      );
      if (!mounted || _pdfTextMode) return;
      _onPdfPageChanged(number);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot navigate to this PDF page.'),
        ));
      }
    }
  }

  void _onPdfPageChanged(int? pageNumber) {
    if (!mounted || widget.book.format != BookFormat.pdf ||
        _pdfTextMode || pageNumber == null ||
        pageNumber < 1 || pageNumber > 100000) return;
    if (_pendingPdfPage == pageNumber) return;
    if (_displayPdfPage != pageNumber) {
      setState(() => _displayPdfPage = pageNumber);
    }
    _pendingPdfPage = pageNumber;
    _savePdfPageTimer?.cancel();
    _savePdfPageTimer = Timer(
      const Duration(milliseconds: 350), _flushPdfPagePosition,
    );
  }

  /// Called before unmount/background so a recent page turn isn't lost.
  void _flushPdfPagePosition() {
    _savePdfPageTimer?.cancel();
    _savePdfPageTimer = null;
    final pageNumber = _pendingPdfPage;
    _pendingPdfPage = null;
    if (pageNumber != null) {
      widget.store.savePdfVisualPage(widget.book.id, pageNumber);
    }
  }

  void _onVisiblePositions() {
    if (!mounted || _loading || _player == null || _document == null ||
        (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
    final player = _player!;
    if (player.isPlaying || player.segments.isEmpty) return;
    final visible = _itemPositionsListener.itemPositions.value
        .where((item) =>
            item.itemTrailingEdge > 0 && item.itemLeadingEdge < 1)
        .map((item) => item.index)
        .toList();
    if (visible.isEmpty) return;
    visible.sort();
    final firstItem = visible.first;
    final previousChapter = _currentChapterIndex;
    final previousDirectory = _currentDirectoryIndex;
    final int index;
    final int sourceOffset;
    if (widget.book.format == BookFormat.epub) {
      if (firstItem >= _epubLayout.blocks.length) return;
      // The initial notification is not manual scroll and must not
      // coarsen an exact bookmark to the nearest spoken segment.
      if (_visualCheckpoint.preserveOnVisibleBlocks(
          visible, _epubLayout)) return;
      final location = _epubLayout.positionForVisibleBlock(
          firstItem, player.segments);
      index = location.segmentIndex;
      sourceOffset = location.sourceOffset;
      if (index < 0) return;
      // One TTS segment can span multiple presentation-only paragraphs.
      // Comparing just its speech index would miss real visual scrolling.
      if (firstItem == _lastVisibleEpubBlockIndex) return;
      _lastVisibleEpubBlockIndex = firstItem;
      _currentEpubVisualSourceOffset = sourceOffset;
    } else {
      index = firstItem.clamp(0, player.segments.length - 1).toInt();
      sourceOffset = player.segments[index].start;
      if (index == _visiblePositionIndex) return;
    }
    _visiblePositionIndex = index;
    if (_currentChapterIndex != previousChapter ||
        _currentDirectoryIndex != previousDirectory) {
      setState(() {});
    }
    _cancelPendingVisualSave();
    final revision = _visualSaveRevision;
    final document = _document;
    _saveVisualPositionTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || player.isPlaying || _player != player ||
          _visualSaveRevision != revision || _document != document ||
          (widget.book.format == BookFormat.epub &&
              _currentEpubVisualSourceOffset != sourceOffset) ||
          (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
      widget.store.savePosition(
        widget.book.id, sourceOffset,
        anchor: document?.anchorAt(widget.book.format, sourceOffset),
      );
    });
  }

  void _onPlaybackChanged() {
    if (!mounted) return;
    final player = _player;
     if (player != null && player.lastError != null &&
        !identical(player.lastError, _lastReportedPlaybackError)) {
      final failure = player.lastError!;
      _lastReportedPlaybackError = failure;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Text-to-speech error: $failure')),
        );
      });
    }
    if (player != null && player.isPlaying && player.segments.isNotEmpty) {
      _cancelPendingVisualSave();
      // Explicit Play changes the active location from a visual-only
      // checkpoint to the spoken segment currently being narrated.
      _visualCheckpoint.clear();
      // Pause/resume must continue from the audio cursor, even when no
      // manual visual scrolling occurred during the previous utterance.
      _visiblePositionIndex = player.currentIndex
          .clamp(0, player.segments.length - 1).toInt();
      if (widget.book.format == BookFormat.epub) {
        _currentEpubVisualSourceOffset =
            player.segments[_visiblePositionIndex!].start;
      }
    }
    // An EPUB exact visual jump may seek the native audio cursor while
    // paused. Never schedule a TTS auto-follow scroll back to its coarse
    // segment after that jump; follow speech only while actually playing.
    if (player != null && player.segments.isNotEmpty && _autoFollow &&
        (widget.book.format != BookFormat.epub || player.isPlaying)) {
      final segmentIndex = player.currentIndex
          .clamp(0, player.segments.length - 1).toInt();
      final target = widget.book.format == BookFormat.epub
          ? _epubLayout.blockForSegment(segmentIndex)
          : segmentIndex;
      if (target != _lastFollowedIndex) {
        _lastFollowedIndex = target;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _player != player || !_autoFollow ||
              !_itemScrollController.isAttached ||
              (widget.book.format == BookFormat.epub &&
                  !player.isPlaying)) {
            return;
          }
          _itemScrollController.jumpTo(index: target, alignment: 0.12);
        });
      }
    }
    setState(() {});
  }

  // Publisher NAV/NCX can contain entries inside a chapter and inside
  // unspoken captions. When paused, use the actual source position
  // rather than a nearby TTS segment that may be in another section.
  int _directorySourceOffset(ReaderPlayer player) {
    final selected = player.isPlaying
        ? player.currentIndex
        : (_visiblePositionIndex ?? player.currentIndex);
    final cursor = selected.clamp(0, player.segments.length - 1).toInt();
    return widget.book.format == BookFormat.epub
        ? epubSourceOffsetForLinkReturn(
            speechOffset: player.segments[cursor].start,
            narrationActive: player.isPlaying,
            visualOffset: _currentEpubVisualSourceOffset,
          )
        : player.segments[cursor].start;
  }

  int get _currentChapterIndex {
    final player = _player;
    if (player == null || player.segments.isEmpty || _chapters.isEmpty) {
      return -1;
    }
    return chapterIndexForOffset(_chapters, _directorySourceOffset(player));
  }

  int get _currentDirectoryIndex {
    if (_authorToc.isEmpty) return _currentChapterIndex;
    final player = _player;
    if (player == null || player.segments.isEmpty) return -1;
    return navigationIndexForOffset(
        _authorToc, _directorySourceOffset(player));
  }

  void _jumpDirectoryIndex(int index) {
    if (_authorToc.isNotEmpty) {
      if (index >= 0 && index < _authorToc.length) {
        _navigateToSourceOffset(_authorToc[index].offset, remember: false);
      }
    } else {
      unawaited(_jumpToChapterIndex(index));
    }
  }

  /// Chapter navigation never starts cloud TTS or auto-resumes interrupted
  /// playback. Persist a stable spine anchor through the existing _select.
  Future<void> _jumpToChapterIndex(int chapterIndex) async {
    final player = _player;
    if (player == null || chapterIndex < 0 ||
        chapterIndex >= _chapters.length) return;
    try {
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player) return;
      final chapter = _chapters[chapterIndex];
      await _select(chapter.segmentIndex,
          visualSourceOffset: chapter.start);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot change chapter: $error')),
      );
    }
  }

  Future<void> _openChapterDirectory() async {
    if (_chapters.isEmpty && _authorToc.isEmpty) return;
    final authorial = _authorToc.isNotEmpty;
    final entries = _authorToc;
    final current = _currentChapterIndex;
    final activeTocIndex = _currentDirectoryIndex;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            children: [
              ListTile(title: Text(authorial
                  ? 'Book table of contents' : 'EPUB spine sections')),
              Expanded(
                child: ScrollablePositionedList.builder(
                  // Keep publisher TOCs with thousands of entries virtual,
                  // but start near the current EPUB chapter rather than
                  // building/scanning earlier chapters to scroll there.
                  initialScrollIndex: authorial
                      ? (activeTocIndex < 0 ? 0 : activeTocIndex)
                      : (current < 0 ? 0 : current),
                  itemCount: authorial ? entries.length : _chapters.length,
                  itemBuilder: (_, index) {
                    if (authorial) {
                      final entry = entries[index];
                      final active = index == activeTocIndex;
                      return Padding(
                        padding: EdgeInsets.only(
                            left: (entry.depth.clamp(0, 12) * 14).toDouble()),
                        child: ListTile(
                          dense: true,
                          leading: Icon(active
                              ? Icons.menu_book : Icons.subdirectory_arrow_right),
                          title: Text(entry.label),
                          selected: active,
                          onTap: () => Navigator.of(sheetContext).pop(index),
                        ),
                      );
                    }
                    final chapter = _chapters[index];
                    return ListTile(
                      leading: index == current
                          ? const Icon(Icons.menu_book)
                          : const Icon(Icons.article_outlined),
                      title: Text(chapter.title),
                      subtitle: Text(chapter.hasSpeech
                          ? 'Section ${index + 1} of ${_chapters.length}'
                          : 'Section ${index + 1} of ${_chapters.length} · '
                            'no spoken text'),
                      selected: index == current,
                      onTap: () => Navigator.of(sheetContext).pop(index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    if (authorial) {
      _navigateToSourceOffset(entries[chosen].offset, remember: false);
    } else {
      await _jumpToChapterIndex(chosen);
    }
  }

  Future<void> _searchInBook() async {
    final player = _player;
    if (player == null || player.segments.isEmpty) return;
    final document = _document;
    if (widget.book.format == BookFormat.epub && document != null) {
      final hit = await showBookSourceSearch(
          context, document.text,
          startOffset: _directorySourceOffset(player));
      if (!mounted || _player != player || _document != document ||
          hit == null) return;
      // A search hit is an immutable original-source UTF-16 span.
      // Highlighting must never rewrite reading anchors or start TTS.
      setState(() => _selectedSourceSearchHit = hit);
      _navigateToSourceOffset(hit.start,
          remember: false, preserveSearchHighlight: true);
      return;
    }
    final result = await showBookSearch(context, player.segments);
    if (!mounted || _player != player || result == null) return;
    await _select(result);
  }

  Future<void> _openBookmarks() async {
    final player = _player;
    final document = _document;
    if (player == null || document == null || player.segments.isEmpty) return;
    final index = player.isPlaying
        ? player.currentIndex.clamp(0, player.segments.length - 1).toInt()
        : (_visiblePositionIndex ?? player.currentIndex)
            .clamp(0, player.segments.length - 1).toInt();
    final segment = player.segments[index];
    // A bookmarked EPUB position is a source location, not an audio
    // segment. Silent captions and mid-segment text must be bookmarkable.
    final sourceOffset = widget.book.format == BookFormat.epub
        ? epubSourceOffsetForLinkReturn(
            speechOffset: segment.start,
            narrationActive: player.isPlaying,
            visualOffset: _currentEpubVisualSourceOffset,
          )
        : segment.start;
    final excerpt = widget.book.format == BookFormat.epub &&
            sourceOffset >= 0 && sourceOffset < document.text.length
        ? document.text.substring(sourceOffset,
            (sourceOffset + 160).clamp(0, document.text.length).toInt())
        : segment.text;
    final offset = await showBookBookmarks(
      context: context,
      store: widget.store,
      book: widget.book,
      document: document,
      currentOffset: sourceOffset,
      currentExcerpt: excerpt,
    );
    if (!mounted || offset == null || _player != player) return;
    final destination = speechSegmentIndexForOffset(player.segments, offset);
    if (destination < 0) return;
    if (widget.book.format == BookFormat.epub) {
      if (offset < 0 || offset > document.text.length) return;
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player) return;
      await _select(destination, visualSourceOffset: offset);
    } else {
      await _select(destination);
    }
  }

  Future<void> _openSpeechSettings() async {
    await _player?.pause();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SpeechProviderScreen(
          store: widget.store,
          bookId: widget.book.id,
          vault: _vault,
        ),
      ),
    );
    if (!mounted) return;
    // Keep a visual/scanned PDF view available even without a text layer.
    // Recreating an audio player is necessary only in text-reading mode.
    if (widget.book.format == BookFormat.pdf && !_pdfTextMode) {
      setState(() {});
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Refresh the chosen adapter without losing the saved source position.
    await _load();
  }

  Future<void> _openPronunciations() async {
    if (_player?.isPlaying ?? false) await _player!.pause();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PronunciationScreen(
          store: widget.store,
          bookId: widget.book.id,
          bookTitle: widget.book.title,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pronunciationRules =
          widget.store.listPronunciationRules(bookId: widget.book.id);
    });
  }

  Future<void> _saveVoiceSettings() async {
    final player = _player;
    if (player == null) return;
    try {
      await widget.store.saveSpeechPreferences(
        player.currentPreferences, bookId: widget.book.id,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot save voice settings: ' + error.toString())),
      );
    }
  }

  Future<void> _playOrPause() async {
    final player = _player;
    if (player == null) return;
    try {
      if (widget.mediaHandler != null &&
          !widget.mediaHandler!.ownsPlayer(player)) {
        throw StateError('Audio session closed. Reopen this book to play.');
      }
      if (player.isPlaying) {
        await (widget.mediaHandler?.pause() ?? player.pause());
      } else {
        final prefs = player.currentPreferences;
        if (prefs.providerId == OpenAiSpeechEngine.providerId &&
            !widget.store.getConsent(
              widget.book.id, OpenAiSpeechEngine.providerId,
            ).allowed) {
          await _openSpeechSettings();
          return;
        }
        _cancelPendingVisualSave();
        // If the user browsed the pages manually, start audio where the
        // reading viewport is, not at the last audio-only position.
        final visible = _visiblePositionIndex;
        if (visible != null && visible != player.currentIndex &&
            // After a *completed* book, Play means start again, not
            // replay just its final segment. Explicit prior visual
            // navigation to an earlier part still takes precedence.
            (player.currentIndex < player.segments.length ||
                visible < player.segments.length - 1)) {
          await player.seekTo(visible);
        }
        await (widget.mediaHandler?.play() ?? player.play());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech failed: $error')),
        );
      }
    }
  }

  Future<void> _move(int delta) async {
    final player = _player;
    if (player == null) return;
    _cancelPendingVisualSave();
    await player.seekTo(player.currentIndex + delta);
    if (player.segments.isNotEmpty) {
      _visiblePositionIndex = player.currentIndex;
      if (widget.book.format == BookFormat.epub) {
        _visualCheckpoint.clear();
        _currentEpubVisualSourceOffset =
            player.segments[player.currentIndex].start;
        final target = _epubLayout.blockForSegment(player.currentIndex);
        _visualCheckpoint.hold(
            _currentEpubVisualSourceOffset, awaitTarget: true);
        _lastVisibleEpubBlockIndex = target;
        _lastFollowedIndex = target;
        if (_itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: target, alignment: 0.12);
        }
      }
      await widget.store.savePosition(
        widget.book.id,
        player.segments[player.currentIndex].start,
        anchor: _document?.anchorAt(
          widget.book.format, player.segments[player.currentIndex].start),
      );
    }
  }

  /// Internal EPUB links and notes are in-book source offsets only, never
  /// arbitrary URLs. A return position is recorded after a successful seek.
  void _navigateToSourceOffset(int sourceOffset, {
    required bool remember,
    bool preserveSearchHighlight = false,
  }) {
    Future<void> navigate() async {
      final player = _player;
      final document = _document;
      if (widget.book.format != BookFormat.epub || player == null ||
          document == null || player.segments.isEmpty ||
          sourceOffset < 0 || sourceOffset >= document.text.length) return;
      final sourceIndex = (player.isPlaying ? player.currentIndex
              : (_visiblePositionIndex ?? player.currentIndex))
          .clamp(0, player.segments.length - 1).toInt();
      final fromOffset = epubSourceOffsetForLinkReturn(
        speechOffset: player.segments[sourceIndex].start,
        narrationActive: player.isPlaying,
        visualOffset: _currentEpubVisualSourceOffset,
      );
      final index = speechSegmentIndexForOffset(
          player.segments, sourceOffset);
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player) return;
      // _select persists the exact source offset once. A second write of
      // the same position after seeking is unnecessary and can race with
      // user scrolls or turn a failed checkpoint into a partial jump.
      await _select(index, visualSourceOffset: sourceOffset,
          preserveSearchHighlight: preserveSearchHighlight);
      if (!mounted || _player != player) return;
      if (remember) {
        _linkHistory.push(fromOffset, sourceOffset);
        setState(() {});
      }
    }
    unawaited(navigate().catchError((Object error, StackTrace stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open EPUB destination: $error')),
      );
    }));
  }

  /// A note peek only displays source-verified local text. Dismissing it
  /// never seeks, updates SQLite progress, changes the back stack, or
  /// starts/stops the speech engine. "Open in book" remains explicit.
  Future<void> _previewEpubFootnote(int sourceOffset) async {
    final document = _document;
    if (!mounted || widget.book.format != BookFormat.epub ||
        document == null) return;
    final matches = document.epubFootnotePreviews.where(
        (item) => item.targetOffset == sourceOffset);
    if (matches.isEmpty) {
      // An unsupported/overlong note remains a regular safe internal link.
      _openEpubLink(sourceOffset);
      return;
    }
    final note = matches.first;
    final openFull = await showEpubFootnotePreview(context, note);
    if (!mounted || _document != document || openFull != true) return;
    _navigateToSourceOffset(sourceOffset, remember: true);
  }

  Future<void> _previewAuxiliaryEpubFootnote(String key) async {
    if (!mounted || widget.book.format != BookFormat.epub) return;
    final document = _document;
    if (document == null) return;
    final previews = document.epubAuxiliaryFootnotePreviews
        .where((note) => note.key == key);
    if (previews.isEmpty) return; // Invalid/stale reference: fail closed.
    // A non-spine note is read-only: do not call seek, savePosition,
    // play/pause, cloud APIs, or add anything to the link return stack.
    await showEpubAuxiliaryFootnotePreview(context, previews.first);
  }

  void _openEpubLink(int sourceOffset) =>
      _navigateToSourceOffset(sourceOffset, remember: true);

  void _returnFromEpubLink() {
    Future<void> navigateBack() async {
      final offset = _linkHistory.last;
      final player = _player;
      final document = _document;
      if (offset == null || player == null || player.segments.isEmpty ||
          document == null || offset < 0 ||
          offset >= document.text.length) return;
      final index = speechSegmentIndexForOffset(
          player.segments, offset);
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player) return;
      await _select(index, visualSourceOffset: offset);
      if (!mounted || _player != player) return;
      _linkHistory.commitReturn();
      setState(() {});
    }
    unawaited(navigateBack().catchError((Object error, StackTrace stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot return from EPUB note: $error')),
      );
    }));
  }

  void _selectFromVisualTap(int index) {
    Future<void> navigate() async {
      final player = _player;
      // EPUB is an explicit reading-location selection, not permission
      // to re-synthesize a new paragraph while narration is active.
      // Also cancel any pending seek/voice auto-resume before seeking.
      if (widget.book.format == BookFormat.epub &&
          player != null && !player.isSettledIdle) {
        await player.pause();
      }
      if (!mounted || _player != player) return;
      await _select(index);
    }
    unawaited(navigate().catchError(
      (Object error, StackTrace stack) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot select passage: $error')),
        );
      },
    ));
  }

  Future<void> _select(int index, {
    int? visualSourceOffset,
    bool preserveSearchHighlight = false,
  }) async {
    final player = _player;
    final visualOnlyEnd = widget.book.format == BookFormat.epub &&
        visualSourceOffset != null && index == player?.segments.length;
    if (player == null || index < 0 ||
        (index >= player.segments.length && !visualOnlyEnd)) return;
    // Navigating elsewhere clears a previous search-result highlight.
    if (!preserveSearchHighlight) _selectedSourceSearchHit = null;
    // A prior scroll debounce must never overwrite this explicit seek
    // or a source-exact bookmark/search hit after the next frame.
    _cancelPendingVisualSave();
    if (visualOnlyEnd) {
      await player.seekToSourceEnd();
    } else {
      await player.seekTo(index);
    }
    if (!mounted || _player != player) return;
    // A verified EPUB link may point inside the current audio segment
    // or into a paragraph without any speech. Save that exact source
    // position, rather than saving a coarse TTS start and then rewriting.
    final sourceOffset = widget.book.format == BookFormat.epub &&
            visualSourceOffset != null
        ? visualSourceOffset : player.segments[index].start;
    await widget.store.savePosition(
      widget.book.id, sourceOffset,
      anchor: _document?.anchorAt(widget.book.format, sourceOffset),
    );
    _visiblePositionIndex = player.segments.isEmpty ? null
        : index.clamp(0, player.segments.length - 1).toInt();
    _currentEpubVisualSourceOffset = widget.book.format == BookFormat.epub
        ? sourceOffset : null;
    // Protect all explicit EPUB seeks from a transient stale viewport,
    // not only jumps with an additional user-specified source offset.
    _visualCheckpoint.hold(widget.book.format == BookFormat.epub
        ? sourceOffset : null,
        awaitTarget: widget.book.format == BookFormat.epub);
    final visualIndex = widget.book.format == BookFormat.epub
        ? _epubLayout.blockForSourceOffset(sourceOffset) : index;
    _lastVisibleEpubBlockIndex = widget.book.format == BookFormat.epub
        ? visualIndex : null;
    if (_itemScrollController.isAttached) {
      _lastFollowedIndex = visualIndex;
      _itemScrollController.jumpTo(index: visualIndex, alignment: 0.12);
    }
    if (mounted && _player == player &&
        widget.book.format == BookFormat.epub) {
      // A programmatic jump may not emit a new visible-item notification:
      // update the chapter and publisher directory indicator explicitly.
      setState(() {});
    }
  }

  void _recordEpubFrames(List<FrameTiming> frames) {
    final sampler = _activeFrameSampler;
    if (sampler == null) return;
    for (final frame in frames) {
      sampler.record(
        buildUs: frame.buildDuration.inMicroseconds,
        rasterUs: frame.rasterDuration.inMicroseconds,
        totalUs: frame.totalSpan.inMicroseconds,
      );
    }
  }

  void _startFrameCapture() {
    if (!mounted || widget.book.format != BookFormat.epub ||
        _loading || _player == null || _activeFrameSampler != null) return;
    _frameProfile = null;
    _activeFrameSampler = EpubFrameSampler();
    SchedulerBinding.instance.addTimingsCallback(_recordEpubFrames);
    _frameCaptureTimer = Timer(const Duration(seconds: 12), () {
      _stopFrameCapture();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reader frame sample finished. Open the '
              'EPUB performance report to inspect it.'),
        ));
      }
    });
    setState(() {});
  }

  void _stopFrameCapture({bool discard = false, bool notify = true}) {
    final sampler = _activeFrameSampler;
    if (sampler == null) return;
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;
    SchedulerBinding.instance.removeTimingsCallback(_recordEpubFrames);
    _activeFrameSampler = null;
    _frameProfile = discard ? null : sampler.snapshot();
    if (notify && mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ReaderLifecyclePolicy.backgroundTransition(state)) return;
    // Do not attribute background, other-app or resume frames to this book.
    _stopFrameCapture(discard: true);
    // A deferred viewport write must never replace the segment anchor
    // recorded by background audio. Leave Android narration running only
    // when a live media handler owns that player.
    _saveVisualPositionTimer?.cancel();
    _flushPdfPagePosition();
    if (_player != null &&
        ReaderLifecyclePolicy.mustPauseOnBackground(
          state: state,
          isAndroid: Platform.isAndroid,
          mediaOwnsPlayer:
              widget.mediaHandler?.ownsPlayer(_player!) == true,
        )) {
      unawaited(_player!.pause().catchError((Object error, StackTrace stack) {
        if (!mounted) return;
        _onPlaybackChanged();
      }));
    }
    // Reopening is always user-driven: never auto-call play() on resumed.
  }

  @override
  void dispose() {
    _stopFrameCapture(discard: true, notify: false);
    ++_loadEpoch;
    _activeEpubTask?.cancel();
    _activeEpubTask = null;
    WidgetsBinding.instance.removeObserver(this);
    _saveVisualPositionTimer?.cancel();
    _flushPdfPagePosition();
    _pdfController.dispose();
    _itemPositionsListener.itemPositions.removeListener(_onVisiblePositions);
    final player = _player;
    if (player != null) {
      widget.mediaHandler?.detach(player);
      player.removeListener(_onPlaybackChanged);
      _recoveryBinding?.dispose();
      player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          if (widget.book.format == BookFormat.epub &&
              !_loading && _epubWorkerTimings != null)
            IconButton(
              icon: const Icon(Icons.speed_outlined),
              tooltip: 'EPUB opening performance',
              onPressed: () => showEpubOpeningPerformance(
                context,
                worker: _epubWorkerTimings!,
                castLayoutUs: _epubCastLayoutUs!,
                voiceSetupUs: _epubVoiceSetupUs!,
                totalOpenUs: _epubTotalOpenUs!,
                firstFrameUs: _epubFirstFrameUs,
                frameProfile: _frameProfile,
                frameCaptureActive: _activeFrameSampler != null,
                onStartFrameCapture: _startFrameCapture,
                onStopFrameCapture: _stopFrameCapture,
              ),
            ),
          if (widget.book.format == BookFormat.epub &&
              (_document?.epubDiagnostics.isNotEmpty ?? false))
            IconButton(
              icon: const Icon(Icons.report_problem_outlined),
              tooltip: 'EPUB compatibility report',
              onPressed: () => showEpubImportDiagnostics(
                context, _document!.epubDiagnostics,
              ),
            ),
          if (widget.book.format == BookFormat.epub)
            PopupMenuButton<EpubReadingPalette>(
              tooltip: 'EPUB reading colors',
              icon: const Icon(Icons.palette_outlined),
              initialValue: _epubPalette,
              onSelected: (palette) =>
                  setState(() => _epubPalette = palette),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: EpubReadingPalette.system,
                  child: Text('Follow device theme'),
                ),
                PopupMenuItem(
                  value: EpubReadingPalette.sepia,
                  child: Text('Warm paper'),
                ),
                PopupMenuItem(
                  value: EpubReadingPalette.night,
                  child: Text('Night reading'),
                ),
              ],
            ),
          if (widget.book.format == BookFormat.epub &&
              _linkHistory.canReturn)
            IconButton(
              tooltip: 'Return from note or internal link',
              icon: const Icon(Icons.keyboard_return),
              onPressed: _returnFromEpubLink,
            ),
          if (widget.book.format == BookFormat.epub &&
              (_chapters.isNotEmpty || _authorToc.isNotEmpty))
            IconButton(
              tooltip: _authorToc.isNotEmpty
                  ? 'Book table of contents' : 'EPUB spine sections',
              icon: const Icon(Icons.view_list),
              onPressed: _openChapterDirectory,
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'TTS engines, models and cloud consent',
            onPressed: _openSpeechSettings,
          ),
          if (_player != null && _player!.segments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.theater_comedy_outlined),
              tooltip: 'Characters and manual voice cast',
              onPressed: _openCastEditor,
            ),
          if (_player != null && _player!.segments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search this book',
              onPressed: _searchInBook,
            ),
          if (_player != null && _player!.segments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              tooltip: 'Bookmarks',
              onPressed: _openBookmarks,
            ),
          IconButton(
            icon: const Icon(Icons.spellcheck),
            tooltip: 'Pronunciation dictionary',
            onPressed: _openPronunciations,
          ),
          if (widget.book.format != BookFormat.pdf || _pdfTextMode)
            IconButton(
              tooltip: _autoFollow
                  ? 'Disable auto-scroll while listening'
                  : 'Enable auto-scroll while listening',
              icon: Icon(_autoFollow ? Icons.my_location : Icons.location_disabled),
              onPressed: () {
                setState(() => _autoFollow = !_autoFollow);
                if (_autoFollow) {
                  _lastFollowedIndex = -1;
                  _onPlaybackChanged();
                }
              },
            ),
          if (widget.book.format == BookFormat.pdf && _pdfTextMode)
            IconButton(
              tooltip: 'Return to PDF pages',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                await _player?.pause();
                _saveVisualPositionTimer?.cancel();
                if (!mounted) return;
                final speech = _player;
                final document = _document;
                if (speech != null && document != null &&
                    speech.segments.isNotEmpty) {
                  final offset = speech.segments[
                      speech.currentIndex.clamp(
                          0, speech.segments.length - 1).toInt()].start;
                  final page = pdfVisualPageForTextOffset(
                    document.pdfPageRanges, offset,
                  );
                  if (page != null) _displayPdfPage = page;
                }
                setState(() => _pdfTextMode = false);
                _onPdfPageChanged(_displayPdfPage);
              },
            ),
          if (widget.book.format != BookFormat.pdf || _pdfTextMode)
            IconButton(
              icon: const Icon(Icons.text_increase),
              tooltip: 'Increase font size',
              onPressed: () => setState(() =>
                  _fontSize = (_fontSize + 2).clamp(14.0, 32.0).toDouble()),
            ),
          if (widget.book.format != BookFormat.pdf || _pdfTextMode)
            IconButton(
              icon: const Icon(Icons.text_decrease),
              tooltip: 'Decrease font size',
              onPressed: () => setState(() =>
                  _fontSize = (_fontSize - 2).clamp(14.0, 32.0).toDouble()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: SelectableText(_error!))
              : widget.book.format == BookFormat.pdf && !_pdfTextMode
                  ? Column(
                      children: [
                        MaterialBanner(
                          content: const Text(
                            'PDF view. Experimental read-aloud uses the '
                            'PDF text layer; reading order may be incorrect '
                            'for columns, notes or complex layouts.',
                          ),
                          actions: [
                            TextButton.icon(
                              onPressed: () {
                                _flushPdfPagePosition();
                                _saveVisualPositionTimer?.cancel();
                                setState(() {
                                  _pdfTextMode = true;
                                  _loading = true;
                                  _error = null;
                                });
                                _load(requestedPdfPage: _displayPdfPage);
                              },
                              icon: const Icon(Icons.record_voice_over),
                              label: const Text('Read text aloud'),
                            ),
                          ],
                        ),
                        PdfPageNavigation(
                          pageNumber: _displayPdfPage,
                          pageCount: _pdfPageCount,
                          onPageRequested: _goToPdfPage,
                          onZoomOut: () {
                            if (_pdfController.isReady) {
                              unawaited(_pdfController.zoomDown());
                            }
                          },
                          onZoomIn: () {
                            if (_pdfController.isReady) {
                              unawaited(_pdfController.zoomUp());
                            }
                          },
                        ),
                        Expanded(
                          child: PdfViewer.file(
                            widget.book.localPath,
                            controller: _pdfController,
                            initialPageNumber: _displayPdfPage,
                            params: PdfViewerParams(
                              onPageChanged: _onPdfPageChanged,
                              onViewerReady: _onPdfReady,
                            ),
                          ),
                        ),
                      ],
                    )
                  : player == null || player.segments.isEmpty
                      ? const Center(child: Text('No readable text'))
                      : Column(
                          children: [
                            Expanded(
                              child: Container(
                                color: widget.book.format == BookFormat.epub
                                    ? _epubPalette.background(context) : null,
                                child: SelectionArea(
                                  child: ScrollablePositionedList.builder(
                                  // A new EPUB extraction/casting pass changes
                                  // the block index. Remount to honor the
                                  // restored anchor after the user edits voices.
                                  key: widget.book.format == BookFormat.epub
                                      ? ObjectKey(_epubLayout) : null,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 24,
                                  ),
                                  itemCount: widget.book.format == BookFormat.epub
                                      ? _epubLayout.blocks.length
                                      : player.segments.length,
                                  itemScrollController: _itemScrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  initialScrollIndex: widget.book.format ==
                                          BookFormat.epub
                                      ? (_visualCheckpoint.offset == null
                                          ? _epubLayout.blockForSegment(
                                              player.currentIndex)
                                          : _epubLayout.blockForSourceOffset(
                                              _visualCheckpoint.offset!))
                                      : player.currentIndex.clamp(
                                          0, player.segments.length - 1).toInt(),
                                  itemBuilder: (context, index) {
                                    if (widget.book.format == BookFormat.epub) {
                                      final block = _epubLayout.blocks[index];
                                      return EpubParagraphTile(
                                        key: ValueKey(block.start),
                                        block: block,
                                        activeSegmentIndex: player.currentIndex,
                                        searchMatch: _selectedSourceSearchHit,
                                        fontSize: _fontSize,
                                        palette: _epubPalette,
                                        onSelectSegment: _selectFromVisualTap,
                                        onOpenLink: _openEpubLink,
                                        onOpenFootnote: (offset) =>
                                            unawaited(_previewEpubFootnote(offset)),
                                        onOpenAuxiliaryFootnote: (key) =>
                                            unawaited(_previewAuxiliaryEpubFootnote(key)),
                                      );
                                    }
                                    final segment = player.segments[index];
                                    final heading = isStandaloneChapterHeading(
                                      _chapterStarts[index], segment,
                                    );
                                    final selected =
                                        index == player.currentIndex;
                                    return InkWell(
                                      onTap: () => _selectFromVisualTap(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        margin: const EdgeInsets.only(bottom: 6),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: selected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                              : null,
                                        ),
                                        child: Semantics(
                                          header: heading,
                                          child: Text(
                                            segment.text,
                                            style: TextStyle(
                                              fontSize: heading
                                                  ? _fontSize + 5 : _fontSize,
                                              fontWeight: heading
                                                  ? FontWeight.w600 : null,
                                              height: heading ? 1.3 : 1.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  ),
                                ),
                              ),
                            ),
                            _controls(player),
                          ],
                        ),
    );
  }

  Widget _controls(ReaderPlayer player) {
    final count = player.segments.length;
    return SafeArea(
      top: false,
      child: Material(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_chapters.isNotEmpty || _authorToc.isNotEmpty) ...[
                Builder(builder: (context) {
                  final index = _currentDirectoryIndex;
                  final authorial = _authorToc.isNotEmpty;
                  final total = authorial
                      ? _authorToc.length : _chapters.length;
                  if (index < 0 || index >= total) {
                    return const SizedBox.shrink();
                  }
                  final label = authorial
                      ? _authorToc[index].label : _chapters[index].title;
                  return Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous EPUB section',
                        onPressed: index > 0
                            ? () => _jumpDirectoryIndex(index - 1) : null,
                        icon: const Icon(Icons.first_page),
                      ),
                      Expanded(
                        child: Text(
                          '$label (${index + 1}/$total)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next EPUB section',
                        onPressed: index + 1 < total
                            ? () => _jumpDirectoryIndex(index + 1) : null,
                        icon: const Icon(Icons.last_page),
                      ),
                    ],
                  );
                }),
              ],
              Text(
                player.currentIndex >= count
                    ? 'Reading complete — Play to restart'
                    : 'Segment ${player.currentIndex + 1} of $count',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (player.activeSpeakerId != null)
                Text('Speaker: ' +
                    (_castNames[player.activeSpeakerId] ?? 'Unknown')
                  , style: Theme.of(context).textTheme.labelSmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous segment',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () => _move(-1),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _playOrPause,
                    icon: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(player.isPlaying ? 'Pause' : 'Play'),
                  ),
                  IconButton(
                    tooltip: 'Next segment',
                    icon: const Icon(Icons.skip_next),
                    onPressed: () => _move(1),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Sleep timer',
                    icon: Icon(player.sleepTimerEndsAt == null
                        ? Icons.bedtime_outlined : Icons.bedtime),
                    onSelected: (minutes) {
                      if (minutes == 0) {
                        player.cancelSleepTimer();
                      } else {
                        player.setSleepTimer(Duration(minutes: minutes));
                      }
                    },
                    itemBuilder: (_) => [
                      if (player.sleepTimerEndsAt != null)
                        const PopupMenuItem(
                          value: 0, child: Text('Turn off sleep timer'),
                        ),
                      for (final minutes in [10, 15, 30, 45, 60])
                        PopupMenuItem(
                          value: minutes,
                          child: Text('Stop after $minutes minutes'),
                        ),
                    ],
                  ),
                ],
              ),
              if (player.sleepTimerEndsAt != null)
                Text(
                  'Sleep timer: stops at ${TimeOfDay.fromDateTime(player.sleepTimerEndsAt!).format(context)}'
                  ' (continues while paused)',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (_epubSpeechNoteFilter?.hasNotes ?? false)
                CheckboxListTile(
                  key: const ValueKey('epub-skip-spoken-notes'),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Skip EPUB footnotes in narration'),
                  subtitle: const Text(
                    'Optional, off by default. Skips only fully contained '
                    'verified note passages. Notes remain visible and '
                    'searchable; mixed passages are spoken to avoid '
                    'losing main text. Already sent cloud prebuffers cannot '
                    'be recalled.',
                  ),
                  value: _skipEpubNotes,
                  onChanged: (value) =>
                      setState(() => _skipEpubNotes = value ?? false),
                ),
              if (player.engineProviderId ==
                  OpenAiSpeechEngine.providerId)
                CheckboxListTile(
                  key: const ValueKey('cloud-cache-only-warmup'),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Warm already cached cloud audio'),
                  subtitle: const Text(
                    'On by default. Only reads a previously generated '
                    'private MP3 and prepares the next decoder locally. '
                    'Never makes an extra network request or reserves '
                    'provider characters. Disable to compare playback.',
                  ),
                  value: player.warmCachedCloudChunk,
                  onChanged: (enabled) =>
                      player.setCachedCloudWarmup(enabled ?? false),
                ),
              if (player.engineProviderId ==
                  OpenAiSpeechEngine.providerId)
                CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Prebuffer one cloud audio chunk'),
                  subtitle: const Text(
                    'Optional, off by default. The next chunk may be '
                    'sent to OpenAI and charged while the current one '
                    'plays, even if you pause or skip before hearing it. '
                    'Only one future chunk is prepared.',
                  ),
                  value: player.prefetchNextCloudChunk,
                  onChanged: (enabled) => player.setCloudPrefetch(
                      enabled ?? false),
                ),
              if (player.availableVoices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const Text('Voice'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<SpeechVoice>(
                          isExpanded: true,
                          hint: const Text('Default system voice'),
                          value: player.selectedVoice,
                          items: player.availableVoices.map((voice) {
                            return DropdownMenuItem(
                              value: voice,
                              child: Text(
                                voice.toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (voice) async {
                            if (voice == null) return;
                            try {
                              await player.selectVoice(voice);
                              await _saveVoiceSettings();
                            } catch (error) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Voice unavailable: $error')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      player.currentPreferences.providerId == 'system'
                          ? 'Engine: system voice'
                          : 'Engine: OpenAI Speech (cloud)',
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Speech preference scope',
                    icon: const Icon(Icons.settings_voice),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'make-global',
                        child: Text('Save as global default'),
                      ),
                      PopupMenuItem(
                        value: 'use-global',
                        child: Text('Use global defaults for this book'),
                      ),
                    ],
                    onSelected: (action) async {
                      try {
                        if (action == 'make-global') {
                          await widget.store.saveSpeechPreferences(
                            player.currentPreferences,
                          );
                        } else if (action == 'use-global') {
                          await player.pause();
                          await widget.store.clearBookSpeechPreferences(
                            widget.book.id,
                          );
                          await player.applyPreferences(
                            widget.store.getSpeechPreferences(
                              bookId: widget.book.id,
                            ),
                          );
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Voice preferences updated'),
                            ),
                          );
                        }
                      } catch (error) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(
                              'Voice settings error: ' + error.toString(),
                            )),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  Text(player.currentPreferences.providerId == 'system'
                      ? 'Pitch' : 'Pitch unavailable'),
                  Expanded(
                    child: Slider(
                      min: 0.5,
                      max: 1.5,
                      divisions: 10,
                      value: player.pitch,
                      onChanged: player.currentPreferences.providerId == 'system'
                          ? (value) {
                              player.setPitch(value);
                            }
                          : null,
                      onChangeEnd: player.currentPreferences.providerId == 'system'
                          ? (_) {
                              unawaited(player.restartAfterSettingsChange());
                              unawaited(_saveVoiceSettings());
                            }
                          : null,
                    ),
                  ),
                  Text(player.pitch.toStringAsFixed(1)),
                ],
              ),
              Row(
                children: [
                  const Text('Speed'),
                  Expanded(
                    child: Slider(
                      min: 0.2,
                      max: 1.0,
                      divisions: 8,
                      value: player.rate,
                      onChanged: (value) {
                        player.setRate(value);
                      },
                      onChangeEnd: (_) {
                        unawaited(player.restartAfterSettingsChange());
                        unawaited(_saveVoiceSettings());
                      },
                    ),
                  ),
                  Text(player.rate.toStringAsFixed(1)),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: player.language,
                    items: <String>{
                      'it-IT', 'en-US', player.language,
                      ...player.availableVoices.map((voice) => voice.locale),
                    }.map((locale) => DropdownMenuItem(
                      value: locale,
                      child: Text(locale),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        player.setLanguage(value);
                        unawaited(player.restartAfterSettingsChange());
                        unawaited(_saveVoiceSettings());
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
