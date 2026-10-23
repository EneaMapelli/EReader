import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/secret_vault.dart';
import '../../data/book_decoder.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/cast_span.dart';
import '../../domain/speech_segment.dart';
import '../../domain/voice_cast.dart';
import '../../llm/dialogue_analysis_plan.dart';
import '../../llm/openai_dialogue_analyzer.dart';

/// Intentional one-window-at-a-time analysis. Opening this screen, choosing
/// scope/model or saving a key NEVER sends any book text to the network.
class DialogueAnalysisScreen extends StatefulWidget {
  const DialogueAnalysisScreen({
    super.key,
    required this.store,
    required this.book,
    required this.document,
    required this.segments,
    required this.vault,
  });

  final LibraryStore store;
  final BookRecord book;
  final DocumentContent document;
  final List<SpeechSegment> segments;
  final SpeechSecretVault vault;

  @override
  State<DialogueAnalysisScreen> createState() => _DialogueAnalysisScreenState();
}

class _DialogueAnalysisScreenState extends State<DialogueAnalysisScreen> {
  static const planner = DialogueAnalysisPlanner();
  late List<DialogueAnalysisScope> _scopes;
  late List<CastCharacter> _cast;
  late OpenAiDialogueAnalyzer _analyzer;
  int _scopeIndex = 0;
  int? _nextFrom;
  bool _limitToReadingPosition = true;
  int _previousContextChars = 0;
  String _model = 'gpt-5.4-mini';
  bool _busy = false;
  bool _keySaved = false;
  String? _notice;
  final _key = TextEditingController();
  final _limit = TextEditingController(text: '25000');

  @override
  void initState() {
    super.initState();
    _scopes = planner.scopes(widget.book.format, widget.document);
    _cast = widget.store.listCastCharacters(widget.book.id);
    _analyzer = OpenAiDialogueAnalyzer(
      access: widget.store, vault: widget.vault,
    );
    final consent = widget.store.getLlmAnalysisConsent(widget.book.id);
    if (consent.maxInputCharacters > 0) {
      _limit.text = consent.maxInputCharacters.toString();
    }
    _checkKey();
  }

  @override
  void dispose() {
    _analyzer.dispose();
    _key.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    try {
      final value = await widget.vault.readKey(
        OpenAiDialogueAnalyzer.keyNamespace,
      );
      if (mounted) setState(() => _keySaved = value?.isNotEmpty ?? false);
    } catch (error) {
      if (mounted) setState(() => _notice = 'Secure storage unavailable');
    }
  }

  void _message(String text) {
    if (mounted) setState(() => _notice = text);
  }

