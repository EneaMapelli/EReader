import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/library_full_text.dart';

/// Explicit opt-in, offline text-layer search. No automatic indexing on
/// startup/import, and no network or user-content logging.
class LibraryFullTextSearchSheet extends StatefulWidget {
  const LibraryFullTextSearchSheet({
    super.key, required this.store, this.onOpenBook,
  });

  final LibraryStore store;
  final void Function(BookRecord, LibraryFullTextJump?)? onOpenBook;

  @override
  State<LibraryFullTextSearchSheet> createState() =>
      _LibraryFullTextSearchSheetState();
}

class _LibraryFullTextSearchSheetState
    extends State<LibraryFullTextSearchSheet> {
  String _query = '';
  LibraryFullTextMatchMode _matchMode = LibraryFullTextMatchMode.allWords;
  bool _running = false;
  bool _cancelRequested = false;
  int _done = 0;
  int _total = 0;
  String? _message;

  Future<void> _changeConsent(bool enabled) async {
    if (!enabled) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Disable full-text indexing?'),
          content: const Text(
            'Delete the local searchable copy of book text and stop '
            'indexing? Books and reading progress stay unchanged. '
            'Previously exported backups and recoverable SQLite '
            'filesystem remnants are not securely erased.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Delete index and disable'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      _cancelRequested = true;
    }
    try {
      widget.store.setFullTextIndexEnabled(enabled);
      if (mounted) setState(() => _message = enabled
          ? 'Enabled. Choose Index next 10 books to start.'
          : 'Full-text index removed and disabled.');
    } catch (_) {
      if (mounted) setState(() => _message =
          'Could not change the index. SQLite FTS5 may be unavailable.');
    }
  }

  Future<void> _indexNext() async {
    if (_running) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _done = 0;
      _total = 0;
      _message = null;
    });
    try {
      final result = await widget.store.indexNextFullTextBatch(
        maxBooks: 10,
        shouldCancel: () => _cancelRequested || !mounted,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _done = completed;
            _total = total;
          });
        },
      );
      if (mounted) {
        setState(() => _message = result.cancelled
            ? 'Indexing cancelled. ${result.indexed} indexed; '
                '${result.skipped} skipped.'
            : 'Indexed ${result.indexed}, skipped ${result.skipped}. '
                '${result.remaining} books remain unprocessed.');
      }
    } catch (_) {
      if (mounted) setState(() => _message =
          'Indexing stopped. Existing indexed books are preserved.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _checkChangedBooks() async {
    if (_running) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _done = 0;
      _total = 0;
      _message = null;
    });
    try {
      final count = await widget.store.refreshChangedFullTextBooks(
        shouldCancel: () => _cancelRequested || !mounted,
        onProgress: (checked, total) {
          if (!mounted) return;
          setState(() {
            _done = checked;
            _total = total;
          });
        },
      );
      if (mounted) {
        setState(() => _message = _cancelRequested
            ? 'Change check cancelled. $count books queued for re-indexing.'
            : '$count changed books queued. '
              'Select Index next 10 books to refresh them.');
      }
    } catch (_) {
      if (mounted) setState(() => _message =
          'Could not check changed books. Existing indexed text is preserved.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _resetIndex() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset full-text index?'),
        content: const Text(
          'Remove indexed excerpts and skipped-book markers, while '
          'keeping indexing enabled? You can re-index the library afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    widget.store.resetFullTextIndex();
    setState(() => _message = 'Index cleared. You can index again.');
  }

  void _openHit(LibraryFullTextHit hit, {
    LibraryFullTextJump? chosenJump,
  }) {
    final book = widget.store.getBook(hit.bookId);
    if (book == null) return;
    // Resolve while this sheet and its query are still mounted. Decode is
    // intentionally deferred to reader load, never performed by the list.
    final jump = chosenJump ??
        widget.store.fullTextJumpForHit(
          hit.bookId, _query, mode: _matchMode);
    Navigator.of(context).pop();
    widget.onOpenBook?.call(book, jump);
  }

  Future<void> _showPassages(LibraryFullTextHit hit) async {
    if (_running || !widget.store.isFullTextIndexEnabled) return;
    final queryAtStart = _query;
    final modeAtStart = _matchMode;
    setState(() => _message = 'Finding matching passages in this book...');
    List<LibraryFullTextPassage> passages;
    try {
      passages = await widget.store.fullTextPassagesForHit(
          hit.bookId, queryAtStart, mode: modeAtStart);
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not inspect this book\'s indexed passages.');
      }
      return;
    }
    if (!mounted) return;
    if (!widget.store.isFullTextIndexEnabled ||
        widget.store.getBook(hit.bookId) == null ||
        _query != queryAtStart || _matchMode != modeAtStart) {
      setState(() => _message = null);
      return;
    }
    setState(() => _message = null);
    if (passages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No source-exact passage is available for this book.'),
      ));
      return;
    }
    final chosen = await showDialog<LibraryFullTextJump>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Passages · ${hit.title}', maxLines: 2,
            overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 480,
          height: 350,
          child: ListView.builder(
            key: const ValueKey('fts-passage-list'),
            itemCount: passages.length,
            itemBuilder: (context, index) {
              final passage = passages[index];
              return ListTile(
                key: ValueKey('fts-passage-${hit.bookId}-$index'),
                title: Text(modeAtStart ==
                        LibraryFullTextMatchMode.exactPhrase
                    ? 'Exact phrase ${index + 1}'
                    : passage.allTermsNearby
                        ? 'Passage ${index + 1} · all terms nearby'
                        : 'Words far apart · first term'),
                subtitle: Text(passage.excerpt,
                    maxLines: 4, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(dialog).pop(passage.jump),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || chosen == null) return;
    _openHit(hit, chosenJump: chosen);
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.store.isFullTextIndexEnabled;
    final hits = enabled
        ? widget.store.searchIndexedBookContents(
            _query, mode: _matchMode) : <LibraryFullTextHit>[];
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Search inside books',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'Offline search in indexed TXT, EPUB and selectable PDF '
                'text. Scanned PDF pages require OCR. Open a result at '
                'its verified text match; changed books use the saved position.',
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('fts-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep a searchable copy on this device'),
                subtitle: const Text(
                    'Off by default; no book contents indexed without consent.'),
                value: enabled,
                onChanged: _changeConsent,
              ),
              if (enabled) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text('Indexed: ${widget.store.fullTextIndexedBooks}'
                          ' · Remaining: ${widget.store.fullTextPendingBooks}'),
                    ),
                    if (_running)
                      TextButton(
                        key: const ValueKey('fts-cancel'),
                        onPressed: () =>
                            setState(() => _cancelRequested = true),
                        child: const Text('Cancel batch'),
                      )
                    else
                      TextButton(
                        key: const ValueKey('fts-reset'),
                        onPressed: _resetIndex,
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                OutlinedButton.icon(
                  key: const ValueKey('fts-check-changes'),
                  onPressed: _running ? null : _checkChangedBooks,
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('Check changed books'),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  key: const ValueKey('fts-index-next'),
                  onPressed: _running || widget.store.fullTextPendingBooks == 0
                      ? null : _indexNext,
                  icon: const Icon(Icons.library_books_outlined),
                  label: const Text('Index next 10 books'),
                ),
                if (_running)
                  LinearProgressIndicator(
                    value: _total > 0 ? _done / _total : null,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('fts-mode-words'),
                      label: const Text('All words'),
                      selected: _matchMode == LibraryFullTextMatchMode.allWords,
                      onSelected: (selected) {
                        if (selected) setState(() =>
                            _matchMode = LibraryFullTextMatchMode.allWords);
                      },
                    ),
                    ChoiceChip(
                      key: const ValueKey('fts-mode-phrase'),
                      label: const Text('Exact phrase'),
                      selected: _matchMode ==
                          LibraryFullTextMatchMode.exactPhrase,
                      onSelected: (selected) {
                        if (selected) setState(() =>
                            _matchMode = LibraryFullTextMatchMode.exactPhrase);
                      },
                    ),
                  ],
                ),
                TextField(
                  key: const ValueKey('fts-query'),
                  maxLength: 120,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    labelText: 'Words in book contents',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    helperText: _matchMode ==
                            LibraryFullTextMatchMode.exactPhrase
                        ? 'Consecutive words in order; punctuation ignored.'
                        : 'Up to 8 words; all must occur in a book.',
                  ),
                ),
              ],
              if (_message != null) Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message!, key: const ValueKey('fts-status')),
              ),
              Expanded(
                child: !enabled
                    ? const Center(child: Text(
                        'Enable indexing, then choose when to index books.'))
                    : _query.trim().isEmpty
                        ? const Center(child: Text('Enter words to search.'))
                        : hits.isEmpty
                            ? const Center(child: Text(
                                'No matches in indexed books.'))
                            : ListView.builder(
                                key: const ValueKey('fts-results'),
                                itemCount: hits.length,
                                itemBuilder: (context, index) {
                                  final hit = hits[index];
                                  return ListTile(
                                    key: ValueKey('fts-hit-${hit.bookId}'),
                                    title: Text(hit.title),
                                    subtitle: Text(hit.excerpt,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis),
                                    onTap: widget.onOpenBook == null
                                        ? null : () => _openHit(hit),
                                    trailing: IconButton(
                                      key: ValueKey(
                                          'fts-passages-${hit.bookId}'),
                                      tooltip: 'Show matching passages',
                                      icon: const Icon(
                                          Icons.format_list_bulleted),
                                      onPressed: _running
                                          ? null : () => _showPassages(hit),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
