import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

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
  // Only EPUB passes real spine-derived narration boundaries. Plain TXT/PDF
  // preserve their historic single-segment transport behavior.
  List<int> _chapterSegmentStarts = const [];
  void Function(int segmentIndex)? _onRemoteNavigation;
  void _clearRemoteSkipIntent() {
    _pendingSkipTarget = null;
    _pendingSkipRevision = null;
  }
  bool _closed = false;
  // Share the entire asynchronous shutdown, not only the initial detach.
  // Concurrent Android lifecycle/dispose callers must await the same native
  // Stop and focus-release fences, including after _closed becomes true.
  Future<void>? _closeFuture;
  // All focus gains and releases are queued on one native operation chain.
  // A delayed gain must never override a newer Pause/release.
  Future<void> _focusOperation = Future<void>.value();
  bool _focusActive = false;
  // A new book must not start audible speech until an old handler-owned
  // Pause or remote Seek has confirmed its native Stop. Persist this
  // barrier across detach/attach; resetting it at book handoff could
  // allow two different speech engines to speak simultaneously.
  Future<bool> _pendingTransportStops = Future<bool>.value(true);
  bool _transportStopUnsafe = false;
  // Remember only players whose Stop fences failed. A confirmed Stop
  // requires no retained reference to a book that has already closed.
  final Set<ReaderPlayer> _unsafeStopPlayers = {};
  int _transportBarrierRevision = 0;
  // Concurrent explicit Play requests must join the same verification
  // rather than having one recovery reset the barrier under the other.
  Future<bool>? _pendingRecovery;

  /// A previous Stop was not confirmed by its deadline. Recovery is
  /// possible only after every affected native engine actually confirms
  /// silence; a genuine native Stop failure stays locked.
  bool get requiresFreshAudioSession => _transportStopUnsafe;

  // Diagnostics only; never expose book IDs or speech content. A closed
  // handler must not retain failed players solely for impossible retries.
  @visibleForTesting
  int get debugRetainedStopPlayers => _unsafeStopPlayers.length;

  void _trackNativeConfirmation(
    Future<bool> confirmation, ReaderPlayer player,
  ) {
    _transportBarrierRevision++;
    final earlier = _pendingTransportStops;
    // Retain the failing engine, not merely the combined failure state.
    // The whole barrier stays fail-closed until a separate explicit
    // recovery verifies every unresolved source player.
    _pendingTransportStops = Future.wait<bool>([earlier, confirmation])
        .then((results) {
      // Shutdown is terminal: even a late native Stop failure must not
      // retain the disposed book/player after close() has started.
      if (!results[1] && !_closed) _unsafeStopPlayers.add(player);
      final confirmed = results.every((value) => value);
      if (!confirmed && !_transportStopUnsafe) {
        _transportStopUnsafe = true;
        _publish();
      }
      return confirmed;
    });
  }

  void _trackTransportStop(Future<void> stopping, ReaderPlayer player) {
    // Consume the old operation's Future immediately, including storage
    // or navigation failures. A failed operation can be rearmed only
    // after the player's actual native Stop is separately confirmed.
    _trackNativeConfirmation(stopping.then<bool>(
      (_) => true, onError: (Object _, StackTrace __) => false,
    ), player);
  }

  /// Re-arm the same MediaSession only after a *late positive* Stop
  /// acknowledgment from every engine that made the handoff unsafe.
  /// Never interpret timeout, native exception, or missing acknowledgment
  /// as silence. Called only in response to a new explicit Play request;
  /// focus gain/interruption callbacks never initiate playback.
  Future<bool> tryRecoverAfterConfirmedNativeStops() {
    if (_closed || _closeFuture != null) return Future<bool>.value(false);
    return _pendingRecovery ??=
        _recoverAfterConfirmedNativeStops().whenComplete(() {
      // The shared verification is complete; a future user Play may
      // inspect new information from a newly acknowledged native Stop.
      _pendingRecovery = null;
    });
  }

  Future<bool> _recoverAfterConfirmedNativeStops() async {
    if (_closed || _closeFuture != null) return false;
    final pending = _pendingTransportStops;
    final revision = _transportBarrierRevision;
    // Direct ReaderScreen navigation bypasses the handler's command epoch
    // and Stop tracker. Preserve its revision as part of recovery identity.
    final recoveryPlayer = _player;
    final recoveryControl = recoveryPlayer?.narrationControlRevision;
    final confirmed = await pending;
    // Even an initially successful Stop can settle after a later
    // detach/attach or close. An obsolete recovery query must never
    // report ownership of a newly bound or already closed MediaSession.
    if (_closed || _closeFuture != null ||
        revision != _transportBarrierRevision ||
        !identical(pending, _pendingTransportStops) ||
        !identical(recoveryPlayer, _player) ||
        recoveryPlayer?.narrationControlRevision != recoveryControl) return false;
    if (confirmed) return true;
    final unsafePlayers = _unsafeStopPlayers.toList(growable: false);
    if (unsafePlayers.isEmpty) return false;
    for (final player in unsafePlayers) {
      // Once a player has already timed out, it must not spend a second
      // nativeStopTimeout waiting for the same unacknowledged operation.
      // Retry becomes eligible only AFTER its late positive callback
      // has cleared nativeStopUnconfirmed.
      if (player.isPlaying || player.nativeStopUnconfirmed ||
          !await player.waitForNativeStopConfirmation()) {
        return false;
      }
    }
    // A new Stop or book handoff while verifying old engines invalidates
    // this recovery. Never clear a newer failure with an older success.
    if (_closed || _closeFuture != null ||
        revision != _transportBarrierRevision ||
        !identical(pending, _pendingTransportStops) ||
        !identical(recoveryPlayer, _player) ||
        recoveryPlayer?.narrationControlRevision != recoveryControl ||
        unsafePlayers.any((player) => player.isPlaying ||
            player.nativeStopUnconfirmed)) return false;
    // A direct Pause/Seek may be stopping the current book without
    // touching the handler's transport barrier. Never re-arm while
    // that current native engine is still transitioning or unsafe.
    if (recoveryPlayer != null && !recoveryPlayer.isSettledIdle) {
      return false;
    }
    _unsafeStopPlayers.clear();
    _pendingTransportStops = Future<bool>.value(true);
    _transportStopUnsafe = false;
    _publish();
    return true;
  }
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
    List<int> chapterSegmentStarts = const [],
    void Function(int segmentIndex)? onRemoteNavigation,
  }) {
    if (_closed) throw StateError('Media handler has been closed');
    detach();
    _player = player;
    _canStart = canStart;
    _onRemoteNavigation = onRemoteNavigation;
    // The source-backed EPUB spine can contain empty/illustrated chapters.
    // Only actual spoken boundaries belong in remote audio navigation.
    // Make a defensive, sorted, deduplicated snapshot for the book session.
    final starts = chapterSegmentStarts
        .where((index) => index >= 0 && index < player.segments.length)
        .toSet()
        .toList()..sort();
    _chapterSegmentStarts = starts.isEmpty
        ? const []
        : List<int>.unmodifiable({0, ...starts}.toList()..sort());
    player.addListener(_onPlayerChanged);
    final bookItem = MediaItem(id: bookId, title: title, album: 'EReader');
    mediaItem.add(bookItem);
    queue.add([bookItem]);
    _publish();
  }

  void detach([ReaderPlayer? expected]) {
    if (expected != null && !identical(expected, _player)) return;
    final outgoing = _player;
    if (outgoing != null) {
      // The UI can call ReaderPlayer.pause/seekTo without going through
      // this handler. Capture that in-flight native Stop before handing
      // audio focus to a new book. Also cancel a pending Seek's *latent*
      // auto-resume (isPlaying may already be false during native Stop).
      if (!outgoing.isSettledIdle) {
        _trackTransportStop(outgoing.pause(), outgoing);
      }
      _trackNativeConfirmation(
          outgoing.waitForNativeStopConfirmation(), outgoing);
    }
    _bindingEpoch++;
    _commandEpoch++;
    _clearRemoteSkipIntent();
    _interruptionPause = null;
    _interruptionControlRevision = null;
    _chapterSegmentStarts = const [];
    _onRemoteNavigation = null;
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
    final unsafeNativeStop =
        _transportStopUnsafe || player.nativeStopUnconfirmed;
    playbackState.add(PlaybackState(
      // Do not advertise actionable Play/Skip buttons when native speech
      // may still be audible. The user must restart the audio service
      // rather than repeatedly triggering the same safety exception.
      controls: unsafeNativeStop ? const [] : [
        MediaControl.skipToPrevious,
        player.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      androidCompactActionIndices:
          unsafeNativeStop ? const [] : const [0, 1, 2],
      processingState: unsafeNativeStop || player.lastError != null
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
    // ReaderScreen can invoke ReaderPlayer.pause/seekTo directly, outside
    // the handler. A newer direct command must also cancel this Play.
    final control = player.narrationControlRevision;

    // Remote headset/lock-screen controls must honor the same per-book
    // consent gate as the in-reader Play button. Consent checks can take
    // time (e.g. disk/platform preferences). While they run, the user
    // might pause, request a newer Play, or open another book. Do not
    // report a stale denial/exception for a session that no longer owns
    // the media controls.
    final canStart = _canStart;
    bool permitted;
    try {
      permitted = canStart == null || await canStart();
    } catch (_) {
      if (_closed || !identical(_player, player) ||
          epoch != _bindingEpoch || command != _commandEpoch ||
          player.narrationControlRevision != control) return;
      rethrow;
    }
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch ||
        player.narrationControlRevision != control) return;
    if (!permitted) {
      throw StateError('Cloud speech consent is not enabled for this book');
    }
    // Audio focus serialization alone is insufficient: native speech Stop
    // may still be outstanding from an earlier attached book.
    final oldStopConfirmed = await _pendingTransportStops;
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch ||
        player.narrationControlRevision != control) return;
    if (!oldStopConfirmed) {
      final recovered = await tryRecoverAfterConfirmedNativeStops();
      if (_closed || !identical(_player, player) ||
          epoch != _bindingEpoch || command != _commandEpoch ||
          player.narrationControlRevision != control) return;
      if (!recovered) {
        throw StateError('Previous native speech Stop is unconfirmed. '
            'Try Play again after Stop completes; restart audio if it failed.');
      }
    }
    bool focused;
    try {
      focused = await _claimAudioFocus();
    } catch (_) {
      // A platform focus error may arrive after a newer Play, Pause or
      // book attachment. The obsolete request no longer owns this
      // MediaSession, and must not surface an unrelated failure.
      if (_closed || !identical(_player, player) ||
          epoch != _bindingEpoch || command != _commandEpoch ||
          player.narrationControlRevision != control) return;
      rethrow;
    }
    if (_closed || !identical(_player, player) ||
        epoch != _bindingEpoch || command != _commandEpoch ||
        player.narrationControlRevision != control) return;
    if (!focused) {
      throw StateError('Cannot obtain Android audio focus');
    }
    if (player.nativeStopUnconfirmed) {
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
    final stopping = player.pause();
    _trackTransportStop(stopping, player);
    try {
      await stopping;
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

  // Binary search to find the next/previous *narratable* chapter.
  // From inside a chapter, Previous restarts that chapter; at the start
  // it goes to the preceding chapter. Past the final chapter, Next goes
  // to silent speech EOF. A source-exact visual chapter jump remains the
  // responsibility of ReaderScreen, never speculative cloud synthesis.
  int _skipTarget(int base, int direction, int total) {
    final starts = _chapterSegmentStarts;
    if (starts.isEmpty) return (base + direction).clamp(0, total).toInt();
    var low = 0;
    var high = starts.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (starts[mid] < base) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (direction < 0) {
      return low == 0 ? 0 : starts[low - 1];
    }
    // Exact chapter starts are not a Next destination; seek beyond them.
    if (low < starts.length && starts[low] == base) low++;
    return low == starts.length ? total : starts[low];
  }

  /// Treat physical media-button presses as individual source steps even
  /// while Stop/Seek awaits the native platform or a SQLite checkpoint.
  /// ReaderPlayer already enforces latest-navigation-wins; this layer must
  /// keep the *requested* cursor for successive remote commands.
  Future<void> _skipRemote(int delta) async {
    final command = ++_commandEpoch;
    final binding = _bindingEpoch;
    final player = _player;
    if (_closed || player == null || player.segments.isEmpty) return;
    final previousTarget = _pendingSkipTarget;
    final base = previousTarget != null &&
            _pendingSkipRevision == player.narrationControlRevision
        ? previousTarget : player.intendedNavigationIndex;
    final length = player.segments.length;
    final target = _skipTarget(base, delta, length);
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
    _trackTransportStop(moving, player);
    // Seek increments its revision synchronously before the first await.
    // Capture that revision NOW so another press arriving during native
    // Stop adds a step rather than calculating from the stale cursor.
    final revision = player.narrationControlRevision;
    _pendingSkipRevision = revision;
    try {
      await moving;
      // An older request or detached book must never drag the visual
      // cursor back after a newer navigation (or emit a stale bookmark).
      if (!_closed && identical(_player, player) &&
          _pendingSkipRevision == revision &&
          player.currentIndex == target &&
          player.intendedNavigationIndex == target) {
        // A successful Seek may have already auto-resumed Play. Play
        // increments the control revision again, but that must NOT
        // suppress visual synchronization for the winning chapter.
        _onRemoteNavigation?.call(target);
      }
    } catch (_) {
      // A native Stop/Seek may fail after another headset command,
      // direct Pause or book handoff. Only the still-owning remote
      // request may surface that error to the Android transport.
      if (_closed || !identical(_player, player) ||
          binding != _bindingEpoch || command != _commandEpoch ||
          _pendingSkipRevision != revision) return;
      rethrow;
    } finally {
      // Preserve accumulation only while a remote skip is still pending.
      // Otherwise a later press after natural speech advancement would
      // incorrectly step from an obsolete media target.
      if (identical(_player, player) && _pendingSkipRevision == revision) {
        _clearRemoteSkipIntent();
      }
    }
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

  /// Swiping away the Android task ends the binding that received the
  /// removal. A newer book may attach while native Stop is still pending;
  /// never detach its MediaSession when the old Stop eventually settles.
  @override
  Future<void> onTaskRemoved() async {
    final removedBinding = _bindingEpoch;
    try {
      await pause();
    } finally {
      // attach/detach increments the epoch, including when a player is
      // rebound with a different book. Clean up only the original binding.
      // A failed Stop still detaches that session and releases its focus.
      if (removedBinding == _bindingEpoch) {
        detach();
        await _focusOperation;
      }
    }
  }

  /// Notification dismissal must not silently auto-resume narration.
  /// Keep the reader binding if the app UI is still open.
  @override
  Future<void> onNotificationDeleted() => pause();

  /// Release native stream listeners only during application shutdown.
  /// Multiple callers share completion of the same shutdown, rather than
  /// treating _closed as proof that native cleanup has already finished.
  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    detach();
    _closed = true;
    await _interruption?.cancel();
    await _noisy?.cancel();
    await _focusOperation;
    // A close initiated during narration must not report completion
    // while the detached book's native Stop is still outstanding.
    try {
      await _pendingTransportStops;
    } finally {
      // No re-arm is possible after _closed. Drop references to old
      // ReaderPlayer instances, including an engine whose native Stop
      // timed out. Preserve the unsafe latch; close is irreversible.
      _unsafeStopPlayers.clear();
      _pendingRecovery = null;
    }
  }
}
