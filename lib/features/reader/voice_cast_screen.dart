import 'dart:math';

import 'package:flutter/material.dart';

import '../../audio/speech_engine.dart';
import '../../data/book_decoder.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/speech_segment.dart';
import '../../domain/voice_cast.dart';

/// User-curated characters, provider voice profiles and segment attribution.
/// Never guesses speakers, modifies the source or sends text to an LLM.
class VoiceCastScreen extends StatefulWidget {
  const VoiceCastScreen({
    super.key,
    required this.store,
    required this.book,
    required this.document,
    required this.segments,
    required this.providerId,
    required this.availableVoices,
  });
  final LibraryStore store;
  final BookRecord book;
  final DocumentContent document;
  final List<SpeechSegment> segments;
  final String providerId;
  final List<SpeechVoice> availableVoices;

  @override
  State<VoiceCastScreen> createState() => _VoiceCastScreenState();
}

class _VoiceCastScreenState extends State<VoiceCastScreen> {
  List<CastCharacter> _characters = const [];
  List<CastVoiceAssignment> _voices = const [];
  late VoiceCastResolver _resolver;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _characters = widget.store.listCastCharacters(widget.book.id);
    _voices = widget.store.listCastVoices(widget.book.id);
    _resolver = VoiceCastResolver(
      bookId: widget.book.id,
      providerId: widget.providerId,
      attributions: widget.store.listSegmentCast(widget.book.id),
      voices: _voices,
      offsetFromAnchor: widget.document.offsetOf,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cast update failed: ' + error.toString())),
    );
  }

  Future<void> _edit(CastCharacter? old) async {
    final name = TextEditingController(text: old?.name ?? '');
    final aliases = TextEditingController(text: old?.aliases.join(', ') ?? '');
    final result = await showDialog<CastCharacter>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(old == null ? 'Add character' : 'Edit character'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: aliases,
              decoration: const InputDecoration(
                labelText: 'Aliases (comma separated)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final person = CastCharacter(
                id: old?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString() + '-' +
                    Random.secure().nextInt(1 << 30).toString(),
                bookId: widget.book.id,
                name: name.text.trim(),
                aliases: aliases.text.split(',').map((e) => e.trim())
                    .where((e) => e.isNotEmpty).toSet().toList(),
              );
              try {
                person.validate();
                Navigator.pop(dialog, person);
              } on FormatException catch (error) {
                ScaffoldMessenger.of(dialog).showSnackBar(
                  SnackBar(content: Text(error.message)),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    aliases.dispose();
    if (!mounted || result == null) return;
    try {
      await widget.store.saveCastCharacter(result);
      _reload();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _delete(CastCharacter person) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete character?'),
        content: Text('Remove ' + person.name +
            ' and all associated turn assignments? '
            'Those passages will return to narrator.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.store.deleteCastCharacter(person.id);
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  String _voiceKey(CastCharacter person) {
    for (final assignment in _voices) {
      if (assignment.characterId != person.id ||
          assignment.providerId != widget.providerId) continue;
      for (final voice in widget.availableVoices) {
        if (voice.name == assignment.voiceName &&
            voice.locale == assignment.voiceLocale) {
          return voice.key;
        }
      }
    }
    return '';
  }

  Future<void> _setVoice(CastCharacter person, String key) async {
    try {
      SpeechVoice? chosen;
      for (final voice in widget.availableVoices) {
        if (voice.key == key) chosen = voice;
      }
      if (chosen == null) {
        await widget.store.deleteCastVoice(person.id, widget.providerId);
      } else {
        await widget.store.saveCastVoice(CastVoiceAssignment(
          characterId: person.id,
          providerId: widget.providerId,
          voiceName: chosen.name,
          voiceLocale: chosen.locale,
        ));
      }
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _setSpeaker(SpeechSegment segment, String id) async {
    try {
      if (id.isEmpty) {
        await widget.store.deleteSegmentCast(
          widget.book.id, segment.start, segment.end);
      } else {
        await widget.store.saveSegmentCast(SegmentCastAssignment(
          bookId: widget.book.id,
          start: segment.start,
          end: segment.end,
          sourceDigest: SegmentCastAssignment.fingerprint(segment.text),
          characterId: id,
          anchor: widget.document.anchorAt(
            widget.book.format, segment.start),
        ));
      }
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  Widget _charactersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        const Text('Define characters manually and select their voice. '
            'Voices are specific to the active provider. '
            'Unknown speakers always use the narrator.'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add character'),
        ),
        Text('Current provider: ' + widget.providerId),
        if (widget.availableVoices.isEmpty)
          const Text('No voices available for this provider yet.'),
        for (final person in _characters)
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(person.name),
                  subtitle: Text(person.aliases.isEmpty
                      ? 'No aliases' : person.aliases.join(', ')),
                  onTap: () => _edit(person),
                  trailing: IconButton(
                    tooltip: 'Delete character',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(person),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: DropdownButtonFormField<String>(
                    value: _voiceKey(person),
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Voice for this provider'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Use narrator voice')),
                      for (final voice in widget.availableVoices)
                        DropdownMenuItem(
                          value: voice.key,
                          child: Text(voice.toString(),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (key) {
                      if (key != null) _setVoice(person, key);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _passagesTab() {
    final term = _search.text.toLowerCase().trim();
    final indices = <int>[];
    for (var i = 0; i < widget.segments.length; i++) {
      if (term.isEmpty ||
          widget.segments[i].text.toLowerCase().contains(term)) {
        indices.add(i);
      }
    }
    final names = <String, String>{
      for (final person in _characters) person.id: person.name,
    };

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(children: [
          const Text('Select the speaker for each passage. '
              'This prototype tags entire text segments: a passage '
              'mixing narration and dialogue should stay with narrator.'),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), labelText: 'Filter passages'),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: indices.length,
          itemBuilder: (context, index) {
            final i = indices[index];
            final segment = widget.segments[i];
            final speaker = _resolver.speakerFor(segment);
            return ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(segment.text, maxLines: 3,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(
                'Segment ' + (i + 1).toString() + ' · ' +
                (speaker == null
                    ? 'Narrator' : (names[speaker] ?? 'Unknown')),
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Assign speaker',
                onSelected: (value) => _setSpeaker(segment, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: '', child: Text('Narrator / unknown'),
                  ),
                  for (final person in _characters)
                    PopupMenuItem(
                      value: person.id, child: Text(person.name),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Voice cast'),
        bottom: const TabBar(tabs: [
          Tab(icon: Icon(Icons.groups_outlined), text: 'Characters'),
          Tab(icon: Icon(Icons.format_quote), text: 'Passages'),
        ]),
      ),
      body: TabBarView(children: [_charactersTab(), _passagesTab()]),
    ),
  );
}
