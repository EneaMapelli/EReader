# Android audio focus and settled-idle transition safety

Increment: 2026-10-23, branch `feature/m0-flutter-foundation`.
Status: **code committed, unit tests authored but not run; native/device verification pending**.

## Problem addressed

`ReaderPlayer.isPlaying` becomes `false` *before* a native TTS stop
finishes, including on a Seek, narrator/cast voice change, Pause, or sleep
timer expiry. A seek/voice transition may also intend to resume immediately
after the stop. Previously, listeners could treat this temporary state as
final and either:
- Release Android audio focus while the player was about to resume, or
- Clear the transactional crash-recovery marker while a segment was still
  active or a navigation would resume.

The new `ReaderPlayer.isSettledIdle` is true **only** when:
1. `isPlaying == false`;
2. No serialized native stop is still pending;
3. There is no pending navigation/voice transition that intends to resume;
4. The player is not disposed.

`_stopCurrent` emits a final notification once each native stop settles
(including when it throws). A navigation that should resume invokes its
next `play()` *before* publishing any spurious settled-idle interval.

## Consumers

- `NarrationRecoveryBinding` clears SQLite v16 crash recovery only on
  settled idle, not during the short pause between two segments after
  a Seek or voice selection. The checkpoint is updated for each new
  utterance and retains the authoritative source anchor.
- `ReaderMediaHandler` releases Android audio focus on settled idle,
  including for **direct ReaderPlayer pauses** initiated by the sleep timer,
  reader settings or UI that do not go through media-session controls.
- Android audio-focus requests and releases run through a single queue;
  an active focus lease is reused instead of acquiring it multiple times.
  Duplicate asynchronous remote Play requests are superseded in order, so
  only the latest valid Play can actually dispatch a speech run.
- The notification state continues to reflect the player's immediate
  state; it does not falsely advertise segment durations or positions.
  No media session is created on Windows.

## Safety rules

- On a long or failing native stop, playback has already been invalidated,
  but focus is not released and the crash marker is not cleared **until the
  stop Future settles**. If an Android plugin hangs forever, these operations
  also remain pending; a bounded native-stop timeout is still a future
  integration requirement, not a claim made here.
- When a seek/voice switch is superseded by user Pause or a system audio
  interruption, resume intent is cancelled. After its last stop settles,
  normal idle cleanup and focus release occur.
- Cloud per-book consent is checked for remote Play using current active
  player preferences rather than an old widget-construction snapshot.
  Actual billable synthesis still requires the existing transactional
  character reservation/consent checks.
- There is **no** automatic restart on audio-focus gain and no automatic
  cloud synthesis on Android process restart.

## Regression tests authored (not executed)

`test/audio/reader_media_handler_test.dart` now contains 18 tests in
total. The six new checks cover:
- Pending Seek retains focus until the new segment is speaking;
- Direct reader Pause releases focus only after native stop completion;
- Sleep timer expiry releases focus without an external transport call;
- Concurrent Play requests waiting for consent do not duplicate speech;
- Concurrent Play requests waiting on audio focus claim one lease;
- A failed native stop still settles idle and triggers focus cleanup.

`test/audio/narration_recovery_binding_test.dart` now contains seven tests
in total; the three new checks verify checkpoint persistence during
pending Seek, a delayed native Pause, and a resuming voice switch.

At final integration, run `flutter analyze`, `flutter test`, Android
screen-off tests with system TTS and consented cloud TTS, lock-screen/
Bluetooth Play/Pause/Next, an actual incoming call, unplugged headphones,
a sleeping timer, and rapid switching between two books. Verify no
orphan foreground notification and inspect service traces/focus callbacks.

Related documents: [Android Background Media](ANDROID_BACKGROUND_MEDIA.md),
[Narration Crash Recovery](NARRATION_CRASH_RECOVERY.md), and
[Playback Session Safety](PLAYBACK_SESSION_SAFETY.md).
