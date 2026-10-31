import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Deliberately local reader actions. Media keys and background transport
/// continue to be owned by ReaderMediaHandler, not this focus widget.
enum ReaderKeyboardAction {
  playPause,
  previousSegment,
  nextSegment,
  search,
  bookmarks,
  help,
  tools,
}

/// Pure, predictable key mapping, independent of the TTS engine.
///
/// Never steal text editing (including Ctrl/Cmd+F), repeated key-downs,
/// platform shortcuts with unrelated modifiers or events from a hidden
/// route. Arrow keys are for source-aligned *spoken segments* only.
ReaderKeyboardAction? resolveReaderKeyboardAction(
  KeyEvent event, {
  required bool readerReady,
  required bool routeActive,
  required bool editingText,
  bool interactiveControlFocused = false,
  bool toolsAvailable = false,
  required bool controlPressed,
  required bool metaPressed,
  required bool altPressed,
  required bool shiftPressed,
}) {
  if (!routeActive || editingText || event is! KeyDownEvent) {
    return null;
  }
  final key = event.logicalKey;
  final command = controlPressed || metaPressed;
  // Tools remain accessible when a PDF is displayed as native pages,
  // where spoken-segment commands intentionally stay disabled.
  if (command && !altPressed && !shiftPressed &&
      key == LogicalKeyboardKey.keyK && toolsAvailable) {
    return ReaderKeyboardAction.tools;
  }
  if (!readerReady) return null;
  if (interactiveControlFocused &&
      (key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight)) {
    // A focused slider/button owns transport keys, even if it bubbles them.
    return null;
  }
  if (command && !altPressed && !shiftPressed) {
    if (key == LogicalKeyboardKey.keyF) {
      return ReaderKeyboardAction.search;
    }
    if (key == LogicalKeyboardKey.keyB) {
      return ReaderKeyboardAction.bookmarks;
    }
  }
  if (command || altPressed || shiftPressed) return null;
  if (key == LogicalKeyboardKey.space) {
    return ReaderKeyboardAction.playPause;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return ReaderKeyboardAction.previousSegment;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return ReaderKeyboardAction.nextSegment;
  }
  if (key == LogicalKeyboardKey.f1) {
    return ReaderKeyboardAction.help;
  }
  return null;
}

/// Keyboard navigation belongs to the foreground reading route only.
/// Dialogs, selection editors and focused text inputs keep their own keys.
class ReaderKeyboardShortcuts extends StatelessWidget {
  const ReaderKeyboardShortcuts({
    super.key,
    required this.enabled,
    required this.onPlayPause,
    required this.onPreviousSegment,
    required this.onNextSegment,
    required this.onSearch,
    required this.onBookmarks,
    required this.onHelp,
    this.onTools,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onPlayPause;
  final VoidCallback onPreviousSegment;
  final VoidCallback onNextSegment;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;
  final VoidCallback onHelp;
  final VoidCallback? onTools;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final focused = FocusManager.instance.primaryFocus?.context;
        final editing = focused?.widget is EditableText ||
            focused?.findAncestorWidgetOfExactType<EditableText>() != null;
        // When a controls' FocusNode has the primary focus, let the
        // control handle Space and arrows instead of seeking narration.
        final interactive = focused?.findAncestorWidgetOfExactType<Slider>() != null ||
            focused?.findAncestorWidgetOfExactType<ButtonStyleButton>() != null ||
            focused?.findAncestorWidgetOfExactType<IconButton>() != null ||
            focused?.findAncestorWidgetOfExactType<ListTile>() != null ||
            focused?.findAncestorWidgetOfExactType<InkWell>() != null;
        final keyboard = HardwareKeyboard.instance;
        final action = resolveReaderKeyboardAction(
          event,
          readerReady: enabled,
          routeActive: ModalRoute.of(context)?.isCurrent ?? true,
          editingText: editing,
          interactiveControlFocused: interactive,
          toolsAvailable: onTools != null,
          controlPressed: keyboard.isControlPressed,
          metaPressed: keyboard.isMetaPressed,
          altPressed: keyboard.isAltPressed,
          shiftPressed: keyboard.isShiftPressed,
        );
        if (action == null) return KeyEventResult.ignored;
        switch (action) {
          case ReaderKeyboardAction.playPause:
            onPlayPause();
          case ReaderKeyboardAction.previousSegment:
            onPreviousSegment();
          case ReaderKeyboardAction.nextSegment:
            onNextSegment();
          case ReaderKeyboardAction.search:
            onSearch();
          case ReaderKeyboardAction.bookmarks:
            onBookmarks();
          case ReaderKeyboardAction.help:
            onHelp();
          case ReaderKeyboardAction.tools:
            onTools?.call();
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// Accessible, non-blocking, on-demand reference: F1 opens it from the
/// reader. No overlay is created while typing in search or cast editors.
Future<void> showReaderKeyboardHelp(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Reader keyboard shortcuts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Space — Play or pause narration'),
            Text('Left arrow — Previous spoken segment'),
            Text('Right arrow — Next spoken segment'),
            Text('Ctrl/Cmd + F — Search in this book'),
            Text('Ctrl/Cmd + B — Bookmarks'),
            Text('Ctrl/Cmd + K — Find reader tools'),
            Text('F1 — Show this help'),
            SizedBox(height: 12),
            Text('Shortcuts do not run while typing in a text field. '
                'Space and arrows belong to focused buttons/sliders. '
                'Navigation follows TTS segment boundaries, not visual '
                'pages or words.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
