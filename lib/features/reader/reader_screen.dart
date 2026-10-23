import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../audio/reader_player.dart';
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

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, required this.store});
  final BookRecord book;
  final LibraryStore store;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final SpeechSecretVault _vault = PlatformSpeechSecretVault();
  ReaderPlayer? _player;
  DocumentContent? _document;
  List<PronunciationRule> _pronunciationRules = const [];
  Map<String, String> _castNames = const {};
  Map<int, String> _fineSpeakerByStart = const {};
  String? _error;
  bool _loading = true;
  double _fontSize = 19;
  bool _pdfTextMode = false;
  bool _autoFollow = true;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Timer? _saveVisualPositionTimer;
  int? _visiblePositionIndex;
  int _lastFollowedIndex = -1;
  Object? _lastReportedPlaybackError;

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onVisiblePositions);
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
      // Finer original-text spans allow manual dialogue casting without
      // assigning the surrounding narrator text to the character.
      final baseChunks = splitQuotedSegments(segmentSpeech(document.text));
      final prepared = prepareCastSpeech(
        source: document.text,
        base: baseChunks,
        annotations: widget.store.listCastSpans(widget.book.id),
        offsetFromAnchor: document.offsetOf,
      );
      final chunks = prepared.segments;
      final prefs = widget.store.getSpeechPreferences(bookId: widget.book.id);
      final player = ReaderPlayer(
        engineProviderId: prefs.providerId,
        engine: SpeechEngineFactory(vault: _vault).create(
          preferences: prefs,
          bookId: widget.book.id,
          store: widget.store,
        ),
        segments: chunks,
        onSegmentStarted: (segment) => widget.store.savePosition(
          widget.book.id, segment.start,
          anchor: document.anchorAt(widget.book.format, segment.start),
        ),
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
      _fineSpeakerByStart = prepared.speakerByStart;
      _configureVoiceCast(player, document);
      if (!mounted) {
        player.dispose();
        return;
      }
      final previous = _player;
      if (previous != null) {
        previous.removeListener(_onPlaybackChanged);
        previous.dispose();
      }
      _lastFollowedIndex = player.currentIndex;
      _visiblePositionIndex = player.currentIndex;
      player.addListener(_onPlaybackChanged);
      setState(() {
        _player = player;
        _document = document;
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

  void _configureVoiceCast(ReaderPlayer player, DocumentContent document) {
    final people = widget.store.listCastCharacters(widget.book.id);
    final legacy = widget.store.listSegmentCast(widget.book.id);
    final voices = widget.store.listCastVoices(widget.book.id);
    _castNames = {for (final person in people) person.id: person.name};
    final legacyResolver = VoiceCastResolver(
      bookId: widget.book.id,
      providerId: player.currentPreferences.providerId,
      attributions: legacy,
      voices: voices,
      offsetFromAnchor: document.offsetOf,
    );
    String? speakerForSegment(SpeechSegment segment) =>
        _fineSpeakerByStart[segment.start] ??
        legacyResolver.speakerFor(segment);
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

  void _onVisiblePositions() {
    if (!mounted || _loading || _player == null || _document == null) return;
    final player = _player!;
    if (player.isPlaying || player.segments.isEmpty) return;
    final visible = _itemPositionsListener.itemPositions.value
        .where((item) => item.itemTrailingEdge > 0)
        .map((item) => item.index)
        .toList();
    if (visible.isEmpty) return;
    visible.sort();
    final index = visible.first.clamp(0, player.segments.length - 1).toInt();
    if (index == _visiblePositionIndex) return;
    _visiblePositionIndex = index;
    _saveVisualPositionTimer?.cancel();
    _saveVisualPositionTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || player.isPlaying || _player != player) return;
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
    if (player != null &&
        player.segments.isNotEmpty &&
        _autoFollow &&
        player.currentIndex != _lastFollowedIndex) {
      final target = player.currentIndex
          .clamp(0, player.segments.length - 1)
          .toInt();
      _lastFollowedIndex = player.currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_autoFollow || !_itemScrollController.isAttached) {
          return;
        }
        _itemScrollController.jumpTo(index: target, alignment: 0.12);
      });
    }
    setState(() {});
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
      if (player.isPlaying) {
        await player.pause();
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
        await player.play();
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
    if (player == null) return;
    await player.seekTo(index);
    await widget.store.savePosition(
      widget.book.id,
      player.segments[index].start,
      anchor: _document?.anchorAt(widget.book.format, player.segments[index].start),
    );
    _visiblePositionIndex = index;
    if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: index, alignment: 0.12);
    }
  }

  @override
  void dispose() {
    _saveVisualPositionTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onVisiblePositions);
    final player = _player;
    if (player != null) {
      player.removeListener(_onPlaybackChanged);
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
                          child: PdfViewer.file(widget.book.localPath),
                        ),
                      ],
                    )
                  : player == null || player.segments.isEmpty
                      ? const Center(child: Text('No readable text'))
                      : Column(
                          children: [
                            Expanded(
                              child: SelectionArea(
                                child: ScrollablePositionedList.builder(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 24,
                                  ),
                                  itemCount: player.segments.length,
                                  itemScrollController: _itemScrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  initialScrollIndex: player.currentIndex
                                      .clamp(0, player.segments.length - 1)
                                      .toInt(),
                                  itemBuilder: (context, index) {
                                    final segment = player.segments[index];
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
                                        child: Text(
                                          segment.text,
                                          style: TextStyle(
                                            fontSize: _fontSize,
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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
                ],
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
