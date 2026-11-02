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

  test('explicit navigation clears detachment only after caller commits', () {
    final follow = ReaderNarrationFollowPolicy();
    expect(follow.onUserScroll(narrationPlaying: true), isTrue);
    expect(follow.suspendedByUser, isTrue);

    // Simulate a failed, cancelled, or superseded asynchronous source seek:
    // no commit callback is invoked and the visual browse state stays put.
    expect(follow.suspendedByUser, isTrue);
    expect(follow.shouldAutoFollow, isFalse);

    // A successfully persisted, winning seek reattaches the viewport.
    expect(follow.onCommittedNavigation(), isTrue);
    expect(follow.suspendedByUser, isFalse);
    expect(follow.shouldAutoFollow, isTrue);
    expect(follow.onCommittedNavigation(), isFalse);
  });

  test('explicit follow-off survives successful source navigation', () {
    final follow = ReaderNarrationFollowPolicy();
    follow.setEnabled(false);
    expect(follow.onCommittedNavigation(), isFalse);
    expect(follow.enabled, isFalse);
    expect(follow.shouldAutoFollow, isFalse);
    follow.setEnabled(true);
    expect(follow.onUserScroll(narrationPlaying: true), isTrue);
    expect(follow.onCommittedNavigation(), isTrue);
    expect(follow.enabled, isTrue);
    expect(follow.shouldAutoFollow, isTrue);
  });

  test('a confirmed paused remote chapter jump reconnects visual follow', () {
    final follow = ReaderNarrationFollowPolicy();
    follow.onUserScroll(narrationPlaying: true);
    expect(follow.suspendedByUser, isTrue);

    // An active remote audio seek must preserve independent visual browsing.
    expect(follow.shouldAutoFollow, isFalse);
    expect(follow.suspendedByUser, isTrue);

    // Media handler calls its UI callback only for the winning remote Seek.
    // When it finishes paused, the source selection becomes intentional.
    expect(follow.onCommittedNavigation(), isTrue);
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
