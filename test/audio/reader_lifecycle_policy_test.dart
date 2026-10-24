import 'package:ereader/audio/reader_lifecycle_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen off with owned Android media service retains narration', () {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      expect(ReaderLifecyclePolicy.backgroundTransition(state), isTrue);
      expect(ReaderLifecyclePolicy.mustPauseOnBackground(
        state: state, isAndroid: true, mediaOwnsPlayer: true,
      ), isFalse);
    }
  });

  test('Android background without active media owner pauses speech', () {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      expect(ReaderLifecyclePolicy.mustPauseOnBackground(
        state: state, isAndroid: true, mediaOwnsPlayer: false,
      ), isTrue);
    }
  });

  test('resume does not auto-play and other platforms are not affected', () {
    for (final state in [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.detached,
    ]) {
      expect(ReaderLifecyclePolicy.backgroundTransition(state), isFalse);
      expect(ReaderLifecyclePolicy.mustPauseOnBackground(
        state: state, isAndroid: true, mediaOwnsPlayer: false,
      ), isFalse);
    }
    expect(ReaderLifecyclePolicy.mustPauseOnBackground(
      state: AppLifecycleState.paused,
      isAndroid: false,
      mediaOwnsPlayer: false,
    ), isFalse);
  });
}
