import 'package:flutter/gestures.dart';

/// Recognize vertical, physical scrolling inside the book viewport.
/// Programmatic jumpTo/animateTo and trackpad pinch-only scaling do not
/// produce a user reading-position change. The native Scrollable remains
/// responsible for performing the actual movement.
bool isReaderDirectVerticalScroll(PointerEvent event) {
  if (event is PointerScrollEvent) {
    return event.scrollDelta.dy != 0;
  }
  if (event is PointerPanZoomUpdateEvent) {
    return event.panDelta.dy != 0;
  }
  return false;
}
