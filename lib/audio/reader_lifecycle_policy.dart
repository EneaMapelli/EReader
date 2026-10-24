import 'package:flutter/widgets.dart';

/// Android lifecycle rule for the current reader. Background audio is allowed
/// only when this book owns a live MediaSession. Other platforms keep their
/// existing window-minimization behavior.
abstract final class ReaderLifecyclePolicy {
  static bool backgroundTransition(AppLifecycleState state) =>
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused;

  static bool mustPauseOnBackground({
    required AppLifecycleState state,
    required bool isAndroid,
    required bool mediaOwnsPlayer,
  }) =>
      isAndroid && !mediaOwnsPlayer && backgroundTransition(state);
}
