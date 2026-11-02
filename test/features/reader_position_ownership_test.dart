import 'package:ereader/features/reader/reader_position_ownership.dart';
import 'package:ereader/features/reader/epub_link_history.dart';
import 'package:ereader/features/reader/epub_visual_layout.dart';
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

  test('EPUB bookmarks and TOC resolve visual source while audio advances', () {
    const visualSourceOffset = 312;
    var audioSourceOffset = 980;

    int visibleSource(bool autoFollow) {
      final useVisual = readerUsesVisualCursor(
        narrationPlaying: true, shouldAutoFollow: autoFollow,
      );
      return epubSourceOffsetForLinkReturn(
        speechOffset: audioSourceOffset,
        narrationActive: !useVisual,
        visualOffset: visualSourceOffset,
      );
    }

    expect(visibleSource(true), 980);
    expect(visibleSource(false), visualSourceOffset);
    audioSourceOffset = 1400;
    expect(visibleSource(false), visualSourceOffset,
        reason: 'Background TTS must not move the bookmark suggestion');
    expect(visibleSource(true), 1400,
        reason: 'Returning to narrator restores live source ownership');
  });

  test('silent EPUB visual checkpoint remains independent of speech', () {
    final exact = EpubVisualSourceCheckpoint();
    exact.hold(12, awaitTarget: false, targetBlockIndex: 0);
    expect(readerUsesVisualCursor(
        narrationPlaying: true, shouldAutoFollow: false), isTrue);
    expect(epubSourceOffsetForLinkReturn(
        speechOffset: 240,
        narrationActive: false,
        visualOffset: exact.offset), 12);
    expect(exact.offset, 12);
    expect(readerMayPersistViewport(
        settledIdle: false,
        narrationPlaying: true,
        temporarilyDetached: true), isFalse);
    expect(exact.offset, 12,
        reason: 'The TTS cursor and visual source coordinate are separate');
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
