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
  goToProgress,
  returnToProgress,
  returnToNarration,
  toggleFocusMode,
  help,
  tools,
  increaseTextSize,
  decreaseTextSize,
  previousSection,
  nextSection,
  firstSection,
  lastSection,
}

/// Shared with the in-reader text-size menu: never write a preference
/// outside the supported reading font range (14–32 logical pixels).
double steppedReaderFontSize(double current, int delta) =>
    (current + delta).clamp(14.0, 32.0).toDouble();

/// Resolve the adjacent EPUB directory entry without wrapping.
///
/// The first Next from an unresolved location starts at section zero;
/// Previous does not guess or accidentally wrap to the final section.
int? adjacentReaderSectionIndex({
  required int current,
  required int count,
  required bool forward,
}) {
  if (count <= 0) return null;
  final target = current < 0
      ? (forward ? 0 : -1)
      : current + (forward ? 1 : -1);
  return target >= 0 && target < count ? target : null;
}

/// Index of the first or last readable EPUB navigation section.
/// Empty TOCs are deliberately not navigable, preventing a fabricated jump.
int? boundaryReaderSectionIndex({
  required int count,
  required bool last,
}) => count <= 0 ? null : (last ? count - 1 : 0);

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
  bool progressAvailable = false,
  bool progressReturnAvailable = false,
  bool returnToNarrationAvailable = false,
  bool textSizeAvailable = false,
  bool focusModeAvailable = false,
  bool sectionNavigationAvailable = false,
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
  // Text layout adjustments do not require playable narration (e.g. PDF
  // text mode), but never run during loading or on hidden/editor routes.
  if (command && !altPressed && textSizeAvailable) {
    if (key == LogicalKeyboardKey.equal) {
      // Ctrl/Cmd+=, or Ctrl/Cmd+Shift+= on keyboards requiring Shift for +.
      return ReaderKeyboardAction.increaseTextSize;
    }
    if (key == LogicalKeyboardKey.minus && !shiftPressed) {
      return ReaderKeyboardAction.decreaseTextSize;
    }
  }
  if (command && !altPressed && !shiftPressed &&
      !interactiveControlFocused && sectionNavigationAvailable) {
    if (key == LogicalKeyboardKey.pageUp) {
      return ReaderKeyboardAction.previousSection;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      return ReaderKeyboardAction.nextSection;
    }
    if (key == LogicalKeyboardKey.home) {
      return ReaderKeyboardAction.firstSection;
    }
    if (key == LogicalKeyboardKey.end) {
      return ReaderKeyboardAction.lastSection;
    }
  }
  if (!readerReady) return null;
  // F11 switches reading presentation only. It must never seek, start TTS
  // or steal a text editor's / focused control's own keyboard input.
  if (!command && !altPressed && !shiftPressed &&
      !interactiveControlFocused && focusModeAvailable &&
      key == LogicalKeyboardKey.f11) {
    return ReaderKeyboardAction.toggleFocusMode;
  }
  // The shortcut is enabled only while visual follow is temporarily detached.
  // It never changes the speech cursor or audio state.
  if (command && shiftPressed && !altPressed &&
      !interactiveControlFocused && returnToNarrationAvailable &&
      key == LogicalKeyboardKey.keyJ) {
    return ReaderKeyboardAction.returnToNarration;
  }
  if (command && !altPressed && !interactiveControlFocused &&
      key == LogicalKeyboardKey.keyG) {
    if (shiftPressed && progressReturnAvailable) {
      return ReaderKeyboardAction.returnToProgress;
    }
    if (!shiftPressed && progressAvailable) {
      return ReaderKeyboardAction.goToProgress;
    }
  }
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
    this.onGoToProgress,
    this.onReturnToProgress,
    this.onReturnToNarration,
    this.onToggleFocusMode,
    this.onIncreaseTextSize,
    this.onDecreaseTextSize,
    this.onPreviousSection,
    this.onNextSection,
    this.onFirstSection,
    this.onLastSection,
    this.onViewportScrollKey,
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
  final VoidCallback? onGoToProgress;
  final VoidCallback? onReturnToProgress;
  final VoidCallback? onReturnToNarration;
  final VoidCallback? onToggleFocusMode;
  final VoidCallback? onIncreaseTextSize;
  final VoidCallback? onDecreaseTextSize;
  final VoidCallback? onPreviousSection;
  final VoidCallback? onNextSection;
  final VoidCallback? onFirstSection;
  final VoidCallback? onLastSection;

  /// Observe unmodified book scrolling keys without consuming their
  /// native ScrollAction. This is only a user-intent signal, not a seek.
  final VoidCallback? onViewportScrollKey;
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
          progressAvailable: onGoToProgress != null,
          progressReturnAvailable: onReturnToProgress != null,
          returnToNarrationAvailable: onReturnToNarration != null,
          textSizeAvailable: onIncreaseTextSize != null &&
              onDecreaseTextSize != null,
          focusModeAvailable: onToggleFocusMode != null,
          sectionNavigationAvailable: onPreviousSection != null &&
              onNextSection != null &&
              onFirstSection != null && onLastSection != null,
          controlPressed: keyboard.isControlPressed,
          metaPressed: keyboard.isMetaPressed,
          altPressed: keyboard.isAltPressed,
          shiftPressed: keyboard.isShiftPressed,
        );
        if (action == null) {
          // Keyboard scrolls may not carry dragDetails, whereas framework
          // relayout/programmatic scrolling can emit UserScrollNotification.
          // Observe the physical key instead of trusting that notification.
          if (onViewportScrollKey != null &&
              event is KeyDownEvent &&
              (ModalRoute.of(context)?.isCurrent ?? true) &&
              !editing && !interactive &&
              !keyboard.isControlPressed && !keyboard.isMetaPressed &&
              !keyboard.isAltPressed && !keyboard.isShiftPressed &&
              (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown ||
                  event.logicalKey == LogicalKeyboardKey.pageUp ||
                  event.logicalKey == LogicalKeyboardKey.pageDown ||
                  event.logicalKey == LogicalKeyboardKey.home ||
                  event.logicalKey == LogicalKeyboardKey.end)) {
            onViewportScrollKey!();
          }
          return KeyEventResult.ignored;
        }
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
          case ReaderKeyboardAction.goToProgress:
            onGoToProgress?.call();
          case ReaderKeyboardAction.returnToProgress:
            onReturnToProgress?.call();
          case ReaderKeyboardAction.returnToNarration:
            onReturnToNarration?.call();
          case ReaderKeyboardAction.toggleFocusMode:
            onToggleFocusMode?.call();
          case ReaderKeyboardAction.help:
            onHelp();
          case ReaderKeyboardAction.tools:
            onTools?.call();
          case ReaderKeyboardAction.increaseTextSize:
            onIncreaseTextSize?.call();
          case ReaderKeyboardAction.decreaseTextSize:
            onDecreaseTextSize?.call();
          case ReaderKeyboardAction.previousSection:
            onPreviousSection?.call();
          case ReaderKeyboardAction.nextSection:
            onNextSection?.call();
          case ReaderKeyboardAction.firstSection:
            onFirstSection?.call();
          case ReaderKeyboardAction.lastSection:
            onLastSection?.call();
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
            Text('Ctrl/Cmd + G — Go to book percentage'),
            Text('Ctrl/Cmd + Shift + G — Return after percentage jump'),
            Text('Ctrl/Cmd + Shift + J — Rejoin active narration'),
            Text('Ctrl/Cmd + K — Find reader tools'),
            Text('Ctrl/Cmd + = — Increase reading text size'),
            Text('Ctrl/Cmd + - — Decrease reading text size'),
            Text('Ctrl/Cmd + Page Up — Previous EPUB section'),
            Text('Ctrl/Cmd + Page Down — Next EPUB section'),
            Text('Ctrl/Cmd + Home — First EPUB section'),
            Text('Ctrl/Cmd + End — Last EPUB section'),
            Text('F11 — Toggle immersive reading mode'),
            Text('F1 — Show this help'),
            SizedBox(height: 12),
            Text('Shortcuts do not run while typing in a text field. '
                'Space and arrows belong to focused buttons/sliders. '
                'Left/right follow spoken segments; Ctrl/Cmd+Page Up/Down '
                'moves between EPUB sections, including silent sections.'),
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
