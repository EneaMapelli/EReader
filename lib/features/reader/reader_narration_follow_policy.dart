/// Presentation-only follow state for a reader with an independent audio
/// cursor. Manual scrolling may detach the viewport from running narration,
/// but must NEVER pause speech or alter an anchor/checkpoint.
class ReaderNarrationFollowPolicy {
  bool _enabled = true;
  bool _suspendedByUser = false;

  bool get enabled => _enabled;
  bool get suspendedByUser => _enabled && _suspendedByUser;
  bool get shouldAutoFollow => _enabled && !_suspendedByUser;

  /// The caller must classify a real user scroll before invoking this.
  /// Programmatic layout/seek/automatic-follow scrolling must not detach.
  /// Returns true only when the suspension is newly entered.
  bool onUserScroll({required bool narrationPlaying}) {
    if (!narrationPlaying || !_enabled || _suspendedByUser) return false;
    _suspendedByUser = true;
    return true;
  }

  /// An explicit setting change drops any stale manual suspension. Disabling
  /// the user preference remains different from temporarily detaching.
  void setEnabled(bool enabled) {
    _enabled = enabled;
    _suspendedByUser = false;
  }

  /// Reconnect the viewport without changing the user preference.
  bool resume() {
    if (!suspendedByUser) return false;
    _suspendedByUser = false;
    return true;
  }

  /// Opening another document must not inherit a previous scroll detachment.
  void resetForBook() {
    _suspendedByUser = false;
  }
}
