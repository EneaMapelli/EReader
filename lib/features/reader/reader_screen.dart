import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
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
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/speech_segment.dart';
import '../../domain/dialogue_segmenter.dart';
import '../../domain/pronunciation_rule.dart';
import '../../domain/voice_cast.dart';
import '../../domain/cast_span.dart';
import 'voice_cast_screen.dart';
import 'pronunciation_screen.dart';
import 'reading_tools.dart';
import 'epub_chapter_navigation.dart';
import 'epub_visual_layout.dart';
import 'epub_paragraph_tile.dart';

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
  EpubVisualLayout _epubLayout = const EpubVisualLayout([], []);
  Map<int, EpubChapter> _chapterStarts = const {};
  List<PronunciationRule> _pronunciationRules = const [];
  Map<String, String> _castNames = const {};
  Map<int, String?> _resolvedSpeakerByStart = const {};
  String? _error;
  bool _loading = true;
  double _fontSize = 19;
  EpubReadingPalette _epubPalette = EpubReadingPalette.system;
  bool _pdfTextMode = false;
  bool _autoFollow = true;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Timer? _saveVisualPositionTimer;
  Timer? _savePdfPageTimer;
  int? _pendingPdfPage;
  late int _displayPdfPage;
  int? _visiblePositionIndex;
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

  Future<void> _load() async {
    try {
      final document = await PrototypeDocumentDecoder().read(widget.book);
      if (!mounted) return;
      // A quoted turn can cross multiple source chunks. Resolve both
      // legacy whole-passage and precise manual tags as verified ranges
      // BEFORE merging short fragments for the same voice/quote group.
      final quoted = splitQuotedSegmentsWithRegions(
        widget.book.format == BookFormat.epub
            ? segmentEpubSpine(document)
            : segmentSpeech(document.text),
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
      final prepared = coalesceQuotedSpeech(
        source: document.text,
        chunks: assigned.segments,
        quotedChunks: quoted,
        speakerByStart: assigned.speakerByStart,
        hardBoundaries: widget.book.format == BookFormat.epub
            ? epubParagraphHardBoundaries(document)
            : const [],
      );
      final chunks = prepared.segments;
      final chapters = widget.book.format == BookFormat.epub
          ? buildEpubChapters(document, chunks)
          : const <EpubChapter>[];
      final visualLayout = widget.book.format == BookFormat.epub
          ? buildEpubVisualLayout(document, chunks, chapters)
          : const EpubVisualLayout([], []);
      final prefs = widget.store.getSpeechPreferences(bookId: widget.book.id);
      final recoveryBinding = NarrationRecoveryBinding(
        store: widget.store,
        bookId: widget.book.id,
        anchorFor: (segment) =>
            document.anchorAt(widget.book.format, segment.start),
      );
      final player = ReaderPlayer(
        engineProviderId: prefs.providerId,
        engine: SpeechEngineFactory(vault: _vault).create(
          preferences: prefs,
          bookId: widget.book.id,
          store: widget.store,
        ),
        segments: chunks,
        onSegmentStarted: recoveryBinding.onSegmentStarted,
      );
      final latestBook = widget.store.getBook(widget.book.id) ?? widget.book;
      final saved = latestBook.progressAnchor == null
          ? latestBook.progressOffset
          : document.offsetOf(latestBook.progressAnchor!) ??
              latestBook.progressOffset;
      final savedIndex = chunks.indexWhere((chunk) => chunk.end > saved);
      if (savedIndex >= 0) player.currentIndex = savedIndex;
      _pronunciationRules =
          widget.store.listPronunciationRules(bookId: widget.book.id);
      player.speechTextTransform = (original) =>
          const PronunciationTransformer().apply(
              original, _pronunciationRules, bookId: widget.book.id);
      await player.loadVoices();
      await player.applyPreferences(prefs);
      _resolvedSpeakerByStart = prepared.speakerByStart;
      _configureVoiceCast(player);
      if (!mounted) {
        recoveryBinding.dispose();
        player.dispose();
        return;
      }
      final previous = _player;
      if (previous != null) {
        widget.mediaHandler?.detach(previous);
        previous.removeListener(_onPlaybackChanged);
        _recoveryBinding?.dispose();
        previous.dispose();
      }
      _lastFollowedIndex = widget.book.format == BookFormat.epub
          ? visualLayout.blockForSegment(player.currentIndex)
          : player.currentIndex;
      _visiblePositionIndex = player.currentIndex;
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
        _chapters = chapters;
        _epubLayout = visualLayout;
        _chapterStarts = {
          for (final chapter in chapters) chapter.segmentIndex: chapter,
        };
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _configureVoiceCast(ReaderPlayer player) {
    final people = widget.store.listCastCharacters(widget.book.id);
    final voices = widget.store.listCastVoices(widget.book.id);
    _castNames = {for (final person in people) person.id: person.name};
    // All source-hashed legacy and precise ranges were resolved before
    // coalescing. Never fall back to exact chunk equality here: that could
    // reapply a stale or intentionally masked legacy speaker.
    String? speakerForSegment(SpeechSegment segment) =>
        _resolvedSpeakerByStart[segment.start];
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
  void _onPdfPageChanged(int? pageNumber) {
    if (!mounted || widget.book.format != BookFormat.pdf ||
        _pdfTextMode || pageNumber == null ||
        pageNumber < 1 || pageNumber > 100000) return;
    if (_pendingPdfPage == pageNumber) return;
    _displayPdfPage = pageNumber;
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
        .where((item) => item.itemTrailingEdge > 0)
        .map((item) => item.index)
        .toList();
    if (visible.isEmpty) return;
    visible.sort();
    final firstItem = visible.first;
    final int index;
    if (widget.book.format == BookFormat.epub) {
      if (firstItem >= _epubLayout.blocks.length) return;
      final firstSegment = _epubLayout.blocks[firstItem].firstSegmentIndex;
      if (firstSegment == null) return;
      index = firstSegment;
    } else {
      index = firstItem.clamp(0, player.segments.length - 1).toInt();
    }
    if (index == _visiblePositionIndex) return;
    final previousChapter = _currentChapterIndex;
    _visiblePositionIndex = index;
    if (_chapters.isNotEmpty &&
        _currentChapterIndex != previousChapter) {
      setState(() {});
    }
    _saveVisualPositionTimer?.cancel();
    _saveVisualPositionTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || player.isPlaying || _player != player ||
          (widget.book.format == BookFormat.pdf && !_pdfTextMode)) return;
      final segment = player.segments[index];
      widget.store.savePosition(
        widget.book.id, segment.start,
        anchor: _document?.anchorAt(widget.book.format, segment.start),
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
      // Pause/resume must continue from the audio cursor, even when no
      // manual visual scrolling occurred during the previous utterance.
      _visiblePositionIndex = player.currentIndex
          .clamp(0, player.segments.length - 1).toInt();
    }
    if (player != null && player.segments.isNotEmpty && _autoFollow) {
      final segmentIndex = player.currentIndex
          .clamp(0, player.segments.length - 1).toInt();
      final target = widget.book.format == BookFormat.epub
          ? _epubLayout.blockForSegment(segmentIndex)
          : segmentIndex;
      if (target != _lastFollowedIndex) {
        _lastFollowedIndex = target;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_autoFollow || !_itemScrollController.isAttached) {
            return;
          }
          _itemScrollController.jumpTo(index: target, alignment: 0.12);
        });
      }
    }
    setState(() {});
  }

  int get _currentChapterIndex {
    final player = _player;
    if (player == null || player.segments.isEmpty || _chapters.isEmpty) {
      return -1;
    }
    // During manual browsing, show the chapter visible on screen. During
    // playback, the audio cursor is authoritative for the chapter indicator.
    final selected = player.isPlaying
        ? player.currentIndex
        : (_visiblePositionIndex ?? player.currentIndex);
    final cursor = selected.clamp(0, player.segments.length - 1).toInt();
    return chapterIndexForOffset(
      _chapters, player.segments[cursor].start,
    );
  }

  /// Chapter navigation never starts cloud TTS or auto-resumes interrupted
  /// playback. Persist a stable spine anchor through the existing _select.
  Future<void> _jumpToChapterIndex(int chapterIndex) async {
    final player = _player;
    if (player == null || chapterIndex < 0 ||
        chapterIndex >= _chapters.length) return;
    try {
      _saveVisualPositionTimer?.cancel();
      if (player.isPlaying) await player.pause();
      if (!mounted || _player != player) return;
      await _select(_chapters[chapterIndex].segmentIndex);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot change chapter: $error')),
      );
    }
  }

  Future<void> _openChapterDirectory() async {
    if (_chapters.isEmpty) return;
    final current = _currentChapterIndex;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.65,
          child: Column(
            children: [
              const ListTile(title: Text('EPUB chapters')),
              Expanded(
                child: ListView.builder(
                  itemCount: _chapters.length,
                  itemBuilder: (_, index) {
                    final chapter = _chapters[index];
                    return ListTile(
                      leading: index == current
                          ? const Icon(Icons.menu_book)
                          : const Icon(Icons.article_outlined),
                      title: Text(chapter.title),
                      subtitle: Text(
                          'Chapter ${index + 1} of ${_chapters.length}'),
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
    await _jumpToChapterIndex(chosen);
  }

  Future<void> _searchInBook() async {
    final player = _player;
    if (player == null || player.segments.isEmpty) return;
    final result = await showBookSearch(context, player.segments);
    if (!mounted || result == null) return;
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
    final offset = await showBookBookmarks(
      context: context,
      store: widget.store,
      book: widget.book,
      document: document,
      currentOffset: segment.start,
      currentExcerpt: segment.text,
    );
    if (!mounted || offset == null) return;
    var destination = player.segments.indexWhere(
      (entry) => entry.end > offset,
    );
    if (destination < 0) destination = player.segments.length - 1;
    await _select(destination);
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
        // If the user browsed the pages manually, start audio where the
        // reading viewport is, not at the last audio-only position.
        final visible = _visiblePositionIndex;
        if (visible != null && visible != player.currentIndex) {
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
    await player.seekTo(player.currentIndex + delta);
    if (player.segments.isNotEmpty) {
      await widget.store.savePosition(
        widget.book.id,
        player.segments[player.currentIndex].start,
        anchor: _document?.anchorAt(
          widget.book.format, player.segments[player.currentIndex].start),
      );
    }
  }

  Future<void> _select(int index) async {
    final player = _player;
    if (player == null || index < 0 || index >= player.segments.length) {
      return;
    }
    await player.seekTo(index);
    await widget.store.savePosition(
      widget.book.id,
      player.segments[index].start,
      anchor: _document?.anchorAt(widget.book.format, player.segments[index].start),
    );
    _visiblePositionIndex = index;
    if (_itemScrollController.isAttached) {
      final visualIndex = widget.book.format == BookFormat.epub
          ? _epubLayout.blockForSegment(index)
          : index;
      _lastFollowedIndex = visualIndex;
      _itemScrollController.jumpTo(index: visualIndex, alignment: 0.12);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ReaderLifecyclePolicy.backgroundTransition(state)) return;
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
    WidgetsBinding.instance.removeObserver(this);
    _saveVisualPositionTimer?.cancel();
    _flushPdfPagePosition();
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
          if (widget.book.format == BookFormat.epub && _chapters.isNotEmpty)
            IconButton(
              tooltip: 'Table of contents: EPUB spine chapters',
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
                if (mounted) setState(() => _pdfTextMode = false);
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
                                _load();
                              },
                              icon: const Icon(Icons.record_voice_over),
                              label: const Text('Read text aloud'),
                            ),
                          ],
                        ),
                        Expanded(
                          child: PdfViewer.file(
                            widget.book.localPath,
                            initialPageNumber: _displayPdfPage,
                            params: PdfViewerParams(
                              onPageChanged: _onPdfPageChanged,
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
                                      ? _epubLayout.blockForSegment(
                                          player.currentIndex)
                                      : player.currentIndex.clamp(
                                          0, player.segments.length - 1).toInt(),
                                  itemBuilder: (context, index) {
                                    if (widget.book.format == BookFormat.epub) {
                                      final block = _epubLayout.blocks[index];
                                      return EpubParagraphTile(
                                        key: ValueKey(block.start),
                                        block: block,
                                        activeSegmentIndex: player.currentIndex,
                                        fontSize: _fontSize,
                                        palette: _epubPalette,
                                        onSelectSegment: (segmentIndex) {
                                          unawaited(_select(segmentIndex));
                                        },
                                      );
                                    }
                                    final segment = player.segments[index];
                                    final heading = isStandaloneChapterHeading(
                                      _chapterStarts[index], segment,
                                    );
                                    final selected =
                                        index == player.currentIndex;
                                    return InkWell(
                                      onTap: () => _select(index),
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
              if (_chapters.isNotEmpty) ...[
                Builder(builder: (context) {
                  final index = _currentChapterIndex;
                  if (index < 0) return const SizedBox.shrink();
                  return Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous EPUB chapter',
                        onPressed: index > 0
                            ? () => _jumpToChapterIndex(index - 1)
                            : null,
                        icon: const Icon(Icons.first_page),
                      ),
                      Expanded(
                        child: Text(
                          '${_chapters[index].title} '
                          '(${index + 1}/${_chapters.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next EPUB chapter',
                        onPressed: index + 1 < _chapters.length
                            ? () => _jumpToChapterIndex(index + 1)
                            : null,
                        icon: const Icon(Icons.last_page),
                      ),
                    ],
                  );
                }),
              ],
              Text('Segment ${player.currentIndex + 1} of $count',
                  style: Theme.of(context).textTheme.labelMedium),
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
                  const Expanded(
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
