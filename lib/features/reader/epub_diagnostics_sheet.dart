import 'package:flutter/material.dart';

import '../../data/epub_import_diagnostics.dart';

/// Passive view of import warnings; fixed descriptions contain no user EPUB
/// markup, URLs, arbitrary paths or hidden book excerpts.
Future<void> showEpubImportDiagnostics(
  BuildContext context,
  List<EpubImportDiagnostic> diagnostics,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('EPUB compatibility report'),
            subtitle: const Text(
              'The original reading text remains available. '
              'Unsupported optional content may be omitted.',
            ),
          ),
          Expanded(
            child: diagnostics.isEmpty
                ? const Center(child: Text('No compatibility warnings found'))
                : ListView.builder(
                    itemCount: diagnostics.length,
                    itemBuilder: (context, index) {
                      final item = diagnostics[index];
                      return ListTile(
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(item.description),
                        trailing: Text('${item.occurrences}×'),
                      );
                    },
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
