import 'package:flutter/material.dart';

/// Always-visible escape hatch from the reader's temporarily hidden controls.
///
/// This changes only the foreground presentation: it never controls speech,
/// changes book progress, or persists an appearance preference.
class ReaderFocusRestoreButton extends StatelessWidget {
  const ReaderFocusRestoreButton({
    super.key,
    required this.onRestore,
  });

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
        key: const ValueKey('reader-focus-restore'),
        heroTag: 'reader-focus-restore-fab',
        tooltip: 'Show narration controls',
        onPressed: onRestore,
        child: const Icon(Icons.expand_less),
      );
}
