import 'package:flutter/material.dart';

/// One compact, accessible entry point for the EPUB chapter visit trail.
///
/// This is navigation history, not TTS previous/next or next EPUB chapter.
/// The reader owns all callbacks and the guarded, persisted source seek.
class ReaderChapterHistoryShortcut extends StatefulWidget {
  const ReaderChapterHistoryShortcut({
    super.key,
    this.onBack,
    this.onForward,
    this.onRecent,
    this.historyRevision,
    this.currentHistoryRevision,
  });

  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onRecent;
  /// Optional live history guard. A popup opened for an older revision
  /// cannot act on a newer chapter/forward trail.
  final int? historyRevision;
  final int Function()? currentHistoryRevision;

  @override
  State<ReaderChapterHistoryShortcut> createState() =>
      _ReaderChapterHistoryShortcutState();
}

class _ReaderChapterHistoryShortcutState
    extends State<ReaderChapterHistoryShortcut> {
  int? _openedRevision;

  bool get _stillCurrent =>
      widget.currentHistoryRevision == null ||
      (widget.historyRevision != null &&
          _openedRevision == widget.currentHistoryRevision!());

  @override
  Widget build(BuildContext context) {
    if (widget.onBack == null &&
        widget.onForward == null && widget.onRecent == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
        key: const ValueKey('reader-chapter-history-shortcut'),
        tooltip: 'Chapter visit history: back, forward and recent positions',
        icon: const Icon(Icons.history),
        // Capture at OPEN time, not only when the reader widget builds:
        // hardware/media navigation can alter the live history while this
        // popup route is still awaiting the user's selection.
        onOpened: () {
          _openedRevision = widget.historyRevision;
        },
        onSelected: (action) {
          if (!_stillCurrent) return;
          switch (action) {
            case 'back':
              widget.onBack?.call();
              break;
            case 'forward':
              widget.onForward?.call();
              break;
            case 'recent':
              widget.onRecent?.call();
              break;
          }
        },
        itemBuilder: (context) => [
          if (widget.onBack != null)
            const PopupMenuItem<String>(
              key: ValueKey('reader-chapter-shortcut-back'),
              value: 'back',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.arrow_back),
                title: Text('Back to previous visited position'),
                subtitle: Text('Ctrl/Cmd + Shift + Page Up'),
              ),
            ),
          if (widget.onForward != null)
            const PopupMenuItem<String>(
              key: ValueKey('reader-chapter-shortcut-forward'),
              value: 'forward',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.arrow_forward),
                title: Text('Forward to next visited position'),
                subtitle: Text('Ctrl/Cmd + Shift + Page Down'),
              ),
            ),
          if (widget.onRecent != null)
            const PopupMenuItem<String>(
              key: ValueKey('reader-chapter-shortcut-recent'),
              value: 'recent',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history_toggle_off),
                title: Text('Recent chapter positions'),
                subtitle: Text('Ctrl/Cmd + Shift + H'),
              ),
            ),
        ],
      );
  }
}