  DialogueAnalysisWindow? _previewWindow() {
    if (_scopes.isEmpty || _cast.isEmpty) return null;
    final scope = _scopes[_scopeIndex];
    final latest = widget.store.getBook(widget.book.id) ?? widget.book;
    final position = latest.progressAnchor == null
        ? latest.progressOffset
        : widget.document.offsetOf(latest.progressAnchor!) ??
            latest.progressOffset;
    final spoilerCeiling = _limitToReadingPosition
        ? position.clamp(0, scope.end).toInt()
        : scope.end;
    if (spoilerCeiling <= scope.start ||
        (_nextFrom != null && _nextFrom! >= spoilerCeiling)) return null;
    try {
      return planner.makeWindow(
        bookId: widget.book.id,
        content: widget.document,
        scope: scope,
        from: _nextFrom ?? scope.start,
        segments: widget.segments,
        cast: _cast,
        spoilerCeiling: spoilerCeiling,
        contextChars: _previousContextChars,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _saveKey() async {
    if (_busy) return;
    try {
      await widget.vault.saveKey(
        OpenAiDialogueAnalyzer.keyNamespace, _key.text);
      _key.clear();
      await _checkKey();
      _message('Analysis key saved in device secure storage.');
    } catch (_) {
      _message('Unable to save the separate analysis key.');
    }
  }

  Future<void> _deleteKey() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete analysis API key?'),
        content: const Text(
          'Future dialogue-analysis requests will be blocked until '
          'you save another key. This does not remove prior suggestions.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete')),
        ],
      ),
    );
    if (allowed != true) return;
    try {
      await widget.vault.deleteKey(
        OpenAiDialogueAnalyzer.keyNamespace);
      await _checkKey();
    } catch (_) {
      _message('Could not delete analysis credential.');
    }
  }

  Future<void> _changeConsent(bool allowed) async {
    if (_busy) return;
    final max = int.tryParse(_limit.text);
    final existing = widget.store.getLlmAnalysisConsent(widget.book.id);
    if (max == null || max < existing.usedInputCharacters ||
        max > 10000000 || max < 1) {
      _message('Enter a valid limit above previous input consumption.');
      return;
    }
    if (allowed) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Allow remote character analysis?'),
          content: Text(
            'Only the passages of this book that you explicitly choose '
            'for analysis will be sent to the OpenAI Responses API, along '
            'with existing character names and aliases. '
            'The local limit is $max input characters including prompt '
            'instructions; API billing uses tokens and also charges for '
            'generated output. This limit is NOT a spending cap. '
            'No request is made by giving consent; each analysis '
            'window requires a separate confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep disabled'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Authorize analysis'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      await widget.store.configureLlmAnalysisConsent(
        widget.book.id, allowed: allowed, maxInputCharacters: max,
      );
      if (mounted) {
        setState(() {});
        _message(allowed
            ? 'Analysis authorized. No book text has been sent.'
            : 'Analysis disabled for this book.');
      }
    } catch (error) {
      _message('Permission update failed: ' + error.toString());
    }
  }

  Future<void> _analyzeSelected() async {
    if (_busy) return;
    final window = _previewWindow();
    if (window == null) {
      _message('Choose a nonempty scope and create known characters first.');
      return;
    }
    final estimatedChars = _analyzer.requestedCharacters(window);
    final consent = widget.store.getLlmAnalysisConsent(widget.book.id);
    if (!consent.allowed || estimatedChars >
        consent.remainingInputCharacters || !_keySaved) {
      _message('Enable analysis, provide a key and check the remaining quota.');
      return;
    }
    final excerpt = window.excerpt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Send this excerpt for analysis?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scope: ' + window.scope.title),
              Text('Model: ' + _model),
              Text('Passages: ' + window.segments.length.toString()),
              Text('Spoiler cutoff (UTF-16): ' +
                  window.effectiveCeiling.toString()),
              Text('Earlier context: ' +
                  window.contextExcerpt.length.toString() + ' characters'),
              Text('Local input budget reservation: ' +
                  estimatedChars.toString() + ' characters'),
              const SizedBox(height: 10),
              if (window.contextSegments.isNotEmpty) ...[
                const Text(
                  'Earlier context sent for speaker disambiguation:'),
                SelectableText(window.contextExcerpt, maxLines: 8),
                const SizedBox(height: 8),
              ],
              const Text('Target excerpt sent (cast names are sent too):'),
              SelectableText(excerpt, maxLines: 12),
              const SizedBox(height: 12),
              const Text(
                'The generated suggestions will NOT be applied or spoken '
                'until you approve them individually in Voice Cast / Review.',
              ),
            ],
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Send only this excerpt')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final raw = await _analyzer.analyze(window, model: _model);
      final proposed = planner.materializeProposals(
        bookId: widget.book.id,
        source: widget.document.text,
        window: window,
        proposals: raw,
        idPrefix: 'llm-' +
            DateTime.now().microsecondsSinceEpoch.toString() + '-' +
            Random.secure().nextInt(1 << 30).toString(),
      );
      final anchored = [
        for (final item in proposed)
          CastSpan(
            id: item.id, bookId: item.bookId,
            start: item.start, end: item.end,
            sourceDigest: item.sourceDigest,
            speakerId: item.speakerId,
            confidence: item.confidence,
            status: CastSpanStatus.proposed,
            origin: CastSpanOrigin.llm,
            lockedByUser: false,
            evidence: item.evidence,
            anchor: widget.document.anchorAt(
              widget.book.format, item.start),
          ),
      ];
      await widget.store.importCastProposals(
          anchored, widget.document.text);
      if (mounted) {
        setState(() {});
        _message('Stored ' + anchored.length.toString() +
            ' unapproved suggestions. Review them before voice casting.');
      }
    } catch (error) {
      _message('Analysis failed; any attempted input remains counted. ' +
          error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _nextWindow() {
    final current = _previewWindow();
    if (current == null) return;
    setState(() {
      _nextFrom = current.segments.last.end;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final permission = widget.store.getLlmAnalysisConsent(widget.book.id);
    final window = _previewWindow();
    return Scaffold(
      appBar: AppBar(title: const Text('AI dialogue analysis')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
        children: [
          const Text('OFF by default. Analysis sends only the chosen '
              'excerpt and existing cast names, never the entire book '
              'automatically. Responses are proposed speaker labels and '
              'require individual human review.'),
          const SizedBox(height: 18),
          Text('Analysis scope',
              style: Theme.of(context).textTheme.titleMedium),
          if (_scopes.isEmpty)
            const Text('This document has no analysable text ranges.'),
          if (_scopes.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _scopeIndex,
              decoration: const InputDecoration(
                labelText: 'Choose chapter, page or text range'),
              items: [
                for (var i = 0; i < _scopes.length; i++)
                  DropdownMenuItem(
                    value: i, child: Text(_scopes[i].title,
                      overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (index) {
                if (index != null) setState(() {
                  _scopeIndex = index;
                  _nextFrom = null;
                });
              },
            ),
          SwitchListTile(
            title: const Text('Spoiler-safe: stop at my saved reading position'),
            subtitle: const Text(
              'On by default. Turning this off explicitly allows the '
              'selected chapter/page through its end; never later scopes.',
            ),
            value: _limitToReadingPosition,
            onChanged: _busy ? null : (value) => setState(() {
              _limitToReadingPosition = value;
              _nextFrom = null;
            }),
          ),
          DropdownButtonFormField<int>(
            value: _previousContextChars,
            decoration: const InputDecoration(
              labelText: 'Earlier context in this scope',
              helperText: 'No future text. Included in preview and quota.',
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('No extra context')),
              DropdownMenuItem(value: 400, child: Text('Up to 400 characters')),
              DropdownMenuItem(value: 900, child: Text('Up to 900 characters')),
            ],
            onChanged: _busy ? null : (value) {
              if (value != null) setState(() => _previousContextChars = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _model,
            decoration: const InputDecoration(labelText: 'Analysis model'),
            items: [
              for (final model in OpenAiDialogueAnalyzer.supportedModels)
                DropdownMenuItem(value: model, child: Text(model)),
            ],
            onChanged: _busy ? null : (model) {
              if (model != null) setState(() => _model = model);
            },
          ),
          const SizedBox(height: 14),
          Text('Known characters: ' + _cast.length.toString()),
          if (_cast.isEmpty)
            const Text('Add characters in Voice Cast before using analysis. '
                'The model cannot create new speaker identities.'),
          if (_limitToReadingPosition)
            const Text(
              'If no passage is available, read farther in the book or '
              'explicitly turn off the saved-position cutoff above.',
            ),
          if (window != null) ...[
            Text('Next window: ' + window.segments.length.toString() +
                ' passages, ' + window.excerpt.length.toString() +
                ' excerpt characters; earlier context: ' +
                window.contextExcerpt.length.toString() + ' characters'),
            OutlinedButton(
              onPressed: _busy ? null : _nextWindow,
              child: const Text('Skip to next window in this scope'),
            ),
          ] else
            const Text('No more passages in the selected scope. '
                'Choose another scope to continue.'),
          const Divider(height: 30),
          Text('Separate API credential',
              style: Theme.of(context).textTheme.titleMedium),
          Text(_keySaved
              ? 'An analysis API key is saved on this device.'
              : 'No analysis key saved. Narration keys are separate.'),
          TextField(
            controller: _key,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Analysis API key'),
          ),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: _busy ? null : _saveKey,
              child: const Text('Save analysis key securely'),
            ),
            if (_keySaved)
              OutlinedButton(
                onPressed: _busy ? null : _deleteKey,
                child: const Text('Delete key'),
              ),
          ]),
          const Divider(height: 30),
          Text('Book privacy permission and input budget',
              style: Theme.of(context).textTheme.titleMedium),
          Text(permission.allowed
              ? 'Authorized for selected excerpts of this book.'
              : 'Disabled. No analysis text may be sent.'),
          Text('Reserved input: ' +
              permission.usedInputCharacters.toString() +
              ' / ' + permission.maxInputCharacters.toString()),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'Local maximum attempted input characters',
              helperText: 'Provider billing is by tokens, including output.',
            ),
          ),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: _busy ? null : () => _changeConsent(true),
              child: Text(permission.allowed
                  ? 'Update analysis permission'
                  : 'Review and enable analysis'),
            ),
            if (permission.allowed)
              OutlinedButton(
                onPressed: _busy ? null : () => _changeConsent(false),
                child: const Text('Disable analysis for this book'),
              ),
          ]),
          const Divider(height: 30),
          FilledButton.icon(
            icon: const Icon(Icons.psychology_alt_outlined),
            onPressed: _busy || window == null || _cast.isEmpty
                ? null : _analyzeSelected,
            label: Text(_busy ? 'Analysing selected excerpt…'
                : 'Preview and analyse selected excerpt'),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SelectableText(_notice!),
            ),
          const SizedBox(height: 10),
          const Text('Generated suggestions remain local and inactive '
              'until reviewed in Voice Cast / Review. This character '
              'budget is NOT a monetary spending cap.'),
        ],
      ),
    );
  }
}
