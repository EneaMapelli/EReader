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
  // Remote headset buttons can arrive twice before a native Stop settles.
  // Keep their cumulative *requested* source target, not the old cursor.
  // Discard this intent if direct ReaderScreen controls change revision.
  int? _pendingSkipTarget;
  int? _pendingSkipRevision;
  void _clearRemoteSkipIntent() {
    _pendingSkipTarget = null;
    _pendingSkipRevision = null;
  }
  bool _closed = false;
  // All focus gains and releases are queued on one native operation chain.
  // A delayed gain must never override a newer Pause/release.
  Future<void> _focusOperation = Future<void>.value();
  bool _focusActive = false;
  // AudioSession may deliver several interruption/noisy callbacks for one
  // incident. Coalesce their Stop into one native operation per attached
  // player; a later book attachment starts with a fresh interruption scope.
  Future<void>? _interruptionPause;
  int? _interruptionControlRevision;

  bool get hasActiveBook => _player != null;

  /// A detached/obsolete ReaderScreen must never control another book.
  bool ownsPlayer(ReaderPlayer player) =>
      !_closed && identical(_player, player);

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
    _clearRemoteSkipIntent();
    _interruptionPause = null;
    _interruptionControlRevision = null;
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
    if (player != null && player.isSettledIdle) {
      // Also covers sleep-timer expiry and direct UI pause. A temporary
      // isPlaying=false during a seek is NOT a settled idle state.
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

  Future<bool> _claimAudioFocus() {
    final previous = _focusOperation;
    final settled = Completer<void>();
    _focusOperation = settled.future;
    return () async {
      try {
        await previous;
        if (_focusActive) return true;
        final acquired = _requestFocus != null
            ? await _requestFocus()
            : (await _session?.setActive(true) ?? true);
        _focusActive = acquired;
        return acquired;
      } finally {
        settled.complete();
      }
    }();
  }

  Future<void> _releaseAudioFocus() {
    final previous = _focusOperation;
    final settled = Completer<void>();
    _focusOperation = settled.future;
    return () async {
      try {
        await previous;
        if (!_focusActive) return;
        try {
          if (_releaseFocusOverride != null) {
            await _releaseFocusOverride();
          } else {
            await _session?.setActive(false);
          }
        } catch (_) {
          // Android may already have disposed the native audio session.
        } finally {
          _focusActive = false;
        }
      } finally {
        settled.complete();
      }
    }();
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (_closed || player == null || player.isPlaying ||
        player.segments.isEmpty) return;
    _clearRemoteSkipIntent();
    // Never acquire focus or dispatch billable/cloud narration while an
    // older native utterance might still be playing after Stop timed out.
    if (player.nativeStopUnconfirmed) {
      throw StateError('Native speech Stop not confirmed; playback is locked');
    }
    final epoch = _bindingEpoch;
    // Two Play requests may both wait on cloud consent or native focus.
    // Only the most recent request may initiate a new playback session.
    final command = ++_commandEpoch;

    // Remote headset/lock-screen controls must honor the same per-book
    // consent gate as the in-reader Play button.
    if (_canStart != null && !await _canStart!()) {
      throw StateError('Cloud speech consent is not enabled for this book');
    }
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch) return;
    if (!await _claimAudioFocus()) {
      if (_closed || !identical(_player, player) ||
          epoch != _bindingEpoch || command != _commandEpoch) return;
      throw StateError('Cannot obtain Android audio focus');
    }
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch ||
        player.nativeStopUnconfirmed) {
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
    // Invalidate pending remote Play even when focus acquisition is still
    // awaiting Android and ReaderPlayer itself never started speaking.
    _commandEpoch++;
    _clearRemoteSkipIntent();
    final player = _player;
    if (player == null) return;
    if (player.isSettledIdle) {
      // No native utterance and no seek/voice auto-resume exist. Calling
      // SpeechEngine.stop here would create a needless native round trip
      // and can interrupt a newly attached book's media pipeline.
      await _releaseAudioFocus();
      return;
    }
    try {
      await player.pause();
    } finally {
      // The listener releases focus when native Stop actually settles.
      // Await that queued release before resolving the transport command.
      if (identical(player, _player) && player.isSettledIdle) {
        await _focusOperation;
      }
    }
  }

  /// Stop means stop the current utterance, not delete its book position.
  @override
  Future<void> stop() => pause();

  /// Treat physical media-button presses as individual source steps even
  /// while Stop/Seek awaits the native platform or a SQLite checkpoint.
  /// ReaderPlayer already enforces latest-navigation-wins; this layer must
  /// keep the *requested* cursor for successive remote commands.
  Future<void> _skipRemote(int delta) async {
    _commandEpoch++;
    final player = _player;
    if (_closed || player == null || player.segments.isEmpty) return;
    final previousTarget = _pendingSkipTarget;
    final base = previousTarget != null &&
            _pendingSkipRevision == player.narrationControlRevision
        ? previousTarget : player.intendedNavigationIndex;
    final length = player.segments.length;
    final target = (base + delta).clamp(0, length).toInt();
    // Explicit EOF is a silent source position, never a replay of the
    // final spoken segment. Repeated Next at EOF is an idempotent no-op.
    // Media Play from EOF remains an explicit user restart from chapter 1.
    if (target == length && player.currentIndex == length &&
        player.isSettledIdle) {
      _clearRemoteSkipIntent();
      return;
    }
    _pendingSkipTarget = target;
    final moving = target == length
        ? player.seekToSourceEnd()
        : player.seekTo(target);
    // Seek increments its revision synchronously before the first await.
    // Capture that revision NOW so another press arriving during native
    // Stop adds a step rather than calculating from the stale cursor.
    _pendingSkipRevision = player.narrationControlRevision;
    await moving;
  }

  @override
  Future<void> skipToNext() => _skipRemote(1);

  @override
  Future<void> skipToPrevious() => _skipRemote(-1);

  /// Conservative policy for calls, competing audio and unplugged
  /// headphones: pause; NEVER auto-resume on a focus-gain event.
  ///
  /// Returnable Future supports deterministic control-plane tests and
  /// allows repeated native interruptions to share one Stop barrier.
  void _trackSystemInterruption(Future<void> pausing) {
    _interruptionPause = pausing;
    // The previous Stop may complete after a more recent interruption.
    // Only the latest tracked Future may reset the pending interruption.
    void clearIfLatest() {
      if (identical(_interruptionPause, pausing)) {
        _interruptionPause = null;
        _interruptionControlRevision = null;
      }
    }
    unawaited(pausing.then<void>((_) => clearIfLatest(),
        onError: (Object _, StackTrace __) => clearIfLatest()));
  }

  Future<void> pauseForSystemInterruption() {
    final player = _player;
    if (_closed || player == null) return Future<void>.value();
    final pending = _interruptionPause;
    if (pending != null) {
      // A duplicate phone/noisy callback must invalidate queued remote
      // Play, but sharing the old Stop is safe ONLY if the player itself
      // has not started another Play/Seek/voice change in the meantime.
      // ReaderScreen can control ReaderPlayer directly, bypassing this
      // handler's _commandEpoch. Without the revision check, a fresh
      // direct Play can resume once the old Stop gate finally settles.
      _commandEpoch++;
      if (_interruptionControlRevision == player.narrationControlRevision) {
        return pending;
      }
      // A newer direct operation superseded the first interruption.
      // Reassert Pause and await BOTH Stop paths. The original pending
      // interruption is still observed, and a duplicate of this new
      // event will once again share its Future without a third Stop.
      final latest = pause();
      _interruptionControlRevision = player.narrationControlRevision;
      final combined =
          Future.wait<void>([pending, latest]).then<void>((_) {});
      _trackSystemInterruption(combined);
      return combined;
    }
    // A seek/voice switch may have isPlaying=false yet be about to
    // resume. Only an explicit Pause invalidates that navigation.
    final pausing = pause();
    _interruptionControlRevision = player.narrationControlRevision;
    _trackSystemInterruption(pausing);
    return pausing;
  }

  void handleSystemInterruption() {
    unawaited(pauseForSystemInterruption()
        .catchError((Object _, StackTrace __) {
      // AudioSession events must not expose uncaught platform errors.
      // Native Stop failures remain recorded by ReaderPlayer; its crash
      // checkpoint stays intact until Stop is confirmed.
    }));
  }

  /// Swiping away the Android task is a deliberate end of the active
  /// reading session. Never synthesize an orphaned book after task removal.
  @override
  Future<void> onTaskRemoved() async {
    try {
      await pause();
    } finally {
      // Do not leave a service-controlled book behind if native stop throws.
      detach();
      await _focusOperation;
    }
  }

  /// Notification dismissal must not silently auto-resume narration.
  /// Keep the reader binding if the app UI is still open.
  @override
  Future<void> onNotificationDeleted() => pause();

  /// Release native stream listeners only during application shutdown.
  Future<void> close() async {
    if (_closed) return;
    detach();
    _closed = true;
    await _interruption?.cancel();
    await _noisy?.cancel();
    await _focusOperation;
  }
}
