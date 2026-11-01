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
