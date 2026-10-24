import 'package:flutter/material.dart';

import '../../data/epub_embedded_content.dart';

/// Read-only, local EPUB footnote peek. The caller alone can decide whether
/// to navigate after the user explicitly chooses "Open in book".
///
/// No audio/player/store callbacks, network loading or HTML rendering occur
/// here. A dismissed sheet returns false/null and has no side effects.
Future<bool?> showEpubFootnotePreview(
  BuildContext context,
  EpubFootnotePreview note,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Footnote',
              style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(note.text,
                  style: Theme.of(sheetContext)
                      .textTheme.bodyLarge?.copyWith(height: 1.6)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Open in book'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
