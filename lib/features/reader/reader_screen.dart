import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../audio/reader_player.dart';
import '../../audio/speech_engine.dart';
import '../../data/book_decoder.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/speech_segment.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, required this.store});
  final BookRecord book;
  final LibraryStore store;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ReaderPlayer? _player;
  String? _error;
  bool _loading = true;
  double _fontSize = 19;
  bool _pdfTextMode = false;

  @override
  void initState() {
    super.initState();
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
      final chunks = segmentSpeech(document.text);
      final player = ReaderPlayer(
        engine: SystemSpeechEngine(),
        segments: chunks,
        onSegmentStarted: (segment) =>
            widget.store.savePosition(widget.book.id, segment.start),
      );
      final saved = widget.book.progressOffset;
      final savedIndex = chunks.indexWhere((chunk) => chunk.end > saved);
      if (savedIndex >= 0) player.currentIndex = savedIndex;
      await player.loadVoices();
      if (!mounted) {
        player.dispose();
        return;
      }
      player.addListener(_onPlaybackChanged);
      setState(() {
        _player = player;
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

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _playOrPause() async {
    final player = _player;
    if (player == null) return;
    try {
      if (player.isPlaying) {
        await player.pause();
      } else {
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
    );
  }

  @override
  void dispose() {
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
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 24,
                                  ),
                                  itemCount: player.segments.length,
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
                  const Text('Pitch'),
                  Expanded(
                    child: Slider(
                      min: 0.5,
                      max: 1.5,
                      divisions: 10,
                      value: player.pitch,
                      onChanged: player.setPitch,
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
                      onChanged: player.setRate,
                    ),
                  ),
                  Text(player.rate.toStringAsFixed(1)),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: player.language,
                    items: const [
                      DropdownMenuItem(value: 'it-IT', child: Text('IT')),
                      DropdownMenuItem(value: 'en-US', child: Text('EN')),
                    ],
                    onChanged: (value) {
                      if (value != null) player.setLanguage(value);
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
