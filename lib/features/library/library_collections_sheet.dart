import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/book_collection.dart';
import 'smart_collection_editor.dart';

/// Collection changes stay local. They never seek, start TTS, or move files.
Future<String?> _askCollectionName(
    BuildContext context, {String? initialName}) async {
  var name = initialName ?? '';
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(initialName == null ? 'New collection' : 'Rename collection'),
      content: TextFormField(
        key: const ValueKey('collection-name-input'),
        initialValue: name,
        onChanged: (value) => name = value,
        maxLength: 80,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Collection name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, name),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Cannot change collection: $error')),
  );
}

/// Global collection management; deletes only the classification,
/// not the books or any of their narration/reading state.
Future<void> showManageBookCollections({
  required BuildContext context,
  required LibraryStore store,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, redraw) {
        final items = store.collections;
        final smartItems = store.smartCollections;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text(
                        'Collections',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      )),
                      FilledButton.tonalIcon(
                        key: const ValueKey('collection-smart-create'),
                        onPressed: () async {
                          final input = await showSmartCollectionEditor(sheet);
                          if (input == null || !sheet.mounted) return;
                          try {
                            store.createSmartCollection(input.name, input.rule);
                            redraw(() {});
                          } catch (error) {
                            if (sheet.mounted) _showError(sheet, error);
                          }
                        },
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Smart'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('collection-create'),
                        onPressed: () async {
                          final name = await _askCollectionName(sheet);
                          if (name == null || !sheet.mounted) return;
                          try {
                            store.createCollection(name);
                            redraw(() {});
                          } catch (error) {
                            if (sheet.mounted) _showError(sheet, error);
                          }
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                  if (items.isEmpty && smartItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No collections yet. Create one to organize your books.'),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length + smartItems.length,
                      itemBuilder: (context, index) {
                        if (index >= items.length) {
                          final item = smartItems[index - items.length];
                          final count =
                              store.smartCollectionBookIds(item.id).length;
                          return ListTile(
                            key: ValueKey('smart-row-${item.id}'),
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: Text(item.name),
                            subtitle: Text('$count books · dynamic filters'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit smart collection',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    final input = await showSmartCollectionEditor(
                                        sheet, existing: item);
                                    if (input == null || !sheet.mounted) return;
                                    try {
                                      store.updateSmartCollection(
                                          item.id, input.name, input.rule);
                                      redraw(() {});
                                    } catch (error) {
                                      if (sheet.mounted) _showError(sheet, error);
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete smart collection',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final approved = await showDialog<bool>(
                                      context: sheet,
                                      builder: (dialog) => AlertDialog(
                                        title: const Text(
                                            'Delete smart collection?'),
                                        content: Text(
                                          'Delete "${item.name}" rules? '
                                          'Books and manual collections '
                                          'will not be deleted.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialog, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(dialog, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (approved != true || !sheet.mounted) {
                                      return;
                                    }
                                    try {
                                      store.deleteSmartCollection(item.id);
                                      redraw(() {});
                                    } catch (error) {
                                      if (sheet.mounted) _showError(sheet, error);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }
                        final item = items[index];
                        final count = store.collectionBookIds(item.id).length;
                        return ListTile(
                          key: ValueKey('collection-row-${item.id}'),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(item.name),
                          subtitle: Text('$count books'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Rename collection',
                                onPressed: () async {
                                  final name = await _askCollectionName(
                                      sheet, initialName: item.name);
                                  if (name == null || !sheet.mounted) return;
                                  try {
                                    store.renameCollection(item.id, name);
                                    redraw(() {});
                                  } catch (error) {
                                    if (sheet.mounted) _showError(sheet, error);
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete collection',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: sheet,
                                    builder: (dialog) => AlertDialog(
                                      title: const Text('Delete collection?'),
                                      content: Text(
                                        'Remove "${item.name}" and its book '
                                        'assignments? Books will not be deleted.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true || !sheet.mounted) return;
                                  try {
                                    store.deleteCollection(item.id);
                                    redraw(() {});
                                  } catch (error) {
                                    if (sheet.mounted) _showError(sheet, error);
                                  }
                                },
                              ),
                            ],
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

/// One book can belong to any number of collections. Membership toggles
/// update only the join table; opening the sheet never changes reading state.
Future<void> showBookCollectionMembership({
  required BuildContext context,
  required LibraryStore store,
  required String bookId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, redraw) {
        final collections = store.collections;
        final assigned = store.listBookCollections(bookId)
            .map((entry) => entry.id).toSet();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text(
                        'Book collections',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      )),
                      FilledButton.icon(
                        key: const ValueKey('book-collection-create'),
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('New'),
                        onPressed: () async {
                          final name = await _askCollectionName(sheet);
                          if (name == null || !sheet.mounted) return;
                          try {
                            final collection = store.createCollection(name);
                            store.setBookCollection(bookId, collection.id, true);
                            redraw(() {});
                          } catch (error) {
                            if (sheet.mounted) _showError(sheet, error);
                          }
                        },
                      ),
                    ],
                  ),
                  if (collections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No collections yet.'),
                    ),
                  if (store.smartCollections.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Smart collections assign books '
                          'automatically and cannot be edited here.'),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: collections.length,
                      itemBuilder: (context, index) {
                        final item = collections[index];
                        return CheckboxListTile(
                          key: ValueKey('book-collection-${item.id}'),
                          title: Text(item.name),
                          value: assigned.contains(item.id),
                          onChanged: (value) {
                            if (value == null) return;
                            try {
                              store.setBookCollection(bookId, item.id, value);
                              redraw(() {});
                            } catch (error) {
                              if (sheet.mounted) _showError(sheet, error);
                            }
                          },
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
