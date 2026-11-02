import 'package:ereader/features/reader/reader_position_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live follow uses speech, manual browsing uses viewport', () {
    expect(readerUsesVisualCursor(
        narrationPlaying: true, shouldAutoFollow: true), isFalse);
    expect(readerUsesVisualCursor(
        narrationPlaying: true, shouldAutoFollow: false), isTrue);
    expect(readerUsesVisualCursor(
        narrationPlaying: false, shouldAutoFollow: true), isTrue);
    expect(readerUsesVisualCursor(
        narrationPlaying: false, shouldAutoFollow: false), isTrue);
  });

  test('active audio permits observing only detached visual scrolling', () {
    expect(readerMayObserveViewport(
        settledIdle: false, narrationPlaying: true,
        shouldAutoFollow: true), isFalse);
    expect(readerMayObserveViewport(
        settledIdle: false, narrationPlaying: true,
        shouldAutoFollow: false), isTrue);
    expect(readerMayObserveViewport(
        settledIdle: true, narrationPlaying: false,
        shouldAutoFollow: true), isTrue);
    expect(readerMayObserveViewport(
        settledIdle: false, narrationPlaying: false,
        shouldAutoFollow: false), isFalse,
        reason: 'Pending native pause/seek must not become a visual jump');
  });

  test('only settled non-detached manual view may save progress', () {
    expect(readerMayPersistViewport(
        settledIdle: true, narrationPlaying: false,
        temporarilyDetached: false), isTrue);
    expect(readerMayPersistViewport(
        settledIdle: false, narrationPlaying: true,
        temporarilyDetached: true), isFalse);
    expect(readerMayPersistViewport(
        settledIdle: true, narrationPlaying: false,
        temporarilyDetached: true), isFalse,
        reason: 'Pausing audio must not save the browsed passage');
    expect(readerMayPersistViewport(
        settledIdle: true, narrationPlaying: true,
        temporarilyDetached: false), isFalse);
    expect(readerMayPersistViewport(
        settledIdle: false, narrationPlaying: false,
        temporarilyDetached: false), isFalse);
  });
}
