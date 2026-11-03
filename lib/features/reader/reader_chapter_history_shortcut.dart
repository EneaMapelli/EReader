import 'package:flutter/material.dart';

/// One compact, accessible entry point for the EPUB chapter visit trail.
///
/// This is navigation history, not TTS previous/next or next EPUB chapter.
/// The reader owns all callbacks and the guarded, persisted source seek.
class ReaderChapterHistoryShortcut extends StatelessWidget {
  const ReaderChapterHistoryShortcut({
    super.key,
    this.onBack,
    this.onForward,
    this.onRecent,
  });

  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onRecent;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: const ValueKey('reader-chapter-history-shortcut'),
        tooltip: 'Chapter visit history: back, forward and recent positions',
        icon: const Icon(Icons.history),
        onSelected: (action) {
          switch (action) {
            case 'back':
              onBack?.call();
              break;
            case 'forward':
              onForward?.call();
              break;
            case 'recent':
              onRecent?.call();
              break;
          }
        },
        itemBuilder: (context) => [
          if (onBack != null)
            const PopupMenuItem<String>(
              key: ValueKey('reader-chapter-shortcut-back'),
              value: 'back',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.arrow_back),
                title: Text('Back to previous visited position'),
              ),
            ),
          if (onForward != null)
            const PopupMenuItem<String>(
              key: ValueKey('reader-chapter-shortcut-forward'),
              value: 'forward',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.arrow_forward),
                title: Text('Forward to next visited position'),
              ),
            ),
          if (onRecent != null)
            const PopupMenuItem<String>(
              key: ValueKey('reader-chapter-shortcut-recent'),
              value: 'recent',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history_toggle_off),
                title: Text('Recent chapter positions'),
              ),
            ),
        ],
      );
}
