import 'package:flutter/material.dart';

import '../../data/book_decoder.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/cast_span.dart';
import '../../domain/dialogue_turn_review.dart';
import '../../domain/voice_cast.dart';
import '../../llm/dialogue_analysis_plan.dart';

/// Bounded local review of complex conversations. No AI requests.
class DialogueTurnReviewScreen extends StatefulWidget {
  const DialogueTurnReviewScreen({
    super.key,
    required this.store,
    required this.book,
    required this.document,
  });

  final LibraryStore store;
  final BookRecord book;
  final DocumentContent document;

  @override
  State<DialogueTurnReviewScreen> createState() =>
      _DialogueTurnReviewScreenState();
}

class _DialogueTurnReviewScreenState extends State<DialogueTurnReviewScreen> {
  late final List<DialogueAnalysisScope> _scopes;
  String? _scopeId;
  int _position = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scopes = const DialogueAnalysisPlanner().scopes(
      widget.book.format, widget.document);
    if (_scopes.isNotEmpty) {
      _scopeId = _scopes.first.id;
      _position = _scopes.first.start;
    }
  }

  int _safeBoundary(int offset, {required int minimum, required int maximum}) {
    var result = offset.clamp(minimum, maximum).toInt();
    if (result > 0 && result < widget.document.text.length &&
        widget.document.text.codeUnitAt(result) >= 0xDC00 &&
        widget.document.text.codeUnitAt(result) <= 0xDFFF) {
      result = result == maximum ? result - 1 : result + 1;
    }
    return result;
  }

  Future<void> _label(DialogueReviewTurn turn,
      List<CastCharacter> people) async {
    String? choice;
    final decision = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) => AlertDialog(
          title: const Text('Label this exact dialogue turn'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(turn.text, maxLines: 8),
                  const SizedBox(height: 12),
                  const Text('No speaker is inferred. Select the person who '
                      'spoke this specific quotation, or explicitly choose '
                      'narrator. The book text is not modified.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: choice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Manually confirmed speaker'),
                    items: [
                      const DropdownMenuItem(
                        value: 'narrator', child: Text('Narrator / unknown')),
                      for (final person in people)
                        DropdownMenuItem(
                          value: person.id,
                          child: Text(person.name,
                              overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) => refresh(() => choice = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
            FilledButton(
              onPressed: choice == null
                  ? null : () => Navigator.pop(dialog, choice),
              child: const Text('Save manual label')),
          ],
        ),
      ),
    );
    if (!mounted || decision == null) return;
    setState(() => _saving = true);
    try {
      final person = decision == 'narrator' ? null : decision;
      final span = CastSpan(
        id: 'manual-turn-' +
            DateTime.now().microsecondsSinceEpoch.toString() + '-' +
            turn.start.toString(),
        bookId: widget.book.id,
        start: turn.start,
        end: turn.end,
        sourceDigest: CastSpan.digest(turn.text),
        speakerId: person,
        origin: CastSpanOrigin.user,
        status: CastSpanStatus.accepted,
        lockedByUser: true,
        anchor: widget.document.anchorAt(
          widget.book.format, turn.start),
      );
      await widget.store.saveManualCastSpan(span, widget.document.text);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manual labeling failed: ' + error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scopes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review complex conversations')),
        body: const Center(child: Text('No readable source scopes available')),
      );
    }
    final scope = _scopes.firstWhere((s) => s.id == _scopeId);
    final start = _safeBoundary(_position,
        minimum: scope.start, maximum: scope.end);
    final end = _safeBoundary(
      (start + DialogueTurnReviewPlanner.maxWindowChars)
          .clamp(scope.start, scope.end).toInt(),
      minimum: start, maximum: scope.end,
    );
    final people = widget.store.listCastCharacters(widget.book.id);
    final names = {for (final person in people) person.id: person.name};
    final turns = const DialogueTurnReviewPlanner().build(
      bookId: widget.book.id,
      source: widget.document.text,
      from: start,
      to: end,
      reachesScopeEnd: end == scope.end,
      precise: widget.store.listCastSpans(widget.book.id),
      legacy: widget.store.listSegmentCast(widget.book.id),
      offsetFromAnchor: widget.document.offsetOf,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Review complex conversations')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 64),
        children: [
          const Text(
            'Source-exact review of quoted speech, interrupted turns '
            'and partially attributed passages. No voices are guessed. '
            'Only an explicit manual label changes playback; previously '
            'locked tags cannot be overwritten silently.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _scopeId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Chapter / page / text range'),
            items: [
              for (final item in _scopes)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _saving ? null : (value) {
              if (value == null) return;
              setState(() {
                _scopeId = value;
                _position = _scopes.firstWhere((s) => s.id == value).start;
              });
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_left),
              onPressed: _saving || start <= scope.start ? null : () =>
                  setState(() => _position = (start -
                    DialogueTurnReviewPlanner.maxWindowChars)
                    .clamp(scope.start, scope.end).toInt()),
              label: const Text('Previous')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_right),
              onPressed: _saving || end >= scope.end ? null : () =>
                  setState(() => _position = end),
              label: const Text('Next')),
          ]),
          Text('Original source offsets: ' + start.toString() + '–' +
              end.toString() + ' · ' + turns.length.toString() +
              ' dialogue fragments in this window'),
          if (turns.length == DialogueTurnReviewPlanner.maxTurns)
            const Text('Maximum review count reached. '
                'Use a smaller selected window for later turns.'),
          if (turns.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No recognized dialogue delimiters in this range. '
                  'This does not prove the text contains no dialogue.')),
          for (final turn in turns)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      turn.delimiter.name + ' · ' + turn.ending.name +
                      ' · ' + turn.start.toString() + '–' +
                      turn.end.toString(),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(turn.text, maxLines: 7),
                    if (turn.hasConflicts)
                      const Text('Conflict: incompatible accepted voices '
                          'overlap; both need manual inspection.'),
                    if (turn.hasMultipleConfirmedSpeakers)
                      const Text('Multiple confirmed voices inside one '
                          'dialogue turn. Check interruption boundaries.'),
                    if (turn.isPartiallyAttributed)
                      const Text('Partially labeled: unassigned text '
                          'continues to use narrator fallback.'),
                    for (final piece in turn.labels)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          piece.state.name + ': ' +
                          (piece.speakerId == null ? '—' :
                              (names[piece.speakerId] ?? 'Unknown ID')) +
                          ' · ' +
                          widget.document.text.substring(
                            piece.start,
                            piece.end,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (turn.labels.isNotEmpty &&
                        turn.labels.every((p) =>
                            p.state == DialogueLabelState.unknown) &&
                        turn.ending != DialogueEnd.openOrTruncated)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          onPressed: _saving
                              ? null : () => _label(turn, people),
                          label: const Text('Label this turn manually'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
