import 'package:ereader/features/reader/epub_link_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links remember visible EPUB source position when narration is paused',
      () {
    const captionStart = 32;
    const nearestSpeechStart = 84;
    const noteTarget = 411;
    final returnOffset = epubSourceOffsetForLinkReturn(
      speechOffset: nearestSpeechStart,
      narrationActive: false,
      visualOffset: captionStart,
    );
    expect(returnOffset, captionStart);
    final history = EpubLinkHistory()
      ..push(returnOffset, noteTarget);
    expect(history.last, captionStart,
        reason: 'Returning from a note must not jump to future narration');

    expect(epubSourceOffsetForLinkReturn(
      speechOffset: nearestSpeechStart,
      narrationActive: true,
      visualOffset: captionStart,
    ), nearestSpeechStart);
    expect(epubSourceOffsetForLinkReturn(
      speechOffset: nearestSpeechStart,
      narrationActive: false,
    ), nearestSpeechStart);
    expect(epubSourceOffsetForLinkReturn(
      speechOffset: nearestSpeechStart,
      narrationActive: false,
      visualOffset: -1,
    ), nearestSpeechStart);
  });

  test('note navigation can return through multiple source anchors', () {
    final history = EpubLinkHistory();
    history.push(18, 202);
    history.push(202, 410);
    expect(history.length, 2);
    expect(history.last, 202);
    history.commitReturn();
    expect(history.last, 18);
    history.commitReturn();
    expect(history.last, isNull);
    expect(history.canReturn, isFalse);
  });

  test('same-offset taps and invalid offsets do not build a back stack', () {
    final history = EpubLinkHistory();
    history.push(10, 10);
    history.push(-1, 12);
    history.push(12, -3);
    expect(history.length, 0);
  });

  test('bounded history discards oldest location and retains recent notes', () {
    final history = EpubLinkHistory(maxDepth: 3);
    for (var index = 0; index < 6; index++) {
      history.push(index * 10, index * 10 + 1);
    }
    expect(history.length, 3);
    expect(history.last, 50);
    history.commitReturn();
    expect(history.last, 40);
    history.commitReturn();
    expect(history.last, 30);
    history.clear();
    expect(history.last, isNull);
  });

  test('return is committed only after explicit success', () {
    final history = EpubLinkHistory();
    history.push(21, 201);
    // A failure to stop the native TTS engine leaves the return location.
    expect(history.last, 21);
    expect(history.length, 1);
    history.commitReturn();
    expect(history.canReturn, isFalse);
  });
}
