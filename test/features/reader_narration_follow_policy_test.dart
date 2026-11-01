import 'package:ereader/features/reader/reader_narration_follow_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts enabled; only real scrolling during playback suspends', () {
    final follow = ReaderNarrationFollowPolicy();
    expect(follow.enabled, isTrue);
    expect(follow.shouldAutoFollow, isTrue);
    expect(follow.onUserScroll(narrationPlaying: false), isFalse);
    expect(follow.shouldAutoFollow, isTrue);
    expect(follow.onUserScroll(narrationPlaying: true), isTrue);
    expect(follow.suspendedByUser, isTrue);
    expect(follow.shouldAutoFollow, isFalse);
    expect(follow.onUserScroll(narrationPlaying: true), isFalse);
    expect(follow.resume(), isTrue);
    expect(follow.resume(), isFalse);
    expect(follow.shouldAutoFollow, isTrue);
  });

  test('explicit disable differs from temporary detachment', () {
    final follow = ReaderNarrationFollowPolicy();
    follow.setEnabled(false);
    expect(follow.shouldAutoFollow, isFalse);
    expect(follow.suspendedByUser, isFalse);
    expect(follow.onUserScroll(narrationPlaying: true), isFalse);
    expect(follow.resume(), isFalse);
    follow.setEnabled(true);
    expect(follow.shouldAutoFollow, isTrue);
    expect(follow.onUserScroll(narrationPlaying: true), isTrue);
    follow.setEnabled(false);
    expect(follow.suspendedByUser, isFalse);
    follow.setEnabled(true);
    expect(follow.shouldAutoFollow, isTrue);
  });

  test('reopening another book clears detachment but not preference', () {
    final follow = ReaderNarrationFollowPolicy();
    follow.onUserScroll(narrationPlaying: true);
    follow.resetForBook();
    expect(follow.suspendedByUser, isFalse);
    expect(follow.shouldAutoFollow, isTrue);
    follow.setEnabled(false);
    follow.resetForBook();
    expect(follow.enabled, isFalse);
    expect(follow.shouldAutoFollow, isFalse);
  });
}
