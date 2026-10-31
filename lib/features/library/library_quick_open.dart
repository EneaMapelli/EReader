import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Clamp an arrow-key selection to the current visible result window.
/// Returning null avoids accidentally selecting a hidden previous result.
int? moveQuickOpenSelection({
  required int current,
  required int count,
  required bool down,
}) {
  if (count == 0) return null;
  return (current + (down ? 1 : -1)).clamp(0, count - 1).toInt();
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
  late final FocusNode _queryFocus =
      FocusNode(debugLabel: 'Quick open query', onKeyEvent: _onQueryKey);
  final ScrollController _resultsScroll = ScrollController();
  late QuickOpenBookResults _matches;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Arrow navigation only changes an index: never rescan thousands of
    // books for every keypress or for each highlight rebuild.
    _matches = findQuickOpenBooks(widget.books, '');
  }
  int _selectedIndex = 0;
  bool _usedArrowNavigation = false;
  double _rowExtent = 92;

  KeyEventResult _onQueryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Ignore auto-repeat so holding Escape cannot close the library route
      // underneath the dialog before the removal animation finishes.
      if (event is KeyDownEvent) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;

    final count = _matches.books.length;
    final next = moveQuickOpenSelection(
      current: _selectedIndex, count: count, down: down);
    if (next != null) {
      setState(() {
        _selectedIndex = next;
        _usedArrowNavigation = true;
      });
      _revealSelection();
    }
    return KeyEventResult.handled;
  }

  void _revealSelection() {
    if (!_resultsScroll.hasClients) return;
    final position = _resultsScroll.position;
    final top = _selectedIndex * _rowExtent;
    final bottom = top + _rowExtent;
    final current = position.pixels;
    final viewport = position.viewportDimension;
    final target = top < current
        ? top
        : bottom > current + viewport
            ? bottom - viewport
            : current;
    if ((target - current).abs() < 0.5) return;
    _resultsScroll.animateTo(
      target.clamp(0.0, position.maxScrollExtent).toDouble(),
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
    );
  }

  void _changeQuery(String value) {
    // New result sets must not inherit an offscreen selection or scroll.
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    setState(() {
      _query = value;
      _matches = findQuickOpenBooks(widget.books, value);
      _selectedIndex = 0;
      _usedArrowNavigation = false;
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocus.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final screen = MediaQuery.sizeOf(context);
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final listHeight = (screen.height - keyboardHeight - 300)
        .clamp(64.0, 320.0).toDouble();
    _rowExtent = MediaQuery.textScalerOf(context).scale(68) + 24;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('quick-open-query'),
              controller: _queryController,
              focusNode: _queryFocus,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: _changeQuery,
              onSubmitted: (value) {
                // Blank Enter must not unexpectedly open the first book.
                if ((value.trim().isNotEmpty || _usedArrowNavigation) &&
                    _selectedIndex < matches.books.length) {
                  Navigator.pop(context, matches.books[_selectedIndex]);
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
                          _changeQuery('');
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
            if (matches.books.isNotEmpty)
              Semantics(
                liveRegion: true,
                child: Text(
                  'Selected ${_selectedIndex + 1} of ${matches.books.length}: '
                  '${matches.books[_selectedIndex].title}',
                  key: const ValueKey('quick-open-selection'),
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Text('Up / Down to select · Enter to open · Esc to close',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SizedBox(
              height: listHeight,
              child: matches.books.isEmpty
                  ? const Center(
                      child: Text('No matching books. Try another title or author.'),
                    )
                  : ListView.builder(
                      key: const ValueKey('quick-open-results'),
                      controller: _resultsScroll,
                      itemExtent: _rowExtent,
                      itemCount: matches.books.length,
                      itemBuilder: (context, index) {
                        final book = matches.books[index];
                        return Semantics(
                          selected: index == _selectedIndex,
                          child: ListTile(
                          key: ValueKey('quick-open-book-' + book.id),
                          selected: index == _selectedIndex,
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
                          ),
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
