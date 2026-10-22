import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/book_decoder.dart';
import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/book_bookmark.dart';
import '../../domain/speech_segment.dart';
import '../../domain/book_search.dart';

/// Local, case-insensitive search over the text actually shown in the reader.
/// Returns the index of a speech segment, preserving the original anchor.
Future<int?> showBookSearch(
  BuildContext context,
  List<SpeechSegment> segments,
) async {
  final queryController = TextEditingController();
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, redraw) {
        final term = queryController.text.trim();
        final matches = findMatchingSegments(segments, term);
        return AlertDialog(
          title: const Text('Search in book'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: 550, maxHeight: 460, minWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: queryController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Find words in this book',
                  ),
                  onChanged: (_) => redraw(() {}),
                ),
                const SizedBox(height: 12),
                if (term.isNotEmpty)
                  Text(matches.isEmpty
                      ? 'No matches'
                      : matches.length == 100
                          ? 'First 100 matching segments'
                          : 'Matching segments: ' + matches.length.toString()),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final segmentId = matches[index];
                      final text = segments[segmentId].text;
                      return ListTile(
                        title: Text(
                          text.length > 160
                              ? text.substring(0, 160) + '…'
                              : text,
                          maxLines: 3,
                        ),
                        subtitle: Text(
                          'Segment ' + (segmentId + 1).toString(),
                        ),
                        onTap: () => Navigator.pop(dialogContext, segmentId),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
  queryController.dispose();
  return result;
}

/// Creates, lists, navigates to and removes bookmarks for one imported book.
/// The stored bookmark contains both the source anchor and fallback offset.
Future<int?> showBookBookmarks({
  required BuildContext context,
  required LibraryStore store,
  required BookRecord book,
  required DocumentContent document,
  required int currentOffset,
  required String currentExcerpt,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, redraw) {
        final bookmarks = store.listBookmarks(book.id);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text(
                        'Bookmarks',
                        style: TextStyle(fontSize: 20,
                            fontWeight: FontWeight.w600),
                      )),
                      FilledButton.icon(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save this position'),
                        onPressed: () async {
                          final suggested = currentExcerpt.trim().length > 55
                              ? currentExcerpt.trim().substring(0, 55) + '…'
                              : currentExcerpt.trim();
                          final titleController =
                              TextEditingController(text: suggested);
                          final title = await showDialog<String>(
                            context: sheetContext,
                            builder: (dialog) => AlertDialog(
                              title: const Text('Bookmark title'),
                              content: TextField(
                                controller: titleController,
                                autofocus: true,
                                maxLength: 200,
                                decoration: const InputDecoration(
                                  labelText: 'Title',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialog, titleController.text),
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                          titleController.dispose();
                          if (title == null || title.trim().isEmpty ||
                              !sheetContext.mounted) return;
                          try {
                            await store.addBookmark(BookBookmark(
                              id: DateTime.now().microsecondsSinceEpoch
                                      .toString() +
                                  '-' + Random.secure()
                                      .nextInt(1 << 30).toString(),
                              bookId: book.id,
                              title: title.trim(),
                              globalOffset: currentOffset,
                              anchor: document.anchorAt(
                                  book.format, currentOffset),
                              createdAt: DateTime.now().toUtc(),
                            ));
                            if (sheetContext.mounted) redraw(() {});
                          } catch (error) {
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(content: Text(
                                  'Cannot create bookmark: ' + error.toString(),
                                )),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  if (bookmarks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No bookmarks yet.'),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: bookmarks.length,
                      itemBuilder: (context, index) {
                        final mark = bookmarks[index];
                        final restored = mark.anchor == null
                            ? mark.globalOffset
                            : document.offsetOf(mark.anchor!) ??
                                mark.globalOffset;
                        return ListTile(
                          leading: const Icon(Icons.bookmark),
                          title: Text(mark.title),
                          subtitle: Text(
                            'Position ' + restored.toString(),
                          ),
                          onTap: () => Navigator.pop(sheetContext, restored),
                          trailing: IconButton(
                            tooltip: 'Delete bookmark',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await store.deleteBookmark(mark.id);
                              if (sheetContext.mounted) redraw(() {});
                            },
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
      },
    ),
  );
}
