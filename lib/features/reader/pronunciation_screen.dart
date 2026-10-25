import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/pronunciation_rule.dart';

/// Only affects text sent to the TTS backend, not rendered book content.
class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({
    super.key,
    required this.store,
    required this.bookId,
    required this.bookTitle,
  });
  final LibraryStore store;
  final String bookId;
  final String bookTitle;

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  bool _bookScope = true;
  List<PronunciationRule> _rules = const [];
  final _sample = TextEditingController(
      text: 'Enea incontrò Aeryn nel vecchio castello.');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _rules = widget.store.listPronunciationRules(bookId: widget.bookId);
    });
  }

  Future<void> _edit(PronunciationRule? existing) async {
    final written = TextEditingController(text: existing?.pattern ?? '');
    final spoken = TextEditingController(text: existing?.replacement ?? '');
    var wholeWord = existing?.wholeWord ?? true;
    var caseSensitive = existing?.caseSensitive ?? false;
    var enabled = existing?.enabled ?? true;
    final bookId = existing == null
        ? (_bookScope ? widget.bookId : null)
        : existing.bookId;

    final edited = await showDialog<PronunciationRule>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add pronunciation' : 'Edit pronunciation'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(bookId == null ? 'All books' : 'This book'),
                  TextField(
                    controller: written,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Word or name in book',
                      hintText: 'Aeryn',
                    ),
                  ),
                  TextField(
                    controller: spoken,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Pronounce as',
                      hintText: 'Erin',
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Match whole words only'),
                    value: wholeWord,
                    onChanged: (v) => setDialogState(() => wholeWord = v),
                  ),
                  SwitchListTile(
                    title: const Text('Case sensitive'),
                    value: caseSensitive,
                    onChanged: (v) => setDialogState(() => caseSensitive = v),
                  ),
                  SwitchListTile(
                    title: const Text('Enabled'),
                    value: enabled,
                    onChanged: (v) => setDialogState(() => enabled = v),
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
            FilledButton(
              onPressed: () {
                final rule = PronunciationRule(
                  id: existing?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString() +
                          '-' + Random.secure().nextInt(1 << 30).toString(),
                  bookId: bookId,
                  pattern: written.text.trim(),
                  replacement: spoken.text.trim(),
                  wholeWord: wholeWord,
                  caseSensitive: caseSensitive,
                  enabled: enabled,
                );
                try {
                  rule.validate();
                  Navigator.pop(dialogContext, rule);
                } on FormatException catch (error) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.message)),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // Dialog text controllers are local and no longer used after dismissal.
    written.dispose();
    spoken.dispose();
    if (!mounted || edited == null) return;
    try {
      await widget.store.upsertPronunciationRule(edited);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot save rule: ' + error.toString())),
        );
      }
    }
  }

  Future<void> _remove(PronunciationRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove pronunciation?'),
        content: Text('Stop replacing "' + rule.pattern + '"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.store.deletePronunciationRule(rule.id);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rules.where((r) =>
        _bookScope ? r.bookId == widget.bookId : r.bookId == null).toList();
    final preview = const PronunciationTransformer().apply(
      _sample.text, _rules, bookId: widget.bookId,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Pronunciation dictionary')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('New rule'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
        children: [
          const Text('Corrections affect audio only, never the ebook text.'),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('This book')),
              ButtonSegment(value: false, label: Text('All books')),
            ],
            selected: {_bookScope},
            onSelectionChanged: (value) =>
                setState(() => _bookScope = value.single),
          ),
          const SizedBox(height: 16),
          Text(_bookScope ? widget.bookTitle : 'Global rules',
              style: Theme.of(context).textTheme.titleMedium),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No rules in this scope.'),
            ),
          for (final rule in visible)
            ListTile(
              leading: Icon(rule.enabled
                  ? Icons.record_voice_over : Icons.volume_off),
              title: Text(rule.pattern),
              subtitle: Text('Pronounce as: ' + rule.replacement +
                  (rule.wholeWord ? ' · whole word' : '')),
              onTap: () => _edit(rule),
              trailing: IconButton(
                tooltip: 'Delete rule',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(rule),
              ),
            ),
          const Divider(),
          Text('Try a replacement',
              style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _sample,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Example text'),
          ),
          const SizedBox(height: 12),
          SelectableText(preview),
          const SizedBox(height: 12),
          const Text('This text preview does not guarantee the sound of a '
              'voice. Book-specific rules override global matches.'),
        ],
      ),
    );
  }
}
