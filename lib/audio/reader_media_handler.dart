import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'reader_player.dart';

/// Android media-session façade around the single ReaderPlayer. The player
/// remains the source of truth for progress, source anchors, voice changes
/// and cloud consent. This handler never creates a second audio stream.
///
/// It is constructed by AudioService.init on Android only, and can also be
/// instantiated with an injected focus callback for non-native unit tests.
class ReaderMediaHandler extends BaseAudioHandler {
  ReaderMediaHandler({
    AudioSession? audioSession,
    Future<bool> Function()? requestFocus,
    Future<void> Function()? releaseFocus,
  }) : _session = audioSession,
       _requestFocus = requestFocus,
       _releaseFocusOverride = releaseFocus {
    if (audioSession != null) {
      _interruption = audioSession.interruptionEventStream.listen((event) {
        // No automatic resume: a transient phone call or navigation prompt
        // must not unexpectedly start cloud synthesis after interruption.
        // TTS engines cannot reliably duck both native and cloud output.
        if (event.begin) handleSystemInterruption();
      });
      _noisy = audioSession.becomingNoisyEventStream.listen((_) {
        handleSystemInterruption();
      });
    }
    _publish();
  }

  final AudioSession? _session;
  final Future<bool> Function()? _requestFocus;
  final Future<void> Function()? _releaseFocusOverride;
  StreamSubscription<AudioInterruptionEvent>? _interruption;
  StreamSubscription<void>? _noisy;

  ReaderPlayer? _player;
  Future<bool> Function()? _canStart;
  int _bindingEpoch = 0;
  int _commandEpoch = 0;
  bool _closed = false;

  bool get hasActiveBook => _player != null;

  /// Only the reader currently displayed may own the external controls.
  /// Closing the page deliberately clears media metadata and controls.
  void attach(ReaderPlayer player, {
    required String bookId,
    required String title,
    Future<bool> Function()? canStart,
  }) {
    if (_closed) throw StateError('Media handler has been closed');
    detach();
    _player = player;
    _canStart = canStart;
    player.addListener(_onPlayerChanged);
    final bookItem = MediaItem(id: bookId, title: title, album: 'EReader');
    mediaItem.add(bookItem);
    queue.add([bookItem]);
    _publish();
  }

  void detach([ReaderPlayer? expected]) {
    if (expected != null && !identical(expected, _player)) return;
    _bindingEpoch++;
    _commandEpoch++;
    _player?.removeListener(_onPlayerChanged);
    _player = null;
    _canStart = null;
    queue.add(const []);
    mediaItem.add(null);
    _publish();
    unawaited(_releaseAudioFocus());
  }

  void _onPlayerChanged() {
    if (_closed) return;
    _publish();
    final player = _player;
    if (player != null && !player.isPlaying &&
        (player.currentIndex >= player.segments.length ||
         player.lastError != null)) {
      unawaited(_releaseAudioFocus());
    }
  }

  void _publish() {
    if (_closed) return;
    final player = _player;
    if (player == null) {
      playbackState.add(PlaybackState(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
      return;
    }

    final completed = player.currentIndex >= player.segments.length;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        player.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: player.lastError != null
          ? AudioProcessingState.error
          : completed
              ? AudioProcessingState.completed
              : AudioProcessingState.ready,
      playing: player.isPlaying,
      // Source segments do not have reliable timing. Never advertise
      // fake elapsed seconds or seek actions to the OS.
      queueIndex: 0,
    ));
  }

  Future<bool> _claimAudioFocus() async {
    if (_requestFocus != null) return _requestFocus();
    return await _session?.setActive(true) ?? true;
  }

  Future<void> _releaseAudioFocus() async {
    try {
      if (_releaseFocusOverride != null) {
        await _releaseFocusOverride();
      } else {
        await _session?.setActive(false);
      }
    } catch (_) {
      // Native audio session may already be torn down by Android.
    }
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (_closed || player == null || player.isPlaying ||
        player.segments.isEmpty) return;
    final epoch = _bindingEpoch;
    final command = _commandEpoch;

    // Remote headset/lock-screen controls must honor the same per-book
    // consent gate as the in-reader Play button.
    if (_canStart != null && !await _canStart!()) {
      throw StateError('Cloud speech consent is not enabled for this book');
    }
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch) return;
    if (!await _claimAudioFocus()) {
      throw StateError('Cannot obtain Android audio focus');
    }
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch) {
      // detach/pause/new commands own any required focus release.
      // A stale play must not release a newer successful play's focus.
      return;
    }
    // ReaderPlayer.play() finishes only at the end of the entire book.
    // AudioHandler.play must return after dispatching, otherwise Android
    // transport requests stay pending until all chapters finish.
    unawaited(player.play().catchError((Object _, StackTrace __) {
      // ReaderPlayer records lastError and notifies its listeners.
      // Consume the future to avoid unhandled platform exceptions.
    }));
  }

  @override
  Future<void> pause() async {
    _commandEpoch++;
    final player = _player;
    if (player == null) return;
    await player.pause();
    if (identical(player, _player) && !player.isPlaying) {
      await _releaseAudioFocus();
    }
  }

  /// Stop means stop the current utterance, not delete its book position.
  @override
  Future<void> stop() => pause();

  @override
  Future<void> skipToNext() async {
    _commandEpoch++;
    final player = _player;
    if (player == null || player.segments.isEmpty) return;
    await player.seekTo(player.currentIndex + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    _commandEpoch++;
    final player = _player;
    if (player == null || player.segments.isEmpty) return;
    await player.seekTo(player.currentIndex - 1);
  }

  /// Conservative policy for phone calls, competing audio and unplugged
  /// headphones: pause; never resume on a subsequent focus-gain event.
  void handleSystemInterruption() {
    _commandEpoch++;
    final player = _player;
    if (player == null || !player.isPlaying) return;
    unawaited(pause().catchError((Object _, StackTrace __) {
      // Native stop errors are not permitted to crash an event subscription.
    }));
  }

  /// Release native stream listeners only during application shutdown.
  Future<void> close() async {
    if (_closed) return;
    detach();
    _closed = true;
    await _interruption?.cancel();
    await _noisy?.cancel();
  }
}
