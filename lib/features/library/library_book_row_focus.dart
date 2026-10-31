import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Owns the focus and More-menu key for one *visible* library item.
///
/// A ListView.builder disposes this state as rows leave its cache area.
/// Unlike a library-wide map of FocusNodes/GlobalKeys, this keeps resource
/// usage proportional to visible rows, even when the catalog has thousands
/// of books. Key the widget by book ID to preserve focus across sorting and
/// live metadata updates while that row remains mounted.
class LibraryBookRowFocus extends StatefulWidget {
  const LibraryBookRowFocus({
    super.key,
    required this.bookTitle,
    required this.enabled,
    required this.builder,
  });

  final String bookTitle;
  final bool enabled;
  final Widget Function(
    FocusNode rowFocus,
    GlobalKey<PopupMenuButtonState<String>> menuKey,
    VoidCallback openMenu,
  ) builder;

  @override
  State<LibraryBookRowFocus> createState() => _LibraryBookRowFocusState();
}

class _LibraryBookRowFocusState extends State<LibraryBookRowFocus> {
  late final FocusNode _rowFocus =
      FocusNode(debugLabel: 'Library book: ' + widget.bookTitle);
  final GlobalKey<PopupMenuButtonState<String>> _menuKey =
      GlobalKey<PopupMenuButtonState<String>>();

  void _openMenu() {
    if (widget.enabled) {
      _menuKey.currentState?.showButtonMenu();
    }
  }

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f10, shift: true):
              _openMenu,
        },
        child: widget.builder(_rowFocus, _menuKey, _openMenu),
      );
}
