import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Foreground-only library commands. Never override an active text editor,
/// OS-modified combinations, or another route/dialog.
enum LibraryKeyboardAction { search, tools, importBooks, help }

LibraryKeyboardAction? resolveLibraryKeyboardAction(
  KeyEvent event, {
  required bool routeActive,
  required bool editingText,
  required bool controlPressed,
  required bool metaPressed,
  required bool altPressed,
  required bool shiftPressed,
  required bool searchAvailable,
  required bool toolsAvailable,
  required bool importAvailable,
}) {
  if (!routeActive || editingText || event is! KeyDownEvent ||
      altPressed || shiftPressed) {
    return null;
  }
  final key = event.logicalKey;
  if (controlPressed || metaPressed) {
    if (key == LogicalKeyboardKey.keyF && searchAvailable) {
      return LibraryKeyboardAction.search;
    }
    if (key == LogicalKeyboardKey.keyK && toolsAvailable) {
      return LibraryKeyboardAction.tools;
    }
    if (key == LogicalKeyboardKey.keyO && importAvailable) {
      return LibraryKeyboardAction.importBooks;
    }
    return null;
  }
  if (key == LogicalKeyboardKey.f1) {
    return LibraryKeyboardAction.help;
  }
  return null;
}

/// One focus listener for desktop and Android hardware keyboards.
/// Shortcuts are intentionally not global and do not reach hidden routes.
class LibraryKeyboardShortcuts extends StatelessWidget {
  const LibraryKeyboardShortcuts({
    super.key,
    required this.onHelp,
    required this.child,
    this.onSearch,
    this.onTools,
    this.onImport,
  });

  final VoidCallback? onSearch;
  final VoidCallback? onTools;
  final VoidCallback? onImport;
  final VoidCallback onHelp;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      final focused = FocusManager.instance.primaryFocus?.context;
      final editing = focused?.widget is EditableText ||
          focused?.findAncestorWidgetOfExactType<EditableText>() != null;
      final keyboard = HardwareKeyboard.instance;
      final action = resolveLibraryKeyboardAction(
        event,
        routeActive: ModalRoute.of(context)?.isCurrent ?? true,
        editingText: editing,
        controlPressed: keyboard.isControlPressed,
        metaPressed: keyboard.isMetaPressed,
        altPressed: keyboard.isAltPressed,
        shiftPressed: keyboard.isShiftPressed,
        searchAvailable: onSearch != null,
        toolsAvailable: onTools != null,
        importAvailable: onImport != null,
      );
      if (action == null) return KeyEventResult.ignored;
      switch (action) {
        case LibraryKeyboardAction.search:
          onSearch?.call();
        case LibraryKeyboardAction.tools:
          onTools?.call();
        case LibraryKeyboardAction.importBooks:
          onImport?.call();
        case LibraryKeyboardAction.help:
          onHelp();
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// Use a scrollable dialog so enlarged accessibility text cannot overflow
/// small screens. No file, network, TTS or database operation is performed.
Future<void> showLibraryKeyboardHelp(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Library keyboard shortcuts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ctrl/Cmd + F — Search your library'),
            Text('Ctrl/Cmd + K — Find library tools'),
            Text('Ctrl/Cmd + O — Import EPUB, PDF or TXT books'),
            Text('F1 — Show this help'),
            SizedBox(height: 12),
            Text('When a book row is focused:'),
            Text('Enter — Open this book'),
            Text('Shift + F10 — More actions for this book'),
            Text('Long press a book — Same menu on touchscreens'),
            SizedBox(height: 12),
            Text('Shortcuts are ignored while typing in a text field or '
                'working inside a dialog. Import never starts narration. '
                'Search filters your local catalog; searching inside '
                'book contents is a separate library tool.'),
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
