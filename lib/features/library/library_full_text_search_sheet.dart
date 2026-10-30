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

  void _openHit(LibraryFullTextHit hit) {
    final book = widget.store.getBook(hit.bookId);
    if (book == null) return;
    Navigator.of(context).pop();
    widget.onOpenBook?.call(book, hit.jump);
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
        ? widget.store.searchIndexedBookContents(_query) : <LibraryFullTextHit>[];
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
                TextField(
                  key: const ValueKey('fts-query'),
                  maxLength: 120,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Words in book contents',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    helperText: 'Up to 8 words; all words must occur in a book.',
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
