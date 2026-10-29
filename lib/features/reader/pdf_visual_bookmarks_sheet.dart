import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/pdf_visual_bookmark.dart';

/// Page-only bookmarks for the faithful PDF viewer. Never creates a
/// source text checkpoint or a speech segment, including on scanned PDFs.
/// Returns a physical page number to the caller; it owns native page jumps.
Future<int?> showPdfVisualBookmarks({
  required BuildContext context,
  required LibraryStore store,
  required String bookId,
  required int currentPage,
  required int pageCount,
}) {
  if (pageCount < 1) return Future<int?>.value(null);
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, redraw) {
        final marks = store.listPdfVisualBookmarks(bookId);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PDF page bookmarks',
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('pdf-bookmark-add'),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save page'),
                        onPressed: currentPage >= 1 && currentPage <= pageCount
                            ? () async {
                                final controller = TextEditingController(
                                    text: 'Page $currentPage');
                                String? title;
                                try {
                                  title = await showDialog<String>(
                                    context: sheetContext,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Bookmark this page'),
                                      content: TextField(
                                        key: const ValueKey('pdf-bookmark-title'),
                                        controller: controller,
                                        autofocus: true,
                                        maxLength: 200,
                                        decoration: const InputDecoration(
                                          labelText: 'Title',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext, controller.text),
                                          child: const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  );
                                } finally {
                                  controller.dispose();
                                }
                                if (!sheetContext.mounted || title == null ||
                                    title.trim().isEmpty) return;
                                try {
                                  store.addPdfVisualBookmark(
                                    PdfVisualBookmark(
                                      id: '${DateTime.now().microsecondsSinceEpoch}-'
                                          '${Random.secure().nextInt(1 << 30)}',
                                      bookId: bookId,
                                      title: title.trim(),
                                      pageNumber: currentPage,
                                      createdAt: DateTime.now().toUtc(),
                                    ),
                                  );
                                  if (sheetContext.mounted) redraw(() {});
                                } catch (_) {
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(sheetContext)
                                        .showSnackBar(const SnackBar(
                                      content: Text('Cannot save PDF bookmark'),
                                    ));
                                  }
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  if (marks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No saved PDF pages yet.'),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: marks.length,
                      itemBuilder: (context, index) {
                        final mark = marks[index];
                        final available = mark.pageNumber <= pageCount;
                        return ListTile(
                          leading: Icon(available
                              ? Icons.bookmark
                              : Icons.warning_amber_outlined),
                          title: Text(mark.title),
                          subtitle: Text(available
                              ? 'Page ${mark.pageNumber} of $pageCount'
                              : 'Page ${mark.pageNumber} is not in this PDF'),
                          onTap: available
                              ? () => Navigator.pop(
                                  sheetContext, mark.pageNumber)
                              : null,
                          trailing: IconButton(
                            tooltip: 'Delete PDF page bookmark',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              store.deletePdfVisualBookmark(bookId, mark.id);
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
