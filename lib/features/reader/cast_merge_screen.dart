import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/cast_merge.dart';
import '../../domain/voice_cast.dart';

/// A destructive character merge is always preceded by an immutable preview,
/// explicit conflict choices and a final acknowledgement. No LLM API calls.
class CastMergeScreen extends StatefulWidget {
  const CastMergeScreen({
    super.key, required this.store, required this.book,
  });

  final LibraryStore store;
  final BookRecord book;

  @override
  State<CastMergeScreen> createState() => _CastMergeScreenState();
}

class _CastMergeScreenState extends State<CastMergeScreen> {
  late List<CastCharacter> _characters;
  String? _sourceId;
  String? _targetId;
  CastMergePreview? _preview;
  String? _error;
  final _voiceDecisions = <String, String>{};
  bool _acknowledged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _characters = widget.store.listCastCharacters(widget.book.id);
  }

  void _recalculate() {
    _preview = null;
    _error = null;
    _acknowledged = false;
    _voiceDecisions.clear();
    if (_sourceId != null && _targetId != null &&
        _sourceId != _targetId) {
      try {
        _preview = widget.store.previewCastMerge(
          widget.book.id, _sourceId!, _targetId!,
        );
      } catch (error) {
        _error = error.toString();
      }
    }
  }

  Future<void> _merge() async {
    final preview = _preview;
    if (preview == null || _saving || !_acknowledged ||
        _voiceDecisions.length != preview.providerConflicts.length) return;
    setState(() { _saving = true; _error = null; });
    try {
      final result = await widget.store.mergeCastCharacters(
        CastMergeDecision(
          bookId: widget.book.id,
          sourceCharacterId: preview.source.id,
          targetCharacterId: preview.target.id,
          expectedSnapshotDigest: preview.snapshotDigest,
          providerChoices: Map.of(_voiceDecisions),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Merged into ' + result.mergedName +
            ' (reviewed ' + result.movedRecordCount.toString() +
            ' dependent references and voice profiles).'),
      ));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Merge cancelled without partial changes: ' +
              error.toString();
          // A concurrent edit invalidates the preview. Require review again.
          _preview = null;
          _acknowledged = false;
          _voiceDecisions.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final ready = preview != null &&
        _acknowledged &&
        _voiceDecisions.length == preview.providerConflicts.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge duplicate characters')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
        children: [
          const Text('This is a manual operation, not an AI decision. '
              'Choose the identity to REMOVE and the identity to KEEP. '
              'The kept identity retains its stable ID and gets all '
              'source speaker assignments, approved character links '
              'and historical aliases. Provider-specific voice conflicts '
              'must be resolved explicitly. The merge cannot be undone '
              'automatically.'),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _sourceId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Remove duplicate identity',
            ),
            items: [
              for (final person in _characters)
                DropdownMenuItem(
                  value: person.id,
                  child: Text(person.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _saving ? null : (value) => setState(() {
              _sourceId = value;
              _recalculate();
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _targetId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Keep this identity and its stable ID',
            ),
            items: [
              for (final person in _characters)
                DropdownMenuItem(
                  value: person.id,
                  child: Text(person.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _saving ? null : (value) => setState(() {
              _targetId = value;
              _recalculate();
            }),
          ),
          const SizedBox(height: 12),
          if (_sourceId != null && _sourceId == _targetId)
            const Text('The source and destination must be different.'),
          if (_error != null)
            SelectableText(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (preview != null) ...[
            const Divider(height: 30),
            Text('Preview (no data modified yet)',
                style: Theme.of(context).textTheme.titleMedium),
            Text('Remove: ' + preview.source.name +
                ' (' + preview.source.id + ')'),
            Text('Keep: ' + preview.target.name +
                ' (' + preview.target.id + ')'),
            const SizedBox(height: 12),
            Text('Resulting aliases:',
                style: Theme.of(context).textTheme.labelLarge),
            Text(preview.resultingAliases.isEmpty
                ? 'None'
                : preview.resultingAliases.join(' · ')),
            const SizedBox(height: 12),
            Text('Associated records transferred:',
                style: Theme.of(context).textTheme.labelLarge),
            for (final entry in preview.counts.entries)
              Text(entry.key.replaceAll('_', ' ') + ': ' +
                  entry.value.toString()),
            const SizedBox(height: 14),
            if (preview.providerConflicts.isNotEmpty) ...[
              Text('Voice conflicts — choose for each provider',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text('No provider voice is overwritten without '
                  'the choice below. Other providers are preserved.'),
              for (final conflict in preview.providerConflicts)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    value: _voiceDecisions[conflict.providerId],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Provider: ' + conflict.providerId,
                      hintText: 'Choose which voice to keep',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'target',
                        child: Text('Keep ' + preview.target.name + ': ' +
                            conflict.target.voiceName +
                            ' (' + conflict.target.voiceLocale + ')',
                          overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'source',
                        child: Text('Use ' + preview.source.name + ': ' +
                            conflict.source.voiceName +
                            ' (' + conflict.source.voiceLocale + ')',
                          overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onChanged: _saving ? null : (choice) => setState(() {
                      if (choice == null) {
                        _voiceDecisions.remove(conflict.providerId);
                      } else {
                        _voiceDecisions[conflict.providerId] = choice;
                      }
                      _acknowledged = false;
                    }),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _acknowledged,
              onChanged: _saving ? null : (value) =>
                  setState(() => _acknowledged = value ?? false),
              title: const Text('I verified both identities and all '
                  'voice choices. Merge them into the kept character.'),
              subtitle: const Text('This will delete the duplicate identity '
                  'but preserve its related speaker/voice metadata and '
                  'write a merge audit record. No book text is modified.'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.merge_type),
              onPressed: ready && !_saving ? _merge : null,
              label: Text(_saving ? 'Merging…' : 'Confirm manual merge'),
            ),
          ],
        ],
      ),
    );
  }
}
