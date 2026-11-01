import 'package:ereader/features/reader/reader_direct_scroll_input.dart';
import 'package:ereader/features/reader/reader_viewport_save_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wheel scrolling accepts vertical movement only', () {
    expect(isReaderDirectVerticalScroll(
      const PointerScrollEvent(scrollDelta: Offset(0, 52)),
    ), isTrue);
    expect(isReaderDirectVerticalScroll(
      const PointerScrollEvent(scrollDelta: Offset(0, -80)),
    ), isTrue);
    expect(isReaderDirectVerticalScroll(
      const PointerScrollEvent(scrollDelta: Offset(90, 0)),
    ), isFalse);
    expect(isReaderDirectVerticalScroll(
      const PointerScrollEvent(scrollDelta: Offset.zero),
    ), isFalse);
  });

  test('touchpad vertical pans count but horizontal pans and pinch do not',
      () {
    expect(isReaderDirectVerticalScroll(
      const PointerPanZoomUpdateEvent(
        pan: Offset(0, 24),
        panDelta: Offset(0, 24),
      ),
    ), isTrue);
    expect(isReaderDirectVerticalScroll(
      const PointerPanZoomUpdateEvent(
        pan: Offset(0, -20),
        panDelta: Offset(0, -20),
        scale: 1.2,
      ),
    ), isTrue);
    expect(isReaderDirectVerticalScroll(
      const PointerPanZoomUpdateEvent(
        pan: Offset(45, 0),
        panDelta: Offset(45, 0),
      ),
    ), isFalse);
    expect(isReaderDirectVerticalScroll(
      const PointerPanZoomUpdateEvent(
        scale: 1.4,
      ),
    ), isFalse);
  });

  test('generic touch and synthetic movement never imply scrolling', () {
    expect(isReaderDirectVerticalScroll(
      const PointerDownEvent(position: Offset(30, 30)),
    ), isFalse);
    expect(isReaderDirectVerticalScroll(
      const PointerMoveEvent(
        position: Offset(30, 60), delta: Offset(0, 30),
      ),
    ), isFalse);
    expect(isReaderDirectVerticalScroll(
      const PointerPanZoomStartEvent(),
    ), isFalse);
    expect(isReaderDirectVerticalScroll(
      const PointerPanZoomEndEvent(),
    ), isFalse);
  });

  test('only eligible pointer input resumes suspended checkpoint saving',
      () {
    final gate = ReaderViewportSaveGate()..suspendForLayoutChange();
    for (final input in <PointerEvent>[
      const PointerPanZoomUpdateEvent(scale: 1.2),
      const PointerScrollEvent(scrollDelta: Offset(48, 0)),
      const PointerMoveEvent(delta: Offset(0, 100)),
    ]) {
      if (isReaderDirectVerticalScroll(input)) {
        gate.resumeFromUserScroll();
      }
      expect(gate.allowsViewportSave, isFalse);
    }
    if (isReaderDirectVerticalScroll(const PointerPanZoomUpdateEvent(
      pan: Offset(0, 55), panDelta: Offset(0, 55),
    ))) {
      gate.resumeFromUserScroll();
    }
    expect(gate.allowsViewportSave, isTrue);
  });
}
