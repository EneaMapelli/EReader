import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

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

/// True only for a direct, vertical book-list drag. Nested scrollables,
/// such as horizontal EPUB table previews, and synthetic layout/follow
/// notifications must not disable narration follow.
bool isReaderUserVerticalViewportScroll(ScrollNotification notification) {
  if (notification.depth != 0 ||
      notification.metrics.axis != Axis.vertical) return false;
  if (notification is ScrollStartNotification) {
    return notification.dragDetails != null;
  }
  if (notification is ScrollUpdateNotification) {
    return notification.dragDetails != null;
  }
  return false;
}
