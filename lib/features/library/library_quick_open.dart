import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// A capped, deterministic search over local catalog metadata only.
///
/// Titles starting with the query rank before other title matches, then
/// author/series matches. Every term must occur in some metadata field.
/// Book contents and local file paths are never searched or uploaded.
class QuickOpenBookResults {
  const QuickOpenBookResults({required this.books, required this.total});

  final List<BookRecord> books;
  final int total;
  bool get truncated => total > books.length;
}

/// Scan the entire catalog before applying the UI cap: a relevant old title
/// must remain discoverable even after thousands of imports.
QuickOpenBookResults findQuickOpenBooks(
  Iterable<BookRecord> books,
  String query, {
  int limit = 40,
}) {
  if (limit < 1) throw RangeError.value(limit, 'limit', 'Must be positive');
  final normalized = query.trim().toLowerCase();
  final terms = normalized.split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty).toList();
  // Maintain only the top K items rather than storing and sorting every
  // matching book. Memory stays O(K) as the local catalog grows.
  final ranked = <(int, BookRecord)>[];
  var total = 0;

  int compareMatches((int, BookRecord) a, (int, BookRecord) b) {
    final rankOrder = a.$1.compareTo(b.$1);
    if (rankOrder != 0) return rankOrder;
    if (normalized.isEmpty && a.$1 == 0) {
      final recent = b.$2.lastOpenedAt!.compareTo(a.$2.lastOpenedAt!);
      if (recent != 0) return recent;
    }
    final titleOrder = a.$2.title.toLowerCase()
        .compareTo(b.$2.title.toLowerCase());
    if (titleOrder != 0) return titleOrder;
    return a.$2.id.compareTo(b.$2.id);
  }

  for (final book in books) {
    final title = book.title.toLowerCase();
    final author = (book.author ?? '').toLowerCase();
    final series = (book.series ?? '').toLowerCase();
    if (terms.isNotEmpty &&
        !terms.every((term) =>
            title.contains(term) ||
            author.contains(term) ||
            series.contains(term))) {
      continue;
    }

    final rank = normalized.isEmpty
        ? (book.lastOpenedAt == null ? 1 : 0)
        : title.startsWith(normalized)
            ? 0
            : title.contains(normalized)
                ? 1
                : author.startsWith(normalized) ||
                        series.startsWith(normalized)
                    ? 2
                    : 3;
    total++;
    final candidate = (rank, book);
    var low = 0;
    var high = ranked.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (compareMatches(candidate, ranked[mid]) > 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low < limit) {
      ranked.insert(low, candidate);
      if (ranked.length > limit) ranked.removeLast();
    }
  }
  return QuickOpenBookResults(
    books: List<BookRecord>.unmodifiable(
      ranked.map((match) => match.$2),
    ),
    total: total,
  );
}

/// Returns a chosen existing book. Only the caller may open the reader;
/// typing or dismissing this dialog cannot mutate books or play TTS.
Future<BookRecord?> showQuickOpenBookDialog(
  BuildContext context, {
  required List<BookRecord> books,
}) {
  return showDialog<BookRecord>(
    context: context,
    builder: (dialogContext) => _QuickOpenBookDialog(books: books),
  );
}

class _QuickOpenBookDialog extends StatefulWidget {
  const _QuickOpenBookDialog({required this.books});

  final List<BookRecord> books;

  @override
  State<_QuickOpenBookDialog> createState() => _QuickOpenBookDialogState();
}

class _QuickOpenBookDialogState extends State<_QuickOpenBookDialog> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = findQuickOpenBooks(widget.books, _query);
    final screen = MediaQuery.sizeOf(context);
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final listHeight = (screen.height - keyboardHeight - 300)
        .clamp(64.0, 320.0).toDouble();
    final countText = matches.truncated
        ? 'Showing ' + matches.books.length.toString() + ' of ' +
            matches.total.toString() + ' books'
        : matches.total.toString() +
            (matches.total == 1 ? ' book found' : ' books found');

    return AlertDialog(
      // The outer content can scroll above a mobile keyboard or when
      // accessibility fonts make even the bounded result list too tall.
      scrollable: true,
      title: const Text('Quick open book'),
      content: SizedBox(
        width: 480,
        height: listHeight + 115,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('quick-open-query'),
              controller: _queryController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) {
                // Blank Enter must not unexpectedly open the first book.
                if (value.trim().isNotEmpty && matches.books.isNotEmpty) {
                  Navigator.pop(context, matches.books.first);
                }
              },
              decoration: InputDecoration(
                labelText: 'Book title, author or series',
                hintText: 'Type to find a book',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear quick search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _queryController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                countText,
                key: const ValueKey('quick-open-count'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: matches.books.isEmpty
                  ? const Center(
                      child: Text('No matching books. Try another title or author.'),
                    )
                  : ListView.builder(
                      key: const ValueKey('quick-open-results'),
                      itemCount: matches.books.length,
                      itemBuilder: (context, index) {
                        final book = matches.books[index];
                        return ListTile(
                          key: ValueKey('quick-open-book-' + book.id),
                          dense: true,
                          leading: Icon(switch (book.format) {
                            BookFormat.epub => Icons.auto_stories_outlined,
                            BookFormat.pdf => Icons.picture_as_pdf_outlined,
                            BookFormat.txt => Icons.description_outlined,
                          }),
                          title: Text(book.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (book.author != null) book.author!,
                              if (book.series != null) book.series!,
                              book.format.name.toUpperCase(),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, book),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
