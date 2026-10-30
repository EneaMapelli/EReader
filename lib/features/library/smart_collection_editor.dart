import 'package:flutter/material.dart';

import '../../domain/book.dart';
import '../../domain/book_collection.dart';
import '../../domain/library_catalog.dart';
import '../../domain/smart_book_collection.dart';

/// Edits saved catalog metadata rules; it never reads book content or
/// changes library membership. Invalid rules remain in the dialog.
Future<({String name, SmartBookCollectionRule rule})?> showSmartCollectionEditor(
  BuildContext context, {
  SmartBookCollection? existing,
}) {
  var name = existing?.name ?? '';
  var query = existing?.rule.query ?? '';
  BookFormat? format = existing?.rule.format;
  var favoritesOnly = existing?.rule.favoritesOnly ?? false;
  BookReadingStatus? readingStatus = existing?.rule.readingStatus;
  var activity = existing?.rule.activity ?? LibraryActivityFilter.all;
  String? error;

  return showDialog<({String name, SmartBookCollectionRule rule})>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, redraw) => AlertDialog(
        title: Text(existing == null
            ? 'New smart collection' : 'Edit smart collection'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Books matching these filters appear automatically. '
                    'This does not change manual collections or index book text.'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('smart-name'),
                  initialValue: name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Collection name'),
                  onChanged: (value) => name = value,
                ),
                TextFormField(
                  key: const ValueKey('smart-query'),
                  initialValue: query,
                  maxLength: 256,
                  decoration: const InputDecoration(
                    labelText: 'Search title, author or series',
                    helperText: 'Optional; supports title:, author:, quotes',
                  ),
                  onChanged: (value) => query = value,
                ),
                DropdownButtonFormField<BookFormat>(
                  key: const ValueKey('smart-format'),
                  initialValue: format,
                  decoration: const InputDecoration(labelText: 'Book format'),
                  items: [
                    const DropdownMenuItem<BookFormat>(
                        value: null, child: Text('Any format')),
                    for (final option in BookFormat.values)
                      DropdownMenuItem<BookFormat>(
                        value: option, child: Text(option.name.toUpperCase()),
                      ),
                  ],
                  onChanged: (value) => redraw(() => format = value),
                ),
                DropdownButtonFormField<BookReadingStatus>(
                  key: const ValueKey('smart-shelf'),
                  initialValue: readingStatus,
                  decoration: const InputDecoration(labelText: 'Reading shelf'),
                  items: [
                    const DropdownMenuItem<BookReadingStatus>(
                        value: null, child: Text('Any shelf')),
                    for (final option in BookReadingStatus.values)
                      DropdownMenuItem<BookReadingStatus>(
                        value: option,
                        child: Text(switch (option) {
                          BookReadingStatus.toRead => 'To read',
                          BookReadingStatus.reading => 'Reading',
                          BookReadingStatus.finished => 'Finished',
                        }),
                      ),
                  ],
                  onChanged: (value) => redraw(() => readingStatus = value),
                ),
                DropdownButtonFormField<LibraryActivityFilter>(
                  key: const ValueKey('smart-activity'),
                  initialValue: activity,
                  decoration: const InputDecoration(labelText: 'Last opened'),
                  items: [
                    for (final option in LibraryActivityFilter.values)
                      DropdownMenuItem<LibraryActivityFilter>(
                        value: option,
                        child: Text(switch (option) {
                          LibraryActivityFilter.all => 'Any',
                          LibraryActivityFilter.opened => 'Opened',
                          LibraryActivityFilter.neverOpened => 'Never opened',
                        }),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) redraw(() => activity = value);
                  },
                ),
                SwitchListTile(
                  key: const ValueKey('smart-favorites'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favorites only'),
                  value: favoritesOnly,
                  onChanged: (value) =>
                      redraw(() => favoritesOnly = value),
                ),
                if (error != null)
                  Text(error!, key: const ValueKey('smart-error'),
                      style: TextStyle(
                          color: Theme.of(dialog).colorScheme.error)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('smart-save'),
            onPressed: () {
              try {
                final clean = BookCollection.cleanName(name);
                final rule = SmartBookCollectionRule(
                  query: query.trim(),
                  format: format,
                  favoritesOnly: favoritesOnly,
                  readingStatus: readingStatus,
                  activity: activity,
                );
                rule.validate();
                Navigator.of(dialog).pop((name: clean, rule: rule));
              } on FormatException catch (problem) {
                redraw(() => error = problem.message);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
