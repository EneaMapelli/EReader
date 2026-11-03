/// Prevent purely visual viewport resizing from changing a saved book
/// checkpoint. An explicit user scroll re-enables ordinary viewport saves.
///
/// A source seek/TOC jump continues through the reader's separate explicit
/// checkpoint path. This gate never persists data and owns no timers.
class ReaderViewportSaveGate {
  bool _waitingForUserScroll = false;

  bool get allowsViewportSave => !_waitingForUserScroll;

  void suspendForLayoutChange() {
    _waitingForUserScroll = true;
  }

  void resumeFromUserScroll() {
    _waitingForUserScroll = false;
  }
}

/// Persist an idle/manual-viewport checkpoint without leaking an unhandled
/// asynchronous storage exception from a debounce Timer. The caller remains
/// responsible for selecting the source/anchor and invalidating obsolete
/// requests on seek, reload, audio transport or a newer scroll event.
///
/// A successful SQLite write cannot be rolled back if a later user intent
/// arrives while its Future settles. Only post-write reporting is guarded.
Future<void> persistReaderViewportCheckpoint({
  required Future<void> Function() save,
  required bool Function() isCurrent,
  required void Function(Object error) onFailure,
  void Function()? onSaved,
}) async {
  if (!isCurrent()) return;
  try {
    await save();
  } catch (error) {
    if (isCurrent()) onFailure(error);
    return;
  }
  if (isCurrent()) onSaved?.call();
}

/// A background reader or a page obscured by another route must never
/// record a viewport-origin checkpoint, even when the player is idle.
/// Explicit source selections and background-audio checkpoints are handled
/// by their own paths, not this visual-scroll eligibility guard.
bool readerMaySaveVisibleViewport({
  required bool readerForeground,
  required bool readerRouteCurrent,
  required bool userScrollAllowed,
}) => readerForeground && readerRouteCurrent && userScrollAllowed;
