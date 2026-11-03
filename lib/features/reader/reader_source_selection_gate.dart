/// In-memory latest-intent guard for reader source navigation.
///
/// Explicit selections reserve their place *before* awaiting a native
/// Pause/Stop barrier. A stale continuation may not begin a Seek, write
/// a source checkpoint, or repaint the viewport after a newer selection.
/// This guard never persists data or operates on the speech engine itself.
class ReaderSourceSelectionGate {
  int _revision = 0;

  int reserve() => ++_revision;

  /// Current intent snapshot for asynchronous errors that do not themselves
  /// initiate a Seek (e.g. transport Pause or a queued TTS snackbar).
  int get revision => _revision;

  bool isCurrent(int revision) => revision == _revision;

  /// A reload / remote selection can invalidate all pending local intent.
  void invalidate() => ++_revision;
}
