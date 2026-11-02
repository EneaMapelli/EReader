import 'package:flutter/material.dart';

import '../../domain/reading_progress.dart';

/// Minimal source-text position for immersion mode, when the normal
/// narration panel (including its seek slider) is hidden.
///
/// This reflects the reader's VISUAL source coordinate, not speech
/// duration, cached audio bytes, or a guessed EPUB page number.
/// Tapping delegates to the existing explicit Go-to-position dialog;
/// the indicator itself never seeks or changes any saved anchor.
class ReaderFocusProgressStrip extends StatelessWidget
    implements PreferredSizeWidget {
  const ReaderFocusProgressStrip({
    super.key,
    required this.sourceOffset,
    required this.sourceLength,
    required this.onNavigate,
  });

  final int sourceOffset;
  final int sourceLength;
  final VoidCallback onNavigate;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final progress = ReadingSourceProgress.fraction(
      offset: sourceOffset,
      length: sourceLength,
    );
    final percent = (progress * 100).round();
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('reader-focus-progress-semantics'),
      button: sourceLength > 0,
      enabled: sourceLength > 0,
      label: sourceLength > 0
          ? 'Book text position: $percent percent. Open go to book position'
          : 'Book text position unavailable',
      // ExcludeSemantics hides the nested InkWell semantics, so expose
      // the activation explicitly for TalkBack and screen readers.
      onTap: sourceLength > 0 ? onNavigate : null,
      child: ExcludeSemantics(
        child: Material(
          color: Theme.of(context).appBarTheme.backgroundColor ??
              colorScheme.surface,
          child: InkWell(
            key: const ValueKey('reader-focus-progress'),
            onTap: sourceLength > 0 ? onNavigate : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      '$percent%',
                      key: const ValueKey('reader-focus-progress-label'),
                      style: Theme.of(context).textTheme.labelMedium,
                      textAlign: TextAlign.start,
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      key: const ValueKey('reader-focus-progress-track'),
                      value: progress,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
