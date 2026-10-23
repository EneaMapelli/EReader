import 'dart:math';

import 'package:flutter/material.dart';

import '../../audio/speech_engine.dart';
import '../../audio/secret_vault.dart';
import 'dialogue_analysis_screen.dart';
import '../../data/book_decoder.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/speech_segment.dart';
import '../../domain/voice_cast.dart';
import '../../domain/cast_span.dart';
import '../../domain/character_candidate.dart';
import '../../domain/llm_cast_proposals.dart';

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
  List<CharacterCandidate> _characterCandidates = const [];
  List<CastSpan> _fine = const [];
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
    _characterCandidates = widget.store.listCharacterCandidates(widget.book.id);
    _fine = widget.store.listCastSpans(widget.book.id);
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

  Future<void> _annotateSelection(SpeechSegment segment) async {
    final editor = TextEditingController(text: segment.text);
    String? speaker = _characters.isEmpty ? null : _characters.first.id;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) => AlertDialog(
          title: const Text('Assign selected text'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select exactly the words spoken by this character '
                    'inside the text field. Use a long press or mouse drag. '
                    'Unselected narration keeps the narrator voice.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: editor,
                    readOnly: true,
                    showCursor: false,
                    maxLines: 6,
                    minLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Select excerpt',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: speaker ?? '',
                    decoration: const InputDecoration(labelText: 'Speaker'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '', child: Text('Narrator / unknown'),
                      ),
                      for (final person in _characters)
                        DropdownMenuItem(
                          value: person.id, child: Text(person.name),
                        ),
                    ],
                    onChanged: (choice) =>
                        refresh(() => speaker = choice ?? ''),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: editor,
                    builder: (context, value, child) {
                      final selection = value.selection;
                      final valid = selection.isValid &&
                          !selection.isCollapsed &&
                          selection.start >= 0 &&
                          selection.end <= segment.text.length;
                      return Text(valid
                          ? 'Selected: ' + segment.text.substring(
                              selection.start, selection.end)
                          : 'Select a nonempty excerpt to enable Save');
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: editor,
              builder: (context, value, child) {
                final selection = value.selection;
                final valid = selection.isValid &&
                    !selection.isCollapsed && selection.start >= 0 &&
                    selection.end <= segment.text.length;
                return FilledButton(
                  onPressed: !valid ? null : () async {
                    final start = segment.start + selection.start;
                    final end = segment.start + selection.end;
                    final original = widget.document.text.substring(start, end);
                    final span = CastSpan(
                      id: 'manual-' +
                          DateTime.now().microsecondsSinceEpoch.toString() +
                          '-' + Random.secure().nextInt(1 << 30).toString(),
                      bookId: widget.book.id,
                      start: start,
                      end: end,
                      sourceDigest: CastSpan.digest(original),
                      speakerId: speaker == null || speaker!.isEmpty
                          ? null : speaker,
                      origin: CastSpanOrigin.user,
                      status: CastSpanStatus.accepted,
                      lockedByUser: true,
                      anchor: widget.document.anchorAt(
                          widget.book.format, start),
                    );
                    try {
                      await widget.store.saveManualCastSpan(
                        span, widget.document.text);
                      if (dialog.mounted) Navigator.pop(dialog, true);
                    } catch (error) {
                      if (dialog.mounted) {
                        ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(
                          content: Text('Cannot save selection: ' +
                              error.toString()),
                        ));
                      }
                    }
                  },
                  child: const Text('Save selected excerpt'),
                );
              },
            ),
          ],
        ),
      ),
    );
    editor.dispose();
    if (mounted && saved == true) _reload();
  }

  Future<void> _importProposals() async {
    final input = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Import structured speaker proposals'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 480),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'For locally reviewed JSON annotations only. '
              'Importing never contacts an LLM or applies the labels. '
              'All suggestions appear as pending until explicitly accepted.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: input,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Version 1 JSON proposal',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.text),
            child: const Text('Validate and import'),
          ),
        ],
      ),
    );
    input.dispose();
    if (submitted == null || !mounted) return;
    try {
      final entries = const CastProposalParser().parse(
        jsonPayload: submitted,
        bookId: widget.book.id,
        sourceText: widget.document.text,
        knownSpeakerIds: {for (final c in _characters) c.id},
      );
      await widget.store.importCastProposals(
          entries, widget.document.text);
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _review(CastSpan span, {required bool approve}) async {
    try {
      await widget.store.reviewCastProposal(
        span.id,
        approve: approve,
        currentSource: widget.document.text,
        resolvedStart: span.resolvedStart(widget.document.offsetOf),
      );
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _openDialogueAnalysis() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DialogueAnalysisScreen(
          store: widget.store,
          book: widget.book,
          document: widget.document,
          segments: widget.segments,
          vault: PlatformSpeechSecretVault(),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _deleteApprovedSpan(CastSpan span) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove this speaker label?'),
        content: const Text(
          'This selected passage will revert to narrator unless '
          'an older full-segment label is still present.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove label')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.store.deleteCastSpan(span.id);
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  String _evidencePreview(CastSpan span) {
    final reference = span.evidence;
    if (reference == null) return 'No earlier source evidence supplied';
    if (!reference.matchesSource(widget.document.text)) {
      return 'Evidence no longer matches the book text';
    }
    return 'Earlier evidence: ' + widget.document.text.substring(
      reference.start, reference.end,
    );
  }

  bool _reviewable(CastSpan span) =>
      span.matchesSource(widget.document.text, widget.document.offsetOf) &&
      (span.evidence == null ||
          span.evidence!.matchesSource(widget.document.text));

  Future<void> _reviewCharacter(
    CharacterCandidate candidate, {required bool approve},
  ) async {
    if (!candidate.matchesSource(widget.document.text)) {
      _error(const FormatException(
        'Original character mention changed; cannot review stale evidence'));
      return;
    }
    if (!approve) {
      try {
        await widget.store.reviewCharacterCandidate(
          candidate.id, approve: false, source: widget.document.text,
        );
        if (mounted) _reload();
      } catch (error) {
        _error(error);
      }
      return;
    }
    final name = TextEditingController(text: candidate.name);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) {
          final current = name.text.trim();
          final allNames = <String>[
            for (final person in _characters) person.name,
            for (final person in _characters) ...person.aliases,
          ];
          final duplicate = candidateConflictsWithCast(current, allNames);
          return AlertDialog(
            title: const Text('Add this character to your cast?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The model found the exact book mention: ' +
                    candidate.name),
                Text('Confidence (not verified probability): ' +
                    candidate.confidence.toStringAsFixed(2)),
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  maxLength: 120,
                  onChanged: (_) => refresh(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Confirm or correct display name',
                  ),
                ),
                if (duplicate)
                  const Text(
                    'This name already belongs to a character or alias. '
                    'Do not create a duplicate; edit the existing cast '
                    'manually if these references identify the same person.',
                  ),
                const Text(
                  'Only an identity will be created after confirmation. '
                  'No dialogue, voice, aliases or future-story details '
                  'will be added automatically.',
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel')),
              FilledButton(
                onPressed: duplicate || current.length < 2
                    ? null : () => Navigator.pop(dialog, current),
                child: const Text('Add character'),
              ),
            ],
          );
        },
      ),
    );
    name.dispose();
    if (selected == null || !mounted) return;
    try {
      await widget.store.reviewCharacterCandidate(
        candidate.id,
        approve: true,
        source: widget.document.text,
        displayName: selected,
        newCharacterId: 'character-' +
            DateTime.now().microsecondsSinceEpoch.toString() + '-' +
            Random.secure().nextInt(1 << 30).toString(),
      );
      if (mounted) _reload();
    } catch (error) {
      _error(error);
    }
  }

  Widget _reviewTab() {
    final accepted = _fine.where(
      (span) => span.status == CastSpanStatus.accepted,
    ).toList();
    final pending = _fine.where(
      (span) => span.status == CastSpanStatus.proposed,
    ).toList();
    final names = {
      for (final character in _characters) character.id: character.name,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        const Text(
          'You can add precise manual labels in Passages. '
          'Approved labels are shown below and can be removed. '
          'Future LLM findings must be reviewed individually. '
          'Manual character labels stay locked and take precedence. '
          'You can import schema-validated JSON locally; no request '
          'or cost is triggered by this screen.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.psychology_alt_outlined),
          label: const Text('Analyze selected chapter or page with AI'),
          onPressed: _openDialogueAnalysis,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: const Text('Import structured suggestions'),
          onPressed: _importProposals,
        ),
        const Divider(height: 28),
        Text('New character candidates',
          style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'These names were proposed from exact excerpts. '
          'Approve a new identity explicitly; no voice or dialogue '
          'will be assigned automatically.',
        ),
        if (!_characterCandidates.any(
            (c) => c.status == CharacterCandidateStatus.proposed))
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No new character candidates await review.'),
          ),
        for (final candidate in _characterCandidates)
          if (candidate.status == CharacterCandidateStatus.proposed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_search_outlined),
                title: Text(candidate.name),
                subtitle: Text(candidate.matchesSource(widget.document.text)
                    ? 'Original mention verified · confidence ' +
                        candidate.confidence.toStringAsFixed(2)
                    : 'Original book text changed: cannot approve'),
                trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Review and create this character',
                    icon: const Icon(Icons.person_add_alt_1),
                    onPressed: candidate.matchesSource(widget.document.text)
                        ? () => _reviewCharacter(candidate, approve: true)
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Reject character candidate',
                    icon: const Icon(Icons.close),
                    onPressed: () => _reviewCharacter(candidate, approve: false),
                  ),
                ]),
              ),
            ),
        const Divider(height: 28),
        Text('Approved speaker labels',
            style: Theme.of(context).textTheme.titleMedium),
        if (accepted.isEmpty)
          const Text('No fine-grained labels have been approved yet.'),
        for (final span in accepted)
          ListTile(
            leading: Icon(span.origin == CastSpanOrigin.user
                ? Icons.lock : Icons.verified_outlined),
            title: Text(span.matchesSource(
                  widget.document.text, widget.document.offsetOf)
                ? widget.document.text.substring(
                    span.resolvedStart(widget.document.offsetOf)!,
                    span.resolvedStart(widget.document.offsetOf)! +
                        span.length)
                : '[Stale source annotation]'),
            subtitle: Text(
              (names[span.speakerId] ?? 'Narrator / unknown') +
              (span.origin == CastSpanOrigin.user
                  ? ' · manual lock' : ' · approved suggestion'),
            ),
            trailing: IconButton(
              tooltip: 'Remove this speaker label',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteApprovedSpan(span),
            ),
          ),
        const Divider(height: 28),
        Text('Pending proposals',
            style: Theme.of(context).textTheme.titleMedium),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('There are no pending speaker suggestions.'),
          ),
        for (final span in pending)
          Card(
            child: ListTile(
              title: Text(span.matchesSource(
                    widget.document.text, widget.document.offsetOf)
                  ? widget.document.text.substring(
                      span.resolvedStart(widget.document.offsetOf)!,
                      span.resolvedStart(widget.document.offsetOf)! +
                          span.length)
                  : '[Stale annotation: source text changed]',
                maxLines: 3),
              subtitle: Text(
                'Speaker: ' + (names[span.speakerId] ?? 'Unknown') +
                ' · confidence: ' +
                (span.confidence?.toStringAsFixed(2) ?? '?') +
                '\n' + _evidencePreview(span),
              ),
              trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'Accept this suggestion',
                  onPressed: _reviewable(span)
                      ? () => _review(span, approve: true) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Reject this suggestion',
                  onPressed: () => _review(span, approve: false),
                ),
              ]),
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
          const Text(
            'Use the text-selection icon to label just part of a passage. '
            'The menu still assigns an entire current segment. '
            'Unknown dialogue remains in the narrator voice.',
          ),
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
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Assign a selected part of the passage',
                  icon: const Icon(Icons.format_color_text),
                  onPressed: () => _annotateSelection(segment),
                ),
                PopupMenuButton<String>(
                tooltip: 'Assign whole segment',
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
              ]),
            );
          },
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Voice cast'),
        bottom: const TabBar(tabs: [
          Tab(icon: Icon(Icons.groups_outlined), text: 'Characters'),
          Tab(icon: Icon(Icons.format_quote), text: 'Passages'),
          Tab(icon: Icon(Icons.fact_check_outlined), text: 'Review'),
        ]),
      ),
      body: TabBarView(children: [
        _charactersTab(), _passagesTab(), _reviewTab(),
      ]),
    ),
  );
}
