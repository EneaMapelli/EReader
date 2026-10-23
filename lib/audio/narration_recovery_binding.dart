import '../data/library_store.dart';
import '../domain/reading_anchor.dart';
import '../domain/speech_segment.dart';
import 'reader_player.dart';

/// Owns the crash-only narration checkpoint for one ReaderPlayer.
///
/// This is deliberately independent of ReaderScreen's visual repaint cycle:
/// media buttons, lock-screen Pause and sleep timer all notify ReaderPlayer
/// even if the Flutter activity is in the background.
class NarrationRecoveryBinding {
  NarrationRecoveryBinding({
    required this.store,
    required this.bookId,
    required this.anchorFor,
  });

  final LibraryStore store;
  final String bookId;
  final ReadingAnchor Function(SpeechSegment) anchorFor;

  ReaderPlayer? _player;
  bool _disposed = false;

  void attach(ReaderPlayer player) {
    if (_disposed || _player != null) {
      throw StateError('Narration checkpoint binding already attached');
    }
    _player = player;
    player.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }

  /// ReaderPlayer calls this before the native/cloud synthesis of each
  /// segment. It is synchronous up to the Future return, so SQLite commits
  /// source position and the crash marker before any speech-side effects.
  Future<void> onSegmentStarted(SpeechSegment segment) async {
    final player = _player;
    if (_disposed || player == null || !player.isPlaying) return;
    store.recordSpeechSegmentStart(
      bookId, segment.start, anchor: anchorFor(segment),
    );
  }

  void _onPlayerChanged() {
    if (_disposed) return;
    final player = _player;
    if (player != null && player.isSettledIdle) {
      // A seek/voice change only *looks* paused while native stop is
      // pending. Preserve the segment checkpoint until playback truly
      // settles, including a completion or an external transport Pause.
      store.clearSpeechRecoveryMarker(bookId);
    }
  }

  /// Called before replacing/discarding a reader. Does not initiate
  /// synthesis or dispose the native audio engine (ReaderPlayer owns that).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _player?.removeListener(_onPlayerChanged);
    _player = null;
    store.clearSpeechRecoveryMarker(bookId);
  }
}
