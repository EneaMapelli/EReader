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
    this.anchorAtOffset,
  });

  final LibraryStore store;
  final String bookId;
  final ReadingAnchor Function(SpeechSegment) anchorFor;
  /// Optional exact end-of-book mapping from canonical source offsets.
  /// EPUB keeps spine ID/context and PDF keeps physical page provenance.
  final ReadingAnchor Function(int offset)? anchorAtOffset;

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

  /// Advance the stored bookmark only after an entire utterance was heard.
  /// This is a SQLite transaction like onSegmentStarted, so a crash between
  /// two segments resumes at the next audible source offset instead of
  /// replaying an already completed clip. The recovery marker remains
  /// active until a genuinely settled Pause/Stop or book completion.
  ///
  /// A native interruption never calls this method for its partial clip.
  Future<void> onSegmentCompleted(
      SpeechSegment finished, SpeechSegment? nextAudible) async {
    final player = _player;
    // ReaderPlayer calls this only after native playback completed.
    // A concurrent Pause may set isPlaying=false while an earlier
    // asynchronous acknowledgment is still pending; that does not
    // make an already-heard clip partial. Do not discard its checkpoint.
    if (_disposed || player == null ||
        !player.isCommittingSpeechSegment) return;
    final offset = nextAudible?.start ?? finished.end;
    // A final source end belongs to an actual EPUB spine/PDF page, not
    // necessarily to the clip START (or to an arbitrary chapter). Keep
    // canonical source and context instead of degrading to a legacy
    // offset-only checkpoint when a source-offset mapper is provided.
    final anchor = nextAudible != null
        ? anchorFor(nextAudible)
        : anchorAtOffset?.call(offset);
    store.recordSpeechSegmentStart(bookId, offset, anchor: anchor);
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
    final player = _player;
    player?.removeListener(_onPlayerChanged);
    _player = null;
    // Detaching the reader is NOT proof that audio has stopped: even
    // without a Stop timeout, dispose() may run while the engine is still
    // speaking or an auto-resuming seek is awaiting its native callback.
    // Erase only after a confirmed settled idle. Preserve the crash
    // checkpoint conservatively if the player has already been disposed,
    // is playing, has a native Stop in flight, or suffered a Stop failure.
    if (player == null || player.isSettledIdle) {
      store.clearSpeechRecoveryMarker(bookId);
    }
  }
}
