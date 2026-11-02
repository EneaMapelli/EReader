import 'dart:async';
import 'dart:io' show Directory, Platform;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
 import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../audio/reader_player.dart';
import '../../audio/narration_transition_diagnostics.dart';
import '../../audio/reader_activity_tracker.dart';
import '../../domain/reading_activity.dart';
import '../../audio/reader_media_handler.dart';
import '../../audio/narration_recovery_binding.dart';
import '../../audio/reader_lifecycle_policy.dart';
import '../../audio/speech_engine.dart';
import '../../audio/speech_engine_factory.dart';
import '../../audio/openai_speech_engine.dart';
import '../../audio/secret_vault.dart';
import '../../audio/sherpa_vits_engine.dart';
import 'speech_provider_screen.dart';
import '../../data/book_decoder.dart';
import '../../data/offline_voice_pack.dart';
import '../../data/pdf_text_navigation.dart';
import 'pdf_page_navigation.dart';
import 'pdf_visual_bookmarks_sheet.dart';
import 'pdf_speech_navigation.dart';
import '../../data/epub_reader_preflight.dart';
import '../../data/epub_speech_note_filter.dart';
import '../../data/epub_progress_recovery.dart';
import '../../domain/library_full_text.dart';
import '../../data/library_store.dart';
import '../../domain/reading_preferences.dart';
import '../../domain/book.dart';
import '../../domain/book_search.dart';
import '../../domain/reading_anchor.dart';
import '../../domain/speech_segment.dart';
import '../../domain/dialogue_segmenter.dart';
import '../../domain/pronunciation_rule.dart';
import '../../domain/cast_span.dart';
import 'voice_cast_screen.dart';
import 'pronunciation_screen.dart';
import 'reading_tools.dart';
import 'epub_chapter_navigation.dart';
import 'reader_chapter_directory_sheet.dart';
import 'epub_link_history.dart';
import 'epub_note_preview_sheet.dart';
import '../../data/epub_navigation.dart';
import 'epub_visual_layout.dart';
import 'epub_progressive_layout.dart';
import 'epub_paragraph_tile.dart';
import 'epub_diagnostics_sheet.dart';
import 'epub_opening_performance_sheet.dart';
import 'epub_frame_sampler.dart';
import 'reader_keyboard_shortcuts.dart';
import 'reader_compact_controls.dart';
import 'reader_focus_restore_button.dart';
import 'reader_focus_progress_strip.dart';
import 'reader_narration_follow_policy.dart';
import 'reader_source_selection_gate.dart';
import 'reader_position_ownership.dart';
import 'reader_return_to_narration_button.dart';
import 'reader_narration_status_indicator.dart';
import 'reader_viewport_layout.dart';
import 'reader_viewport_save_gate.dart';
import 'reader_direct_scroll_input.dart';
import '../shared/organized_action_sheet.dart';
import 'reader_tool_menu_options.dart';
import 'reading_progress_bar.dart';
import 'reader_go_to_progress_dialog.dart';
import 'reader_section_range.dart';
import 'reader_progress_return_point.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key, required this.book, required this.store, this.mediaHandler,
    this.initialSearchJump,
  });
  final BookRecord book;
  final LibraryStore store;
  final ReaderMediaHandler? mediaHandler;
  /// Optional visual-only source hint from a local full-text search result.
  /// It never directly persists a reading checkpoint or starts narration.
  final LibraryFullTextJump? initialSearchJump;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final SpeechSecretVault _vault = PlatformSpeechSecretVault();
  ReaderPlayer? _player;
  ReaderActivityTracker? _readingActivityTracker;
  bool _readerForeground = true;
  DateTime? _lastReadingInteraction;

  /// Count visual time only after an explicit reader gesture. A dormant
  /// screen times out after three minutes; audio is its own exclusive mode.
  ReadingActivityMode? _currentReadingActivityMode() {
    if (!mounted || !widget.store.isReadingActivityTrackingEnabled) {
      return null;
    }
    final player = _player;
    final onReaderRoute = ModalRoute.of(context)?.isCurrent ?? false;
    final audioVisible = _readerForeground && onReaderRoute;
    final backgroundMedia = player != null && Platform.isAndroid &&
        widget.mediaHandler?.ownsPlayer(player) == true;
    if (player != null && player.isPlaying &&
        (audioVisible || backgroundMedia)) {
      return ReadingActivityMode.tts;
    }
    final interaction = _lastReadingInteraction;
    if (!audioVisible || _loading || interaction == null ||
        DateTime.now().difference(interaction) >
            const Duration(minutes: 3)) {
      return null;
    }
    return ReadingActivityMode.visual;
  }

  Duration _visualTimeRemaining() {
    final interaction = _lastReadingInteraction;
    if (!_readerForeground || _loading || interaction == null) {
      return Duration.zero;
    }
    final remaining = const Duration(minutes: 3) -
        DateTime.now().difference(interaction);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  void _onReadingGesture() {
    // An explicit opt-out also avoids capturing the last gesture in memory.
    if (!_readerForeground || _loading ||
        !widget.store.isReadingActivityTrackingEnabled) return;
    _lastReadingInteraction = DateTime.now();
    _readingActivityTracker?.refresh();
  }

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
  bool _initialSearchJumpConsumed = false;
  CancellableEpubPreflight? _activeEpubTask;
  EpubPreflightTimings? _epubWorkerTimings;
  int? _epubCastLayoutUs;
  int? _epubVoiceSetupUs;
  int? _epubTotalOpenUs;
  int? _epubFirstFrameUs;
  EpubFrameSampler? _activeFrameSampler;
  EpubFrameProfile? _frameProfile;
  Timer? _frameCaptureTimer;
  ReadingPreferences _readingPrefs = const ReadingPreferences();
  double get _fontSize => _readingPrefs.fontSize;
  EpubReadingPalette get _epubPalette =>
      EpubReadingPalette.values.byName(_readingPrefs.palette);
  bool _pdfTextMode = false;
  final ReaderNarrationFollowPolicy _narrationFollow =
      ReaderNarrationFollowPolicy();
  bool _followUiRefreshQueued = false;
  bool _visualProgressRefreshQueued = false;
  // Keep the page itself spacious. Playback settings are available on demand.
  bool _advancedControlsExpanded = false;
  bool _readerFocusMode = false;
  final ScrollController _advancedControlsScroll = ScrollController();
  final ReaderViewportSaveGate _viewportSaveGate = ReaderViewportSaveGate();
  final ReaderProgressReturnPoint _progressReturn = ReaderProgressReturnPoint();
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
  // Only the latest in-reader source selection can persist its bookmark.
  // A superseded Seek may return successfully once native Stop settles;
  // it must not write its obsolete visual location afterward.
  final ReaderSourceSelectionGate _sourceSelectionGate =
      ReaderSourceSelectionGate();
  // Fast progress updates while manually scrolling must not rebuild
  // the entire potentially large EPUB/painted-document widget tree.
  final ValueNotifier<int> _visualProgressTick = ValueNotifier<int>(0);

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
  // Disambiguates visual-only OPF items sharing identical UTF-16 offsets.
  String? _selectedVisualSpineIdref;
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
  void didChangeMetrics() {
    // Rotation, split-screen resizing and keyboard-inset changes may alter
    // the first visible source paragraph without user scroll intent. Never
    // persist a transient viewport coordinate during that relayout.
    _cancelPendingVisualSave();
    _viewportSaveGate.suspendForLayoutChange();
    super.didChangeMetrics();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A route becomes available only after the first frame; do not access
    // ModalRoute.of(context) from initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.store.isReadingActivityTrackingEnabled) return;
      // Disabled means no sampler or periodic activity timer is created.
      _readingActivityTracker = ReaderActivityTracker(
        store: widget.store,
        bookId: widget.book.id,
        mode: _currentReadingActivityMode,
        visualTimeRemaining: _visualTimeRemaining,
      );
    });
    _itemPositionsListener.itemPositions.addListener(_onVisiblePositions);
    _readingPrefs = widget.store.getReadingPreferences(bookId: widget.book.id);
    _displayPdfPage = widget.book.format == BookFormat.pdf
        ? widget.store.getPdfVisualPage(widget.book.id)
        : 1;
    if (widget.book.format == BookFormat.pdf &&
        widget.initialSearchJump != null) {
      // Search points into selectable PDF text, not physical viewer pages.
      // Enter text mode without modifying the saved PDF page bookmark.
      _pdfTextMode = true;
    }
    if (widget.book.format != BookFormat.pdf || _pdfTextMode) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load({int? requestedPdfPage}) async {
    // A later reload supersedes all earlier work, including an in-flight
    // worker that would otherwise continue unpacking ZIP/XHTML offscreen.
    final epoch = ++_loadEpoch;
    _sourceSelectionGate.invalidate();
    _cancelPendingVisualSave();
    _progressReturn.clear();
    _narrationFollow.resetForBook();
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
      InstalledOfflineVoicePack? selectedLocalVoice;
      if (prefs.providerId == SherpaVitsSpeechEngine.providerId) {
        // No automatic download, FFI probe or cloud fallback. Verify the
        // exact selected on-disk pack before constructing a native engine.
        // The model is an explicit alpha choice, never a default.
        if (!Platform.isWindows) {
          throw UnsupportedError(
              'Offline neural voice trial currently requires Windows');
        }
        final support = await getApplicationSupportDirectory();
        selectedLocalVoice = await loadInstalledOfflineVoicePack(
          packId: prefs.modelId,
          modelsDirectory: Directory(p.join(support.path, 'offline-voices')),
        );
        if (!mounted || epoch != _loadEpoch) return;
      }
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
        // A small cancellable breath is useful ONLY at actual
        // narrator/character voice changes. Leave cloud and VITS timing
        // untouched; no pause at plain narrator sentence boundaries.
        dialogueTurnPause:
            Duration(milliseconds: prefs.dialogueTurnPauseMs),
        engine: SpeechEngineFactory(
            vault: _vault, offlineVoicePack: selectedLocalVoice).create(
          preferences: prefs,
          bookId: widget.book.id,
          store: widget.store,
        ),
        segments: chunks,
        chapterStartIndices: {
          for (final chapter in chapters)
            if (chapter.hasSpeech) chapter.segmentIndex,
        },
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
      // FTS stores extracted UTF-16 positions, not EPUB byte offsets or PDF
      // page numbers. Verify the exact text on a FRESH decode: the source
      // may have been rewritten or the extractor updated since indexing.
      // A valid hit is a visual-only opening location, not a new bookmark.
      final requestedSearchJump = _initialSearchJumpConsumed
          ? null : widget.initialSearchJump;
      final verifiedSearchOffset =
          requestedSearchJump?.validatedOffset(document.text);
      if (verifiedSearchOffset != null) saved = verifiedSearchOffset;
      final searchPdfPage = verifiedSearchOffset != null &&
              widget.book.format == BookFormat.pdf
          ? pdfVisualPageForTextOffset(
              document.pdfPageRanges, verifiedSearchOffset)
          : null;
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
      if (verifiedSearchOffset == null &&
          requestedSearchJump == null &&
          epubRecovery?.shouldPersist == true) {
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
      final savedSilentSpine = widget.book.format == BookFormat.epub &&
          latestBook.progressAnchor?.kind == AnchorKind.epubSpine &&
          chapters.any((chapter) => !chapter.hasSpeech &&
              chapter.idref == latestBook.progressAnchor?.sourceId)
          ? latestBook.progressAnchor!.sourceId : null;
      final previous = _player;
      if (previous != null) {
        widget.mediaHandler?.detach(previous);
        previous.removeListener(_onPlaybackChanged);
        _recoveryBinding?.dispose();
        previous.dispose();
      }
      final restoredBlock = savedSilentSpine == null
          ? visualLayout.blockForSourceOffset(saved)
          : visualLayout.blockForSpine(savedSilentSpine, saved);
      _visualCheckpoint.hold(widget.book.format == BookFormat.epub
          && chunks.isNotEmpty && saved >= 0 && saved <= document.text.length
          ? saved : null, awaitTarget: true,
          targetBlockIndex: widget.book.format == BookFormat.epub
              ? restoredBlock : null);
      _lastFollowedIndex = widget.book.format == BookFormat.epub
          ? (_visualCheckpoint.offset == null
              ? visualLayout.blockForSegment(player.currentIndex)
              : restoredBlock)
          : player.currentIndex;
      // A completed speech cursor equals chunks.length, which is NOT a
      // visual-list index. Show the last text block without allowing its
      // initial viewport notification to rewrite an EOF bookmark.
      _visiblePositionIndex = chunks.isEmpty ? null
          : player.currentIndex.clamp(0, chunks.length - 1).toInt();
      _currentEpubVisualSourceOffset = widget.book.format == BookFormat.epub
          ? saved : null;
      _selectedVisualSpineIdref = savedSilentSpine;
      _lastVisibleEpubBlockIndex = widget.book.format == BookFormat.epub
          ? _lastFollowedIndex : null;
      recoveryBinding.attach(player);
      player.addListener(_onPlaybackChanged);
      // Windows has no AudioService media handler: do not materialize
      // a chapter-index map for books opened only in the desktop reader.
      final remoteChapterTargets = widget.mediaHandler != null &&
              widget.book.format == BookFormat.epub
          ? buildEpubMediaChapterTargets(
              chapters, chunks.length, document.text.length)
          : const <int, EpubMediaChapterTarget>{};
      widget.mediaHandler?.attach(
        player,
        bookId: widget.book.id,
        title: widget.book.title,
        chapterSegmentStarts: [
          for (final chapter in chapters)
            if (chapter.hasSpeech) chapter.segmentIndex,
        ],
        onRemoteNavigation: (index) {
          // Media controls operate directly on ReaderPlayer, bypassing
          // _select and its visual bookmark. Synchronize the viewport
          // without issuing another native Stop or extra speech request.
          if (!mounted || _player != player || _document != document ||
              chunks.isEmpty) return;
          // A winning external media seek supersedes pending local
          // selections that might still be waiting for native Pause.
          _sourceSelectionGate.invalidate();
          _cancelPendingVisualSave();
          final speechEnd = index >= chunks.length;
          final sourceTarget = remoteChapterTargets[index];
          final sourceOffset = sourceTarget?.sourceOffset ??
              (speechEnd ? document.text.length : chunks[index].start);
          final silentSpineIdref = sourceTarget?.silentSpineIdref;
          // A remote chapter change may advance speech while the user is
          // reading elsewhere. Do not overwrite the visual cursor unless
          // the viewport is following, or the remote seek was made paused.
          final updateViewport =
              _narrationFollow.shouldAutoFollow || !player.isPlaying;
          if (updateViewport) {
            // The media handler invokes this callback only after its
            // latest winning Seek. A paused remote chapter jump is an
            // explicit move, not continued detached browsing: reattach
            // temporary follow, but never re-enable a user-disabled option.
            // Remote movement while speech is still active and detached
            // deliberately leaves the viewport at its browsed paragraph.
            if (!player.isPlaying) {
              _narrationFollow.onCommittedNavigation();
            }
            _visiblePositionIndex = index;
            if (widget.book.format == BookFormat.epub) {
              _visualCheckpoint.clear();
              _selectedVisualSpineIdref = silentSpineIdref;
              _currentEpubVisualSourceOffset = sourceOffset;
              final block = silentSpineIdref == null
                  ? visualLayout.blockForSourceOffset(sourceOffset)
                  : visualLayout.blockForSpine(
                      silentSpineIdref, sourceOffset);
              _visualCheckpoint.hold(sourceOffset,
                  awaitTarget: true, targetBlockIndex: block);
              _lastVisibleEpubBlockIndex = block;
              _lastFollowedIndex = block;
              if (_itemScrollController.isAttached) {
                _itemScrollController.jumpTo(
                    index: block, alignment: 0.12);
              }
            } else if (_itemScrollController.isAttached) {
              _itemScrollController.jumpTo(
                  index: index.clamp(0, chunks.length - 1).toInt(),
                  alignment: 0.12);
            }
          }
          _visualProgressTick.value++;
          setState(() {});
          if (!player.isPlaying) {
            // Persist a paused lock-screen jump just like an in-reader
            // chapter selection; never race an active speech checkpoint.
            unawaited(widget.store.savePosition(
              widget.book.id, sourceOffset,
              anchor: silentSpineIdref == null
                  ? document.anchorAt(widget.book.format, sourceOffset)
                  : ReadingAnchor(kind: AnchorKind.epubSpine,
                      sourceId: silentSpineIdref, localOffset: 0),
            ).catchError((Object _, StackTrace __) {
              // Visual navigation must not turn a storage error into
              // another unsolicited audio or cloud operation.
            }));
          }
        },
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
        _initialSearchJumpConsumed = true;
        if (searchPdfPage != null) _displayPdfPage = searchPdfPage;
        _selectedSourceSearchHit = verifiedSearchOffset != null &&
                widget.book.format == BookFormat.epub
            ? BookSourceMatch(
                verifiedSearchOffset,
                verifiedSearchOffset + requestedSearchJump!.expectedText.length,
                requestedSearchJump.expectedText,
              )
            : null;
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
      if (requestedSearchJump != null && verifiedSearchOffset == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _loadEpoch) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The indexed passage has changed. '
                'Opened at your saved reading position instead.'),
          ));
        });
      }
      if (preflight != null) {
        // Frame-end time is local wall clock from opening attempt, not
        // a frame-duration/FPS estimate or peak memory measurement.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _loadEpoch) return;
          setState(() => _epubFirstFrameUs = stopwatch.elapsedMicroseconds);
        });
      }
      if (verifiedSearchOffset == null &&
          (epubRecovery?.needsReview == true || recoveryWriteFailed)) {
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

  Future<void> _openPdfVisualBookmarks() async {
    if (!mounted || widget.book.format != BookFormat.pdf ||
        _pdfTextMode || _pdfPageCount == null) return;
    final selected = await showPdfVisualBookmarks(
      context: context,
      store: widget.store,
      bookId: widget.book.id,
      currentPage: _displayPdfPage,
      pageCount: _pdfPageCount!,
    );
    if (!mounted || _pdfTextMode || selected == null) return;
    await _goToPdfPage(selected);
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

  // Item-position listeners can run inside Flutter's layout phase. Never
  // rebuild the reader or notify the progress bar synchronously from there.
  void _scheduleReaderVisualRefresh() {
    if (_followUiRefreshQueued) return;
    _followUiRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followUiRefreshQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _scheduleReaderProgressRefresh() {
    if (_visualProgressRefreshQueued) return;
    _visualProgressRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visualProgressRefreshQueued = false;
      if (mounted) _visualProgressTick.value++;
    });
  }

  /// A deliberate viewport gesture detaches active speech-follow, without
  /// pausing or seeking the player and without writing a checkpoint.
  void _onUserReaderScroll() {
    _viewportSaveGate.resumeFromUserScroll();
    if (_narrationFollow.onUserScroll(
        narrationPlaying: _player?.isPlaying ?? false)) {
      _lastFollowedIndex = -1;
      // Coalesce successive gesture notifications into one safe UI frame.
      _scheduleReaderVisualRefresh();
    }
    if (_player?.isPlaying == true && !_narrationFollow.shouldAutoFollow) {
      // A verified user gesture supersedes a pending EPUB restore target.
      // Otherwise its five-second grace window can hide the new visible
      // paragraph from the cursor even though the list really moved.
      _visualCheckpoint.clear();
    }
  }

  /// Reattach visually to the current utterance. The viewport write gate
  /// avoids treating this programmatic scroll as a new reading checkpoint.
  void _returnToNarration() {
    if (!_narrationFollow.resume()) return;
    final player = _player;
    _cancelPendingVisualSave();
    _viewportSaveGate.suspendForLayoutChange();
    if (player != null && player.segments.isNotEmpty) {
      final index = player.currentIndex
          .clamp(0, player.segments.length - 1).toInt();
      final target = widget.book.format == BookFormat.epub
          ? _epubLayout.blockForSegment(index) : index;
      _lastFollowedIndex = target;
      // The button reconnects the *view* to the speech cursor. It does
      // not request a media seek or save a new source checkpoint.
      _visiblePositionIndex = index;
      if (widget.book.format == BookFormat.epub) {
        _currentEpubVisualSourceOffset = player.segments[index].start;
        _selectedVisualSpineIdref = null;
        _lastVisibleEpubBlockIndex = target;
        _visualCheckpoint.clear();
      }
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: target, alignment: 0.12);
      }
      _visualProgressTick.value++;
    }
    if (mounted) setState(() {});
  }

  void _onVisiblePositions() {
    if (!mounted || _loading || _player == null || _document == null ||
        (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
    final player = _player!;
    // A pending native Stop/checkpoint makes isPlaying=false while a
    // Seek may still auto-resume. Never treat its transient viewport
    // notifications as a manual bookmark or override crash recovery.
    if (!readerMayObserveViewport(
          settledIdle: player.isSettledIdle,
          narrationPlaying: player.isPlaying,
          shouldAutoFollow: _narrationFollow.shouldAutoFollow,
        ) || player.segments.isEmpty ||
        !_viewportSaveGate.allowsViewportSave) return;
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
      _selectedVisualSpineIdref =
          _epubLayout.silentSpineIdrefForBlock(firstItem);
      _lastVisibleEpubBlockIndex = firstItem;
      _currentEpubVisualSourceOffset = sourceOffset;
    } else {
      index = firstItem.clamp(0, player.segments.length - 1).toInt();
      sourceOffset = player.segments[index].start;
      if (index == _visiblePositionIndex) return;
    }
    _visiblePositionIndex = index;
    // Independent visual progress can advance while the narrator speaks.
    // Frame scheduling avoids build-phase writes from position callbacks.
    _scheduleReaderProgressRefresh();
    if (_currentChapterIndex != previousChapter ||
        _currentDirectoryIndex != previousDirectory) {
      _scheduleReaderVisualRefresh();
    }
    _cancelPendingVisualSave();
    // Display progress, TOC and bookmark suggestions are independent of
    // the TTS cursor. Browsing while audio plays is never a SQLite save;
    // a detached viewport also must not persist on a subsequent Pause.
    if (!readerMayPersistViewport(
          settledIdle: player.isSettledIdle,
          narrationPlaying: player.isPlaying,
          temporarilyDetached: _narrationFollow.suspendedByUser,
        )) return;
    final revision = _visualSaveRevision;
    final document = _document;
    _saveVisualPositionTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !readerMayPersistViewport(
            settledIdle: player.isSettledIdle,
            narrationPlaying: player.isPlaying,
            temporarilyDetached: _narrationFollow.suspendedByUser,
          ) || _player != player ||
          _visualSaveRevision != revision || _document != document ||
          (widget.book.format == BookFormat.epub &&
              _currentEpubVisualSourceOffset != sourceOffset) ||
          (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
      final emptySpine = widget.book.format == BookFormat.epub
          ? _epubLayout.silentSpineIdrefForBlock(firstItem) : null;
      widget.store.savePosition(
        widget.book.id, sourceOffset,
        anchor: emptySpine == null
            ? document?.anchorAt(widget.book.format, sourceOffset)
            : ReadingAnchor(kind: AnchorKind.epubSpine,
                sourceId: emptySpine, localOffset: 0),
      );
    });
  }

  void _onPlaybackChanged() {
    if (!mounted) return;
    _readingActivityTracker?.refresh();
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
      if (_narrationFollow.shouldAutoFollow) {
        // Only a connected viewport follows speech. Otherwise the player
        // owns its audio cursor and must NOT rewrite the text location.
        _visualCheckpoint.clear();
        _selectedVisualSpineIdref = null;
        _visiblePositionIndex = player.currentIndex
            .clamp(0, player.segments.length - 1).toInt();
        if (widget.book.format == BookFormat.epub) {
          _currentEpubVisualSourceOffset =
              player.segments[_visiblePositionIndex!].start;
        }
      }
    }
    // An EPUB exact visual jump may seek the native audio cursor while
    // paused. Never schedule a TTS auto-follow scroll back to its coarse
    // segment after that jump; follow speech only while actually playing.
    if (player != null && player.segments.isNotEmpty && _narrationFollow.shouldAutoFollow &&
        (widget.book.format != BookFormat.epub || player.isPlaying)) {
      final segmentIndex = player.currentIndex
          .clamp(0, player.segments.length - 1).toInt();
      final target = widget.book.format == BookFormat.epub
          ? _epubLayout.blockForSegment(segmentIndex)
          : segmentIndex;
      if (target != _lastFollowedIndex) {
        _lastFollowedIndex = target;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _player != player || !_narrationFollow.shouldAutoFollow ||
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
    final useVisual = readerUsesVisualCursor(
      narrationPlaying: player.isPlaying,
      shouldAutoFollow: _narrationFollow.shouldAutoFollow,
    );
    final selected = useVisual
        ? (_visiblePositionIndex ?? player.currentIndex)
        : player.currentIndex;
    final cursor = selected.clamp(0, player.segments.length - 1).toInt();
    return widget.book.format == BookFormat.epub
        ? epubSourceOffsetForLinkReturn(
            speechOffset: player.segments[cursor].start,
            narrationActive: !useVisual,
            visualOffset: _currentEpubVisualSourceOffset,
          )
        : player.segments[cursor].start;
  }

  int get _currentChapterIndex {
    final player = _player;
    if (player == null || player.segments.isEmpty || _chapters.isEmpty) {
      return -1;
    }
    if (readerUsesVisualCursor(
            narrationPlaying: player.isPlaying,
            shouldAutoFollow: _narrationFollow.shouldAutoFollow,
          ) && _selectedVisualSpineIdref != null) {
      final chosen = _chapters.indexWhere(
          (chapter) => chapter.idref == _selectedVisualSpineIdref);
      if (chosen >= 0) return chosen;
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

  void _jumpDirectoryRelative(int direction) {
    if (!mounted || _loading || _error != null ||
        widget.book.format != BookFormat.epub ||
        _player == null || _player!.segments.isEmpty) return;
    final count = _authorToc.isNotEmpty
        ? _authorToc.length : _chapters.length;
    if (count == 0 || direction == 0) return;
    final next = adjacentReaderSectionIndex(
      current: _currentDirectoryIndex,
      count: count,
      forward: direction > 0,
    );
    if (next == null) return;
    _jumpDirectoryIndex(next);
  }

  void _jumpDirectoryBoundary({required bool last}) {
    if (!mounted || _loading || _error != null ||
        widget.book.format != BookFormat.epub ||
        _player == null || _player!.segments.isEmpty) return;
    final count = _authorToc.isNotEmpty
        ? _authorToc.length : _chapters.length;
    final target = boundaryReaderSectionIndex(count: count, last: last);
    if (target != null) _jumpDirectoryIndex(target);
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
      final selection = _sourceSelectionGate.reserve();
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      final chapter = _chapters[chapterIndex];
      await _select(chapter.segmentIndex,
          visualSourceOffset: chapter.start,
          visualSpineIdref: chapter.hasSpeech ? null : chapter.idref,
          reservedSelection: selection);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot change chapter: $error')),
      );
    }
  }

  Future<void> _openChapterDirectory() async {
    if (!mounted || (_chapters.isEmpty && _authorToc.isEmpty)) return;
    final player = _player;
    final document = _document;
    final loadEpoch = _loadEpoch;
    final bookId = widget.book.id;
    final authorial = _authorToc.isNotEmpty;
    final entries = _authorToc;
    final chosen = await showReaderChapterDirectory(
      context,
      authorToc: entries,
      chapters: _chapters,
      activeTocIndex: _currentDirectoryIndex,
      activeChapterIndex: _currentChapterIndex,
    );
    // Searching and highlighting are visual-only. If the book was
    // replaced/reloaded while the sheet was open, a stale original index
    // must not be applied to a different spine or publisher directory.
    if (!mounted || chosen == null || _loading ||
        widget.book.id != bookId || _loadEpoch != loadEpoch ||
        _player != player || _document != document) return;
    if (authorial) {
      if (chosen >= 0 && chosen < entries.length) {
        _navigateToSourceOffset(entries[chosen].offset, remember: false);
      }
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
      // The result must not replace a previous highlight unless the
      // source-exact seek and its durable checkpoint both succeed.
      // A cancelled or superseded search leaves the UI untouched.
      _navigateToSourceOffset(hit.start,
          remember: false, searchMatch: hit);
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
    final useVisual = readerUsesVisualCursor(
      narrationPlaying: player.isPlaying,
      shouldAutoFollow: _narrationFollow.shouldAutoFollow,
    );
    final index = (useVisual
            ? (_visiblePositionIndex ?? player.currentIndex)
            : player.currentIndex)
        .clamp(0, player.segments.length - 1).toInt();
    final segment = player.segments[index];
    // While browsing during narration, a bookmark targets the actual
    // viewport, not the speech chunk heard in the background.
    final sourceOffset = widget.book.format == BookFormat.epub
        ? epubSourceOffsetForLinkReturn(
            speechOffset: segment.start,
            narrationActive: !useVisual,
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
    final destination = widget.book.format == BookFormat.epub
        ? speechSourceDestinationIndexForOffset(player.segments, offset)
        : speechSegmentIndexForOffset(player.segments, offset);
    if (destination < 0) return;
    if (widget.book.format == BookFormat.epub) {
      if (offset < 0 || offset > document.text.length) return;
      final selection = _sourceSelectionGate.reserve();
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      await _select(destination, visualSourceOffset: offset,
          reservedSelection: selection);
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
        // Explicit Play supersedes an older source seek still awaiting a
        // native Stop/Pause. Never auto-play from a now-obsolete transport
        // continuation after a newer chapter/bookmark selection.
        final playRevision = _sourceSelectionGate.reserve();
        _cancelPendingVisualSave();
        if (readerMaySeekToViewportOnPlay(
            temporarilyDetached: _narrationFollow.suspendedByUser)) {
          // Outside detached browsing, an intentional manual reading
          // position remains the source for starting new narration.
          final visible = _visiblePositionIndex;
          if (widget.book.format == BookFormat.epub &&
              visible == player.segments.length &&
              player.currentIndex != player.segments.length) {
            // A visual-only EPUB end has no speech. Confirm native Stop
            // before the user's explicit restart from this location.
            await player.seekToSourceEnd();
          } else if (visible != null && visible != player.currentIndex &&
              (player.currentIndex < player.segments.length ||
                  visible < player.segments.length - 1)) {
            await player.seekTo(visible);
          }
        }
        // Detached browsing is different: Play resumes the existing audio
        // cursor and leaves the text viewport at its independent location.
        if (!mounted || _player != player ||
            !_sourceSelectionGate.isCurrent(playRevision)) return;
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
    final document = _document;
    if (!mounted || player == null || player.segments.isEmpty ||
        document == null) return;
    final target = player.sourceStepDestination(delta);
    // Next on a completed book is idempotent. The final narrated chunk
    // must not be replayed by clamping a Next to the last *audio* index.
    if (target == player.segments.length && player.isSettledIdle &&
        player.currentIndex == target) return;
    try {
      if (target == player.segments.length) {
        final eof = widget.book.format == BookFormat.epub
            ? epubSpeechEndTarget(
                _chapters, player.segments.length, document.text.length)
            : EpubMediaChapterTarget(sourceOffset: document.text.length);
        await _select(target, visualSourceOffset: eof.sourceOffset,
            visualSpineIdref: eof.silentSpineIdref);
      } else {
        // _select owns the native Stop barrier, latest-selection guard,
        // source-exact SQLite write and visual scroll checkpoint.
        await _select(target);
      }
    } catch (error) {
      if (!mounted || _player != player) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot move to this passage: $error')),
      );
    }
  }

  /// Internal EPUB links and notes are in-book source offsets only, never
  /// arbitrary URLs. A return position is recorded after a successful seek.
  void _navigateToSourceOffset(int sourceOffset, {
    required bool remember,
    BookSourceMatch? searchMatch,
    String? visualSpineIdref,
    VoidCallback? onCommitted,
  }) {
    Future<void> navigate() async {
      final player = _player;
      final document = _document;
      if (widget.book.format != BookFormat.epub || player == null ||
          document == null || player.segments.isEmpty ||
          sourceOffset < 0 || sourceOffset > document.text.length) return;
      final narrationActive = !readerUsesVisualCursor(
        narrationPlaying: player.isPlaying,
        shouldAutoFollow: _narrationFollow.shouldAutoFollow,
      );
      final sourceIndex = (narrationActive ? player.currentIndex
              : (_visiblePositionIndex ?? player.currentIndex))
          .clamp(0, player.segments.length - 1).toInt();
      final fromOffset = epubSourceOffsetForLinkReturn(
        speechOffset: player.segments[sourceIndex].start,
        narrationActive: narrationActive,
        visualOffset: _currentEpubVisualSourceOffset,
      );
      // Equal text offsets do not identify visual-only EPUB sections.
      // Capture the origin before the asynchronous Stop/seek clears it.
      final fromSpineIdref = narrationActive
          ? null : _selectedVisualSpineIdref;
      final index = speechSourceDestinationIndexForOffset(
          player.segments, sourceOffset);
      final selection = _sourceSelectionGate.reserve();
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      // _select persists the exact source offset once. A second write of
      // the same position after seeking is unnecessary and can race with
      // user scrolls or turn a failed checkpoint into a partial jump.
      var committed = false;
      await _select(index, visualSourceOffset: sourceOffset,
          visualSpineIdref: visualSpineIdref,
          committedSearchMatch: searchMatch,
          reservedSelection: selection,
          onCommitted: () {
            committed = true;
            onCommitted?.call();
          });
      // A superseded seek returns without throwing. Do not add a broken
      // "return from note" entry when that source jump never committed.
      if (!mounted || _player != player || !committed ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      if (remember) {
        _linkHistory.push(fromOffset, sourceOffset,
            fromSpineIdref: fromSpineIdref,
            toSpineIdref: visualSpineIdref);
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
      final origin = _linkHistory.lastLocation;
      final player = _player;
      final document = _document;
      if (origin == null || player == null || player.segments.isEmpty ||
          document == null || origin.sourceOffset < 0 ||
          origin.sourceOffset > document.text.length) return;
      final index = speechSourceDestinationIndexForOffset(
          player.segments, origin.sourceOffset);
      final selection = _sourceSelectionGate.reserve();
      _saveVisualPositionTimer?.cancel();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      var committed = false;
      await _select(index,
          visualSourceOffset: origin.sourceOffset,
          visualSpineIdref: origin.spineIdref,
          reservedSelection: selection,
          onCommitted: () => committed = true);
      // A newer seek or failed durable checkpoint cannot consume history.
      if (!mounted || _player != player || !committed ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      if (_linkHistory.commitReturnIfTop(origin)) setState(() {});
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
      if (player == null) return;
      final selection = _sourceSelectionGate.reserve();
      // EPUB is an explicit reading-location selection, not permission
      // to re-synthesize a new paragraph while narration is active.
      // Also cancel any pending seek/voice auto-resume before seeking.
      if (widget.book.format == BookFormat.epub &&
          !player.isSettledIdle) {
        await player.pause();
      }
      if (!mounted || _player != player ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      await _select(index, reservedSelection: selection);
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
    String? visualSpineIdref,
    BookSourceMatch? committedSearchMatch,
    int? reservedSelection,
    VoidCallback? onCommitted,
  }) async {
    final player = _player;
    // Explicit source EOF also exists for TXT and PDF. Ordinary segment
    // selection still refuses out-of-range positions.
    final visualOnlyEnd = visualSourceOffset != null &&
        index == player?.segments.length;
    if (player == null || index < 0 ||
        (index >= player.segments.length && !visualOnlyEnd)) return;
    // Reserve before native Pause in callers with an asynchronous barrier.
    // A newer selection or remote media seek must defeat an older
    // continuation BEFORE it can issue a Seek or mutate a checkpoint.
    final selection = reservedSelection ?? _sourceSelectionGate.reserve();
    if (!_sourceSelectionGate.isCurrent(selection)) return;
    // Preserve the current highlight until the seek actually commits.
    _cancelPendingVisualSave();
    if (visualOnlyEnd) {
      await player.seekToSourceEnd();
    } else {
      await player.seekTo(index);
    }
    if (!mounted || _player != player ||
        !_sourceSelectionGate.isCurrent(selection) ||
        player.currentIndex != index ||
        player.intendedNavigationIndex != index) return;
    // A verified EPUB link may point inside the current audio segment
    // or into a paragraph without any speech. Save that exact source
    // position, rather than saving a coarse TTS start and then rewriting.
    final sourceOffset = visualOnlyEnd
        ? visualSourceOffset!
        : widget.book.format == BookFormat.epub &&
                visualSourceOffset != null
            ? visualSourceOffset : player.segments[index].start;
    final explicitSilentAnchor = widget.book.format == BookFormat.epub &&
        visualSpineIdref != null
        ? ReadingAnchor(kind: AnchorKind.epubSpine,
            sourceId: visualSpineIdref, localOffset: 0)
        : null;
    await widget.store.savePosition(
      widget.book.id, sourceOffset,
      anchor: explicitSilentAnchor ??
          _document?.anchorAt(widget.book.format, sourceOffset),
    );
    // Even the SQLite Future can yield to a newer user navigation.
    // The old selection has already committed its write, but must not
    // repaint or scroll over the new intent when its Future resolves.
    if (!mounted || _player != player ||
        !_sourceSelectionGate.isCurrent(selection) ||
        player.currentIndex != index ||
        player.intendedNavigationIndex != index) return;
    // An explicit, durable source selection supersedes merely browsing
    // elsewhere. Reattach temporary follow only at this winning commit.
    // The user's explicit Follow narration OFF setting remains unchanged.
    _narrationFollow.onCommittedNavigation();
    _selectedSourceSearchHit = committedSearchMatch;
    _selectedVisualSpineIdref = visualSpineIdref;
    _visiblePositionIndex = player.segments.isEmpty ? null
        : index.clamp(0, player.segments.length - 1).toInt();
    _currentEpubVisualSourceOffset = widget.book.format == BookFormat.epub
        ? sourceOffset : null;
    // Protect all explicit EPUB seeks from a transient stale viewport,
    // not only jumps with an additional user-specified source offset.
    final visualIndex = widget.book.format == BookFormat.epub
        ? (visualSpineIdref == null
            ? _epubLayout.blockForSourceOffset(sourceOffset)
            : _epubLayout.blockForSpine(visualSpineIdref, sourceOffset))
        : index.clamp(0, player.segments.length - 1).toInt();
    _visualCheckpoint.hold(widget.book.format == BookFormat.epub
        ? sourceOffset : null,
        awaitTarget: widget.book.format == BookFormat.epub,
        targetBlockIndex: widget.book.format == BookFormat.epub
            ? visualIndex : null);
    _lastVisibleEpubBlockIndex = widget.book.format == BookFormat.epub
        ? visualIndex : null;
    if (_itemScrollController.isAttached) {
      _lastFollowedIndex = visualIndex;
      _itemScrollController.jumpTo(index: visualIndex, alignment: 0.12);
    }
    if (mounted && _player == player) {
      // Also refresh TXT/PDF, since temporary follow and the status chip
      // can change after an explicit seek on any readable text format.
      // The source-exact EPUB highlight and TOC must refresh immediately.
      setState(() {});
      _visualProgressTick.value++;
    }
    // Called only after a winning source seek, durable checkpoint, and
    // visual selection. A canceled/superseded seek has no return history.
    onCommitted?.call();
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
    _readingActivityTracker?.refresh();
    _readerForeground = state == AppLifecycleState.resumed;
    if (!_readerForeground) _lastReadingInteraction = null;
    _readingActivityTracker?.refresh();
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
    _readingActivityTracker?.dispose();
    _readingActivityTracker = null;
    _stopFrameCapture(discard: true, notify: false);
    ++_loadEpoch;
    _activeEpubTask?.cancel();
    _activeEpubTask = null;
    WidgetsBinding.instance.removeObserver(this);
    _saveVisualPositionTimer?.cancel();
    _flushPdfPagePosition();
    // pdfrx 2.4.8 PdfViewerController has no dispose() API; the PdfViewer
    // widget releases its native renderer when unmounted. Do not call an
    // unavailable controller method during book/screen shutdown.
    _itemPositionsListener.itemPositions.removeListener(_onVisiblePositions);
    _visualProgressTick.dispose();
    _advancedControlsScroll.dispose();
    final player = _player;
    if (player != null) {
      widget.mediaHandler?.detach(player);
      player.removeListener(_onPlaybackChanged);
      _recoveryBinding?.dispose();
      player.dispose();
    }
    super.dispose();
  }

  void _changeVisualReaderLayout(VoidCallback change) {
    // Changing the height of controls or text layout may expose a different
    // first paragraph. It is NOT a user navigation intent and must not
    // replace a prior exact EPUB bookmark or TXT segment checkpoint.
    _cancelPendingVisualSave();
    _viewportSaveGate.suspendForLayoutChange();
    setState(change);
  }

  void _setReaderFocusMode(bool enabled) {
    if (_readerFocusMode == enabled) return;
    _changeVisualReaderLayout(() {
      _readerFocusMode = enabled;
      // A hidden panel must not reappear expanded on restore.
      if (enabled) _advancedControlsExpanded = false;
    });
  }

  void _adjustReaderTextSize(int delta) {
    if (_loading || _error != null ||
        (widget.book.format == BookFormat.pdf && !_pdfTextMode)) {
      return;
    }
    final next = steppedReaderFontSize(_fontSize, delta);
    if (next == _fontSize) return; // no redundant SQLite save at bounds
    _setReadingPreferences(_readingPrefs.copyWith(fontSize: next));
  }

  void _setReadingPreferences(ReadingPreferences preferences) {
    preferences.validate();
    // Synchronous SQLite write first: failed persistence must not leave the
    // live visual state claiming settings that cannot survive a restart.
    widget.store.saveReadingPreferences(
        preferences, bookId: widget.book.id);
    if (mounted) _changeVisualReaderLayout(() => _readingPrefs = preferences);
  }

  Future<void> _openReadingAppearance() async {
    var draft = _readingPrefs;
    final result = await showDialog<
        ({ReadingPreferences preferences, String action})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, redraw) {
          void change(ReadingPreferences preferences) =>
              redraw(() => draft = preferences);
          return AlertDialog(
            title: const Text('Reading appearance'),
            content: SizedBox(
              width: (MediaQuery.sizeOf(dialogContext).width - 96)
                  .clamp(200.0, 420.0).toDouble(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Text size: ${draft.fontSize.round()}'),
                    Slider(
                      value: draft.fontSize,
                      min: 14,
                      max: 32,
                      divisions: 18,
                      label: '${draft.fontSize.round()}',
                      onChanged: (value) =>
                          change(draft.copyWith(fontSize: value)),
                    ),
                    Text('Line spacing: ${draft.lineHeight.toStringAsFixed(2)}'),
                    Slider(
                      value: draft.lineHeight,
                      min: 1.2,
                      max: 2.4,
                      divisions: 24,
                      label: draft.lineHeight.toStringAsFixed(2),
                      onChanged: (value) =>
                          change(draft.copyWith(lineHeight: value)),
                    ),
                    Text('Letter spacing: ${draft.letterSpacing.toStringAsFixed(2)} px'),
                    Slider(
                      key: const ValueKey('reading-letter-spacing'),
                      value: draft.letterSpacing,
                      min: 0,
                      max: 3,
                      divisions: 12,
                      label: '${draft.letterSpacing.toStringAsFixed(2)} px',
                      onChanged: (value) =>
                          change(draft.copyWith(letterSpacing: value)),
                    ),
                    Text('Word spacing: ${draft.wordSpacing.toStringAsFixed(1)} px'),
                    Slider(
                      key: const ValueKey('reading-word-spacing'),
                      value: draft.wordSpacing,
                      min: 0,
                      max: 8,
                      divisions: 16,
                      label: '${draft.wordSpacing.toStringAsFixed(1)} px',
                      onChanged: (value) =>
                          change(draft.copyWith(wordSpacing: value)),
                    ),
                    Text('Paragraph gaps: ${draft.paragraphSpacingFactor.toStringAsFixed(1)}×'),
                    Slider(
                      key: const ValueKey('reading-paragraph-spacing'),
                      value: draft.paragraphSpacingFactor,
                      min: 0.5,
                      max: 2.5,
                      divisions: 20,
                      label: '${draft.paragraphSpacingFactor.toStringAsFixed(1)}×',
                      onChanged: (value) => change(
                          draft.copyWith(paragraphSpacingFactor: value)),
                    ),
                    Text('Reading column: ${draft.contentWidth.round()} px'),
                    Slider(
                      key: const ValueKey('reading-column-width'),
                      value: draft.contentWidth,
                      min: 480,
                      max: 1000,
                      divisions: 13,
                      label: '${draft.contentWidth.round()} px',
                      onChanged: (value) =>
                          change(draft.copyWith(contentWidth: value)),
                    ),
                    const Text('Paragraph alignment'),
                    DropdownButton<String>(
                      key: const ValueKey('reading-text-alignment'),
                      value: draft.textAlignment,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'auto',
                            child: Text('Original reader layout')),
                        DropdownMenuItem(value: 'start',
                            child: Text('Left aligned (ragged right)')),
                        DropdownMenuItem(value: 'justify',
                            child: Text('Justified')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          change(draft.copyWith(textAlignment: value));
                        }
                      },
                    ),
                    const Text('Font family'),
                    DropdownButton<String>(
                      value: draft.fontFamily,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'serif',
                            child: Text('Serif (book style)')),
                        DropdownMenuItem(value: 'sans-serif',
                            child: Text('Sans serif')),
                        DropdownMenuItem(value: 'monospace',
                            child: Text('Monospace')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          change(draft.copyWith(fontFamily: value));
                        }
                      },
                    ),
                    if (widget.book.format == BookFormat.epub) ...[
                      const Text('Page colors'),
                      DropdownButton<String>(
                        value: draft.palette,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'system',
                              child: Text('Follow device theme')),
                          DropdownMenuItem(value: 'sepia',
                              child: Text('Warm paper')),
                          DropdownMenuItem(value: 'night',
                              child: Text('Night reading')),
                          DropdownMenuItem(value: 'highContrast',
                              child: Text('High contrast (white/black)')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            change(draft.copyWith(palette: value));
                          }
                        },
                      ),
                    ],
                    const Text(
                      'Appearance affects only display, not audio, '
                      'bookmarks, cloud usage or saved reading position.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext,
                    (preferences: draft, action: 'reset')),
                child: const Text('Use global defaults'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext,
                    (preferences: draft, action: 'global')),
                child: const Text('Set global default'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext,
                    (preferences: draft, action: 'book')),
                child: const Text('Save for book'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    if (result.action == 'reset') {
      widget.store.clearBookReadingPreferences(widget.book.id);
      _changeVisualReaderLayout(() => _readingPrefs =
          widget.store.getReadingPreferences(bookId: widget.book.id));
    } else if (result.action == 'global') {
      // Global should affect this open book too; other books with
      // explicit overrides retain their own reading appearance.
      widget.store.saveReadingPreferences(result.preferences);
      widget.store.clearBookReadingPreferences(widget.book.id);
      _changeVisualReaderLayout(() => _readingPrefs = result.preferences);
    } else {
      _setReadingPreferences(result.preferences);
    }
  }

  /// Book actions are grouped by intent, not displayed as an overflowing
  /// row of 10+ icon-only controls. Every operation is invoked only after
  /// this accessible, scrollable sheet has closed.
  /// A percentage is a canonical source coordinate. The dialog never
  /// starts narration, and a stale result from a replaced book is ignored.
  ReaderSectionRange? _currentSectionRange() {
    final document = _document;
    if (widget.book.format != BookFormat.epub ||
        document == null || document.text.isEmpty ||
        _player == null || _player!.segments.isEmpty) return null;
    return readerSectionRangeForIndex(
      authorToc: _authorToc,
      chapters: _chapters,
      currentIndex: _currentDirectoryIndex,
      sourceLength: document.text.length,
    );
  }

  Future<void> _openGoToProgress({
    bool autofocus = false,
    bool withinSection = false,
  }) async {
    final player = _player;
    final document = _document;
    final bookId = widget.book.id;
    final loadEpoch = _loadEpoch;
    if (!mounted || _loading || _error != null ||
        player == null || player.segments.isEmpty ||
        document == null || document.text.isEmpty ||
        (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
    final sectionIndex = withinSection ? _currentDirectoryIndex : -1;
    final section = withinSection ? _currentSectionRange() : null;
    if (withinSection && section == null) return;
    final displayedOrigin = _visibleProgressOffset(
        player, document.text.length);
    final target = await showReaderGoToProgressDialog(
      context,
      currentSourceOffset: section == null
          ? displayedOrigin : (displayedOrigin - section.start)
              .clamp(0, section.length).toInt(),
      sourceLength: section?.length ?? document.text.length,
      autofocus: autofocus,
      title: withinSection ? 'Go to section position' : 'Go to book position',
      explanation: withinSection
          ? 'Choose a percentage within the current EPUB section. '
              'This uses original source text, not audio time.'
          : 'Choose a percentage of the original book text. '
              'This is not estimated audio time or a PDF page.',
      fieldLabel: withinSection ? 'Section position' : 'Book position',
    );
    if (!mounted || target == null || _loading || _error != null ||
        widget.book.id != bookId || _loadEpoch != loadEpoch ||
        _player != player || _document != document ||
        (widget.book.format == BookFormat.pdf && !_pdfTextMode) ||
        (withinSection && _currentDirectoryIndex != sectionIndex)) return;
    final destination = section == null ? target
        : section.start + target.clamp(0, section.length - 1).toInt();
    // Narration/media controls may advance the text while this dialog is
    // open. Record the actual point immediately before the confirmed jump.
    final origin = _visibleProgressOffset(player, document.text.length);
    // A stale illustrated viewport may remain visible while TTS speaks a
    // different chapter. Only a paused visual reader owns a spine-specific
    // origin; active narration returns by its true spoken source offset.
    final originSpineIdref = widget.book.format == BookFormat.epub &&
            readerUsesVisualCursor(
              narrationPlaying: player.isPlaying,
              shouldAutoFollow: _narrationFollow.shouldAutoFollow,
            )
        ? _selectedVisualSpineIdref : null;
    // The return point is established only AFTER the new seek and SQLite
    // checkpoint succeeded. A canceled/no-op/failed jump leaves it alone.
    _jumpToSourceProgress(destination, onCommitted: () {
      if (!mounted || _player != player || _document != document) return;
      final actualDestination = _visibleProgressOffset(
          player, document.text.length);
      if (_progressReturn.recordCommittedJump(
        fromOffset: origin,
        toOffset: actualDestination,
        sourceLength: document.text.length,
        originSpineIdref: originSpineIdref,
        destinationSpineIdref: widget.book.format == BookFormat.epub
            ? _selectedVisualSpineIdref : null,
      )) {
        setState(() {});
      }
    });
  }

  void _returnToProgressJumpOrigin() {
    final origin = _progressReturn.origin;
    final originSpineIdref = _progressReturn.originSpineIdref;
    final player = _player;
    final document = _document;
    if (!mounted || origin == null || _loading || _error != null ||
        player == null || player.segments.isEmpty ||
        document == null || document.text.isEmpty ||
        (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
    final returnRevision = _progressReturn.revision;
    _jumpToSourceProgress(origin,
        visualSpineIdref: originSpineIdref,
        onCommitted: () {
      if (!mounted || _player != player || _document != document) return;
      if (_progressReturn.consumeIfOrigin(origin,
          expectedRevision: returnRevision)) {
        setState(() {});
      }
    });
  }

  Future<void> _openReaderTools({
    bool autofocusSearch = false,
    bool navigationOnly = false,
  }) async {
    // Keep the full settings sheet available during loading (speech and
    // pronunciation settings do not require an active text player).
    // Quick navigation, on the other hand, needs a usable destination.
    if (!mounted ||
        (navigationOnly && (_loading || _error != null))) return;
    final openedBookId = widget.book.id;
    final openedPlayer = _player;
    final openedDocument = _document;
    final epub = widget.book.format == BookFormat.epub;
    final pdf = widget.book.format == BookFormat.pdf;
    final textMode = !pdf || _pdfTextMode;
    final playable = _player != null && _player!.segments.isNotEmpty;
    final availability = ReaderToolMenuAvailability(
      isEpub: epub,
      isPdf: pdf,
      textMode: textMode,
      hasPlayableSegments: playable,
      hasContents: _chapters.isNotEmpty || _authorToc.isNotEmpty,
      canReturnFromLink: _linkHistory.canReturn,
      hasPdfPageBookmarks: _pdfPageCount != null,
      hasEpubPerformance: !_loading && _epubWorkerTimings != null,
      hasEpubWarnings: _document?.epubDiagnostics.isNotEmpty ?? false,
      autoFollow: _narrationFollow.enabled,
      followSuspended: _narrationFollow.suspendedByUser,
      paletteName: _epubPalette.name,
      focusMode: _readerFocusMode,
      hasProgressReturn: _progressReturn.canReturn,
      hasSectionPosition: !_loading && _error == null &&
          _currentSectionRange() != null,
    );
    final sections = navigationOnly
        ? buildReaderQuickNavigationSections(availability)
        : buildReaderToolSections(availability);
    if (sections.isEmpty) return;
    final action = await showOrganizedActionSheet(
      context,
      title: navigationOnly ? 'Quick navigation' : 'Reader tools',
      autofocusSearch: autofocusSearch,
      sections: sections,
    );
    // Closing a sheet after replacing/reloading a book must never
    // dispatch an old action into a different document/player session.
    if (!mounted || action == null || widget.book.id != openedBookId ||
        _player != openedPlayer || _document != openedDocument) return;
    switch (action) {
      case 'contents':
        await _openChapterDirectory();
        return;
      case 'first-section':
        _jumpDirectoryBoundary(last: false);
        return;
      case 'last-section':
        _jumpDirectoryBoundary(last: true);
        return;
      case 'search':
        await _searchInBook();
        return;
      case 'go-to-percent':
        await _openGoToProgress();
        return;
      case 'section-percent':
        await _openGoToProgress(withinSection: true);
        return;
      case 'return-to-percent':
        _returnToProgressJumpOrigin();
        return;
      case 'bookmarks':
        await _openBookmarks();
        return;
      case 'pdf-bookmarks':
        await _openPdfVisualBookmarks();
        return;
      case 'return-link':
        _returnFromEpubLink();
        return;
      case 'pdf-pages':
        await _returnToPdfPages();
        return;
      case 'reading-focus':
        _setReaderFocusMode(!_readerFocusMode);
        return;
      case 'appearance':
        await _openReadingAppearance();
        return;
      case 'font-plus':
        _adjustReaderTextSize(2);
        return;
      case 'font-minus':
        _adjustReaderTextSize(-2);
        return;
      case 'return-to-narration':
        _returnToNarration();
        return;
      case 'auto-follow':
        final enabled = !_narrationFollow.enabled;
        _narrationFollow.setEnabled(enabled);
        setState(() {});
        if (enabled) {
          _lastFollowedIndex = -1;
          _onPlaybackChanged();
        }
        return;
      case 'palette-system':
      case 'palette-sepia':
      case 'palette-night':
      case 'palette-contrast':
        final palette = switch (action) {
          'palette-system' => EpubReadingPalette.system,
          'palette-sepia' => EpubReadingPalette.sepia,
          'palette-night' => EpubReadingPalette.night,
          _ => EpubReadingPalette.highContrast,
        };
        _setReadingPreferences(
            _readingPrefs.copyWith(palette: palette.name));
        return;
      case 'speech':
        await _openSpeechSettings();
        return;
      case 'cast':
        await _openCastEditor();
        return;
      case 'pronunciation':
        await _openPronunciations();
        return;
      case 'keyboard-help':
        await showReaderKeyboardHelp(context);
        return;
      case 'epub-performance':
        if (_epubWorkerTimings != null) {
          await showEpubOpeningPerformance(
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
          );
        }
        return;
      case 'epub-compat':
        final reports = _document?.epubDiagnostics;
        if (reports != null && reports.isNotEmpty) {
          await showEpubImportDiagnostics(context, reports);
        }
        return;
    }
  }

  Future<void> _returnToPdfPages() async {
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
    setState(() {
      _pdfTextMode = false;
      _readerFocusMode = false;
    });
    _onPdfPageChanged(_displayPdfPage);
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final epubSectionsAvailable = !_loading && _error == null &&
        widget.book.format == BookFormat.epub &&
        player != null && player.segments.isNotEmpty &&
        (_authorToc.isNotEmpty || _chapters.isNotEmpty);
    final progressNavigationAvailable = !_loading && _error == null &&
        _document != null && _document!.text.isNotEmpty &&
        player != null && player.segments.isNotEmpty &&
        (widget.book.format != BookFormat.pdf || _pdfTextMode);
    final compactReaderToolbar = useCompactReaderToolbar(
      width: MediaQuery.sizeOf(context).width,
      scaledBaseTextSize: MediaQuery.textScalerOf(context).scale(16),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onReadingGesture(),
      onPointerSignal: (_) => _onReadingGesture(),
      child: ReaderKeyboardShortcuts(
      enabled: !_loading && player != null &&
          player.segments.isNotEmpty &&
          (widget.book.format != BookFormat.pdf || _pdfTextMode),
      onPlayPause: () => unawaited(_playOrPause()),
      onPreviousSegment: () => unawaited(_move(-1)),
      onNextSegment: () => unawaited(_move(1)),
      onSearch: () => unawaited(_searchInBook()),
      onBookmarks: () => unawaited(_openBookmarks()),
      onGoToProgress: progressNavigationAvailable
          ? () => unawaited(_openGoToProgress(autofocus: true))
          : null,
      onReturnToProgress: progressNavigationAvailable &&
              _progressReturn.canReturn
          ? _returnToProgressJumpOrigin
          : null,
      onHelp: () => unawaited(showReaderKeyboardHelp(context)),
      onTools: _loading || _error != null ? null
          : () => unawaited(_openReaderTools(autofocusSearch: true)),
      onIncreaseTextSize: !_loading && _error == null &&
              (widget.book.format != BookFormat.pdf || _pdfTextMode)
          ? () => _adjustReaderTextSize(2) : null,
      onDecreaseTextSize: !_loading && _error == null &&
              (widget.book.format != BookFormat.pdf || _pdfTextMode)
          ? () => _adjustReaderTextSize(-2) : null,
      onPreviousSection: epubSectionsAvailable
          ? () => _jumpDirectoryRelative(-1) : null,
      onNextSection: epubSectionsAvailable
          ? () => _jumpDirectoryRelative(1) : null,
      onFirstSection: epubSectionsAvailable
          ? () => _jumpDirectoryBoundary(last: false) : null,
      onLastSection: epubSectionsAvailable
          ? () => _jumpDirectoryBoundary(last: true) : null,
      // Genuine keyboard viewport movement must detach just like touch/wheel.
      onViewportScrollKey: _onUserReaderScroll,
      onReturnToNarration: !_loading && _error == null &&
              _narrationFollow.suspendedByUser
          ? _returnToNarration : null,
      onToggleFocusMode: progressNavigationAvailable
          ? () => _setReaderFocusMode(!_readerFocusMode) : null,
      child: Scaffold(
      floatingActionButton: !_loading && _error == null && player != null &&
              player.segments.isNotEmpty &&
              (widget.book.format != BookFormat.pdf || _pdfTextMode) &&
              (_readerFocusMode || _narrationFollow.suspendedByUser)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_narrationFollow.suspendedByUser)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReaderNarrationStatusIndicator(
                        currentIndex: player.currentIndex,
                        segmentCount: player.segments.length,
                        isPlaying: player.isPlaying,
                      ),
                      const SizedBox(width: 8),
                      ReaderReturnToNarrationButton(
                        onReturn: _returnToNarration,
                      ),
                    ],
                  ),
                if (_narrationFollow.suspendedByUser && _readerFocusMode)
                  const SizedBox(height: 8),
                if (_readerFocusMode)
                  ReaderFocusRestoreButton(
                    onRestore: () => _setReaderFocusMode(false),
                  ),
              ],
            )
          : null,
      appBar: AppBar(
        title: Text(widget.book.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        // Focus mode intentionally hides the full player and its progress
        // slider. Keep a small, screen-reader-accessible visual position in
        // the existing header, without overlapping the reading surface.
        // ValueListenableBuilder tracks viewport movement even when TTS
        // continues at another source offset in the background.
        bottom: _readerFocusMode && progressNavigationAvailable
            ? PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: ValueListenableBuilder<int>(
                  valueListenable: _visualProgressTick,
                  builder: (context, revision, child) =>
                      ReaderFocusProgressStrip(
                    sourceOffset: _visibleProgressOffset(
                        player!, _document!.text.length),
                    sourceLength: _document!.text.length,
                    onNavigate: () => unawaited(_openGoToProgress()),
                  ),
                ),
              )
            : null,
        actions: [
          // Compact layouts have one dedicated navigation entry instead
          // of hiding search/contents/return deep inside all preferences.
          // It routes through the existing action handler, never a second
          // path to native Seek or book-position persistence.
          if (compactReaderToolbar && !_loading && _error == null &&
              ((player?.segments.isNotEmpty ?? false) ||
               (widget.book.format == BookFormat.epub &&
                   (_chapters.isNotEmpty || _authorToc.isNotEmpty)) ||
               (widget.book.format == BookFormat.pdf &&
                   _pdfPageCount != null && !_pdfTextMode)))
            IconButton(
              key: const ValueKey('reader-quick-navigation'),
              icon: const Icon(Icons.explore_outlined),
              tooltip: 'Quick navigation for this book',
              onPressed: () => unawaited(
                  _openReaderTools(navigationOnly: true)),
            ),
          if (!compactReaderToolbar &&
              widget.book.format == BookFormat.epub &&
              _linkHistory.canReturn)
            IconButton(
              key: const ValueKey('reader-return-link'),
              tooltip: 'Return from note or internal link',
              icon: const Icon(Icons.keyboard_return),
              onPressed: _returnFromEpubLink,
            ),
          if (!compactReaderToolbar &&
              widget.book.format == BookFormat.epub &&
              (_chapters.isNotEmpty || _authorToc.isNotEmpty))
            IconButton(
              key: const ValueKey('reader-contents-action'),
              tooltip: _authorToc.isNotEmpty
                  ? 'Book table of contents' : 'EPUB spine sections',
              icon: const Icon(Icons.view_list),
              onPressed: _openChapterDirectory,
            ),
          if (!compactReaderToolbar &&
              _player != null && _player!.segments.isNotEmpty)
            IconButton(
              key: const ValueKey('reader-search-action'),
              icon: const Icon(Icons.search),
              tooltip: 'Search this book (Ctrl/Cmd+F)',
              onPressed: _searchInBook,
            ),
          IconButton(
            key: const ValueKey('reader-tools-menu'),
            icon: const Icon(Icons.more_vert),
            tooltip: 'Reader tools & settings (Ctrl+K)',
            onPressed: _openReaderTools,
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
                                  child: Listener(
                                    onPointerSignal: (event) {
                                      if (isReaderDirectVerticalScroll(event)) {
                                        _onUserReaderScroll();
                                      }
                                    },
                                    // Desktop touchpads commonly emit pan/zoom
                                    // events instead of wheel events. Pinch
                                    // zoom without vertical pan stays ignored.
                                    onPointerPanZoomUpdate: (event) {
                                      if (isReaderDirectVerticalScroll(event)) {
                                        _onUserReaderScroll();
                                      }
                                    },
                                    child: NotificationListener<ScrollNotification>(
                                    onNotification: (notification) {
                                      if (isReaderUserVerticalViewportScroll(
                                          notification)) {
                                        _onUserReaderScroll();
                                      }
                                      return false;
                                    },
                                    child: ScrollablePositionedList.builder(
                                  // A new EPUB extraction/casting pass changes
                                  // the block index. Remount to honor the
                                  // restored anchor after the user edits voices.
                                  key: widget.book.format == BookFormat.epub
                                      ? ObjectKey(_epubLayout) : null,
                                  padding: readerViewportPadding(
                                    width: MediaQuery.sizeOf(context).width,
                                    focusMode: _readerFocusMode,
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
                                          : _selectedVisualSpineIdref == null
                                              ? _epubLayout.blockForSourceOffset(
                                                  _visualCheckpoint.offset!)
                                              : _epubLayout.blockForSpine(
                                                  _selectedVisualSpineIdref!,
                                                  _visualCheckpoint.offset!))
                                      : player.currentIndex.clamp(
                                          0, player.segments.length - 1).toInt(),
                                  itemBuilder: (context, index) {
                                    if (widget.book.format == BookFormat.epub) {
                                      final block = _epubLayout.blocks[index];
                                      return EpubParagraphTile(
                                        // Multiple illustrated OPF sections may
                                        // share the exact same source offset.
                                        // List-child keys must be unique or
                                        // Flutter can reuse another cover's
                                        // image/gesture widget state.
                                        key: ValueKey((block.start, index)),
                                        block: block,
                                        activeSegmentIndex: player.currentIndex,
                                        searchMatch: _selectedSourceSearchHit,
                                        fontSize: _fontSize,
                                        fontFamily: _readingPrefs.fontFamily,
                                        lineHeight: _readingPrefs.lineHeight,
                                        contentWidth: _readingPrefs.contentWidth,
                                        textAlignment: _readingPrefs.textAlignment,
                                        paragraphSpacingFactor:
                                            _readingPrefs.paragraphSpacingFactor,
                                        letterSpacing: _readingPrefs.letterSpacing,
                                        wordSpacing: _readingPrefs.wordSpacing,
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
                                    return Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: _readingPrefs.contentWidth,
                                        ),
                                        child: InkWell(
                                          onTap: () => _selectFromVisualTap(index),
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            margin: EdgeInsets.only(bottom:
                                                6.0 * _readingPrefs.paragraphSpacingFactor),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
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
                                                  fontFamily:
                                                      _readingPrefs.fontFamily,
                                                  height: heading
                                                      ? 1.3
                                                      : _readingPrefs.lineHeight,
                                                  letterSpacing:
                                                      _readingPrefs.letterSpacing == 0
                                                          ? null : _readingPrefs.letterSpacing,
                                                  wordSpacing:
                                                      _readingPrefs.wordSpacing == 0
                                                          ? null : _readingPrefs.wordSpacing,
                                                ),
                                                textAlign:
                                                    _readingPrefs.textAlignment ==
                                                            'justify'
                                                        ? TextAlign.justify
                                                        : TextAlign.start,
                                              ),
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
                              ),
                            ),
                            if (!_readerFocusMode) _controls(player),
                          ],
                        ),
      ),
    ),
    );
  }

  /// The visible source offset is not necessarily the current spoken
  /// utterance: manual EPUB scrolling, silent OPF items and exact note
  /// destinations are represented independently of the audio cursor.
  int _visibleProgressOffset(ReaderPlayer player, int totalLength) {
    final useVisual = readerUsesVisualCursor(
      narrationPlaying: player.isPlaying,
      shouldAutoFollow: _narrationFollow.shouldAutoFollow,
    );
    if (useVisual) {
      if (widget.book.format == BookFormat.epub) {
        // Never use an old programmatic checkpoint to override a detached
        // active viewport. Browse by exact original UTF-16 source offset.
        final precise = player.isPlaying
            ? _currentEpubVisualSourceOffset
            : (_visualCheckpoint.offset ?? _currentEpubVisualSourceOffset);
        if (precise != null) return precise.clamp(0, totalLength).toInt();
      } else if (_visiblePositionIndex != null &&
          (player.currentIndex < player.segments.length ||
              _visiblePositionIndex! < player.segments.length - 1)) {
        // Audio EOF and the visual end are distinct. Keep EOF only when
        // the viewport hasn't scrolled back to an earlier segment.
        final visualIndex = _visiblePositionIndex!
            .clamp(0, player.segments.length - 1).toInt();
        return player.segments[visualIndex].start
            .clamp(0, totalLength).toInt();
      }
    }
    if (player.currentIndex >= player.segments.length) {
      return totalLength;
    }
    final index = useVisual
        ? (_visiblePositionIndex ?? player.currentIndex)
        : player.currentIndex;
    final safeIndex = index.clamp(0, player.segments.length - 1).toInt();
    return player.segments[safeIndex].start.clamp(0, totalLength).toInt();
  }

  /// Explicit whole-book navigation, not speculative synthesis. Reuse the
  /// exact-source EPUB pipeline for silent content and the serialized
  /// stop/seek barrier for TXT/PDF text. Never auto-resume when scrubbing.
  void _jumpToSourceProgress(int requestedOffset, {
    String? visualSpineIdref,
    VoidCallback? onCommitted,
  }) {
    final player = _player;
    final document = _document;
    if (!mounted || player == null || player.segments.isEmpty ||
        document == null || document.text.isEmpty) return;
    final target = requestedOffset.clamp(0, document.text.length).toInt();
    if (widget.book.format == BookFormat.epub) {
      _navigateToSourceOffset(target, remember: false,
          visualSpineIdref: visualSpineIdref,
          onCommitted: onCommitted);
      return;
    }
    Future<void> jump() async {
      final selection = _sourceSelectionGate.reserve();
      if (!player.isSettledIdle) await player.pause();
      if (!mounted || _player != player || _document != document ||
          !_sourceSelectionGate.isCurrent(selection)) return;
      // The same _select pipeline handles both ordinary text segments and
      // exact source EOF, with one latest-wins guard and SQLite write.
      final atEnd = target == document.text.length;
      final index = atEnd ? player.segments.length
          : speechSegmentIndexForOffset(player.segments, target);
      if (index < 0) return;
      await _select(index,
          visualSourceOffset: atEnd ? target : null,
          reservedSelection: selection,
          onCommitted: onCommitted);
    }
    unawaited(jump().catchError((Object error, StackTrace stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot move to this position: $error')),
      );
    }));
  }

  Widget _controls(ReaderPlayer player) {
    final count = player.segments.length;
    if (!_advancedControlsExpanded) {
      return SafeArea(
        top: false,
        child: Material(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_document?.text.isNotEmpty ?? false)
                  ValueListenableBuilder<int>(
                    valueListenable: _visualProgressTick,
                    builder: (context, revision, child) => ReadingProgressBar(
                      sourceOffset: _visibleProgressOffset(
                          player, _document!.text.length),
                      sourceLength: _document!.text.length,
                      onSeekToOffset: _jumpToSourceProgress,
                    ),
                  ),
                // The source viewport may change without a player state
                // notification when the reader manually scrolls away from
                // the narrated passage. Observe visual progress revisions
                // so the EPUB chapter label always follows the visible
                // source location, not a stale speech cursor.
                ValueListenableBuilder<int>(
                  valueListenable: _visualProgressTick,
                  builder: (context, revision, child) {
                    final sections = _authorToc.isNotEmpty
                        ? _authorToc.length : _chapters.length;
                    final current = widget.book.format == BookFormat.epub &&
                            sections > 0
                        ? _currentDirectoryIndex : -1;
                    final sectionName = current < 0 || current >= sections
                        ? null
                        : _authorToc.isNotEmpty
                            ? _authorToc[current].label
                            : _chapters[current].title;
                    final sectionRange = sectionName == null
                        ? null : _currentSectionRange();
                    final sectionPercent = sectionRange == null ||
                            _document == null
                        ? null : sectionRange.percentageAt(
                            _visibleProgressOffset(
                                player, _document!.text.length));
                    return ReaderCompactControls(
                      segmentLabel: player.currentIndex >= count
                          ? 'Reading complete — Play to restart'
                          : 'Segment ' + (player.currentIndex + 1).toString() +
                              ' of ' + count.toString(),
                      sectionLabel: sectionName,
                      sectionIndex: current,
                      sectionCount: sections,
                      sectionProgressPercent: sectionPercent,
                      onOpenSections: sectionName == null
                          ? null : () => unawaited(_openChapterDirectory()),
                      isPlaying: player.isPlaying,
                      sleepTimerActive: player.sleepTimerEndsAt != null,
                      onPrevious: () => unawaited(_move(-1)),
                      onPlayPause: () => unawaited(_playOrPause()),
                      onNext: () => unawaited(_move(1)),
                      onExpand: () => _changeVisualReaderLayout(
                          () => _advancedControlsExpanded = true),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Advanced controls are deliberately bounded and separately scrollable:
    // voice diagnostics and large accessibility text must not consume the
    // entire book viewport or overflow a small Android display.
    final advancedMaxHeight =
        (MediaQuery.sizeOf(context).height * 0.52)
            .clamp(130.0, 420.0).toDouble();
    return SafeArea(
      top: false,
      child: Material(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('reader-collapse-controls'),
                  onPressed: () => _changeVisualReaderLayout(
                      () => _advancedControlsExpanded = false),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Less controls'),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: advancedMaxHeight),
                child: Scrollbar(
                  controller: _advancedControlsScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const ValueKey('reader-advanced-controls-scroll'),
                    controller: _advancedControlsScroll,
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
                      if ((_document?.text.isNotEmpty ?? false))
                        ValueListenableBuilder<int>(
                          valueListenable: _visualProgressTick,
                          builder: (context, revision, child) =>
                              ReadingProgressBar(
                            sourceOffset: _visibleProgressOffset(
                                player, _document!.text.length),
                            sourceLength: _document!.text.length,
                            onSeekToOffset: _jumpToSourceProgress,
                          ),
                        ),
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          IconButton(
                            tooltip: 'Previous segment (Left arrow)',
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
                            tooltip: 'Next segment (Right arrow)',
                            icon: const Icon(Icons.skip_next),
                            onPressed: () => _move(1),
                          ),
                          IconButton(
                            tooltip: 'Keyboard shortcuts (F1)',
                            icon: const Icon(Icons.keyboard_outlined),
                            onPressed: () => unawaited(
                                showReaderKeyboardHelp(context)),
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
                      if (player.engineProviderId == 'sherpa-vits')
                        CheckboxListTile(
                          key: const ValueKey('offline-next-wav-warmup'),
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: const Text('Prepare next offline voice clip'),
                          subtitle: const Text(
                            'On by default for the selected local VITS voice. '
                            'Prepares only one future WAV, using local CPU and '
                            'temporary disk but no network or provider fees. '
                            'Stop, pause and seek cancel pending synthesis.',
                          ),
                          value: player.warmNextOfflineChunk,
                          onChanged: (enabled) =>
                              player.setOfflineWarmup(enabled ?? false),
                        ),
                      if (player.engineProviderId == 'sherpa-vits' &&
                          player.offlineVoiceStatistics != null)
                        Builder(builder: (context) {
                          final d = player.offlineVoiceStatistics!;
                          return ExpansionTile(
                            key: const ValueKey('offline-vits-performance'),
                            title: const Text('Offline voice performance'),
                            subtitle: const Text(
                              'This session only. No book text or audio logged; '
                              'RAM reflects the entire app, not just ONNX.',
                            ),
                            children: [
                              ListTile(
                                dense: true,
                                title: Text(
                                  'Model loads: ${d.modelLoads} · '
                                  'Syntheses: ${d.syntheses} · '
                                  'Prepared in advance: ${d.aheadSyntheses} · '
                                  'WAVs reused: ${d.warmedWaveReuses}',
                                ),
                              ),
                              ListTile(
                                dense: true,
                                title: Text(
                                  'Last synthesis: ${d.lastSynthesisMs} ms · '
                                  'Average: ${d.averageSynthesisMs} ms · '
                                  'P95 of last 64: ${d.p95SynthesisMs} ms',
                                ),
                                subtitle: const Text(
                                  'Native/model synthesis duration; '
                                  'P95 is a rolling sample statistic.',
                                ),
                              ),
                              ListTile(
                                dense: true,
                                title: Text(
                                  'Decoder handoff: ${d.lastDecoderHandoffMs} ms · '
                                  'Whole-process RSS: '
                                  '${d.lastWholeProcessRssMiB} MiB',
                                ),
                                subtitle: Text(
                                  'Failed: ${d.failures} · '
                                  'Cancelled: ${d.cancelledSyntheses} · '
                                  'Pending WAV cleanup: ${d.pendingWaveFolders}. '
                                  'Handoff is not audible onset; '
                                  'RSS is not model-only memory.',
                                ),
                              ),
                              ListTile(
                                key: const ValueKey('reader-narration-transition-timing'),
                                dense: true,
                                title: const Text('Real-reading narration timing'),
                                subtitle: Text(formatNarrationTransitionDiagnostics(
                                    player.narrationTimings)),
                              ),
                              ListTile(
                                key: const ValueKey('reader-narration-delay-analysis'),
                                dense: true,
                                title: const Text('Where transition time is spent'),
                                subtitle: Text(formatNarrationDelayAssessment(
                                    player.narrationTimings)),
                              ),
                            ],
                          );
                        }),
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
                                  ? Platform.isWindows
                                      ? 'Engine: system voice (interpreted pauses)'
                                      : 'Engine: Android voice (native punctuation)'
                                  : player.currentPreferences.providerId == 'system-interpreted'
                                      ? 'Engine: system voice (interpreted punctuation)'
                                      : player.currentPreferences.providerId == 'system-native'
                                          ? 'Engine: system voice (native punctuation)'
                                      : player.currentPreferences.providerId ==
                                              SherpaVitsSpeechEngine.providerId
                                          ? 'Engine: local neural VITS (experimental)'
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
                                  final globalPrefs = widget.store.getSpeechPreferences(
                                    bookId: widget.book.id,
                                  );
                                  await player.applyPreferences(globalPrefs);
                                  player.setDialogueTurnPause(Duration(
                                      milliseconds: globalPrefs.dialogueTurnPauseMs));
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
                          Text((player.currentPreferences.providerId == 'system' ||
                              player.currentPreferences.providerId == 'system-native' ||
                                   player.currentPreferences.providerId == 'system-interpreted')
                              ? 'Pitch' : 'Pitch unavailable'),
                          Expanded(
                            child: Slider(
                              min: 0.5,
                              max: 1.5,
                              divisions: 10,
                              value: player.pitch,
                              onChanged: (player.currentPreferences.providerId == 'system' ||
                                  player.currentPreferences.providerId == 'system-native' ||
                                   player.currentPreferences.providerId == 'system-interpreted')
                                  ? (value) {
                                      player.setPitch(value);
                                    }
                                  : null,
                              onChangeEnd: (player.currentPreferences.providerId == 'system' ||
                                  player.currentPreferences.providerId == 'system-native' ||
                                   player.currentPreferences.providerId == 'system-interpreted')
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
                      if (player.engineProviderId == 'system' ||
                          player.engineProviderId == 'system-native' ||
                           player.engineProviderId == 'system-interpreted')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('Dialogue pause'),
                                  Expanded(
                                    child: Slider(
                                      key: const ValueKey('dialogue-turn-pause'),
                                      min: 0,
                                      max: 2000,
                                      divisions: 80,
                                      value: player.dialogueTurnPause.inMilliseconds
                                          .toDouble(),
                                      onChanged: (value) => player.setDialogueTurnPause(
                                        Duration(milliseconds: value.round()),
                                      ),
                                      onChangeEnd: (_) =>
                                          unawaited(_saveVoiceSettings()),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      player.dialogueTurnPause == Duration.zero
                                          ? 'Off'
                                          : '${player.dialogueTurnPause.inMilliseconds} ms',
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Extra breath only between different installed '
                                'narrator/character voices. The current sentence '
                                'continues unchanged. Does not affect cloud TTS.',
                              ),
                            ],
                          ),
                        ),
                      if (player.supportsVolume)
                        Row(
                          children: [
                            const Text('Volume'),
                            Expanded(
                              child: Slider(
                                key: const ValueKey('system-speech-volume'),
                                min: 0,
                                max: 1,
                                divisions: 20,
                                value: player.volume,
                                semanticFormatterCallback: (value) =>
                                    '${(value * 100).round()} percent',
                                onChanged: player.setVolume,
                                onChangeEnd: (_) {
                                  unawaited(player.restartAfterSettingsChange());
                                  unawaited(_saveVoiceSettings());
                                },
                              ),
                            ),
                            SizedBox(
                              width: 54,
                              child: Text('${(player.volume * 100).round()}%',
                                  textAlign: TextAlign.end),
                            ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
