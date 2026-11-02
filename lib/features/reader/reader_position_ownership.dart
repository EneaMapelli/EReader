/// Decide which cursor owns a displayed reading location. Source positions
/// and media-session progress remain the responsibility of their existing
/// owners; this policy never persists or moves either cursor.
///
/// Normal follow: live speech is the source of truth for the UI.
/// Manual detachment or explicitly disabled follow: the viewport owns the
/// visible chapter, bookmark suggestion and displayed progress.
bool readerUsesVisualCursor({
  required bool narrationPlaying,
  required bool shouldAutoFollow,
}) => !narrationPlaying || !shouldAutoFollow;

/// A playing TTS player is not settled idle. Manual browsing must still
/// receive visible-block callbacks even while the audio cursor advances.
bool readerMayObserveViewport({
  required bool settledIdle,
  required bool narrationPlaying,
  required bool shouldAutoFollow,
}) => settledIdle || (narrationPlaying && !shouldAutoFollow);

/// Mere browsing during narration must not replace its crash-recovery
/// checkpoint. A temporarily detached viewport also remains non-persistent
/// after Pause until the user explicitly rejoins or navigates elsewhere.
bool readerMayPersistViewport({
  required bool settledIdle,
  required bool narrationPlaying,
  required bool temporarilyDetached,
}) => settledIdle && !narrationPlaying && !temporarilyDetached;
