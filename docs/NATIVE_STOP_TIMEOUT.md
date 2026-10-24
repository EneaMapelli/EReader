# Bounded native TTS Stop — fail-closed timeout policy

Increment: 2026-10-23, branch `feature/m0-flutter-foundation`.
**Implemented in source; analyzer, Flutter tests, builds and device validation have not been run.**

## Why a timeout is not a completed Stop

System TTS or a provider adapter may never complete `SpeechEngine.stop()`
because of a stalled platform MethodChannel, driver or media backend.
Waiting without a limit makes the reader's Pause, Seek, sleep timer,
voice switch or Android MediaSession command hang indefinitely.

`ReaderPlayer.nativeStopTimeout` defaults to **8 seconds** and can be
injected in tests. `SpeechStopTimeout` reports a bounded wait to the
caller. Importantly, **ending that wait does not cancel the underlying
native Stop Future and does not prove the audio stopped**.

## State and safety contract

- A timed-out Stop marks `nativeStopUnconfirmed` and sets `lastError`.
  `isSettledIdle` remains false; no new `play()` is permitted.
- A remote Android Play checks the uncertain-stop state **before**
  requesting focus or starting synthesis, preventing unintended API use.
- The player invalidates outstanding narration/session/navigation epochs,
  including Play that was waiting for the same Stop and a Seek/voice
  change that would otherwise restart automatically.
- The real native Future remains observed. If it eventually completes
  **successfully**, the uncertain state clears and the player stays paused.
  Only a new **explicit Play** can start narration again.
- A native Stop that fails (immediately or after the timeout) remains
  unsafe for that `ReaderPlayer` instance. It cannot reuse the failed
  engine for further speech. A fresh engine may be needed, but disposing
  a misbehaving engine is not proof of successful native output shutdown.
- When Stop remains pending, Android retains its existing audio-focus lease
  while the media handler owns the reader. If the reader is closed, the
  service detaches by its existing lifecycle policy; this cannot guarantee
  that a hung native engine has stopped producing sound.
- The SQLite v16 crash-recovery checkpoint is **not** cleared while
  native Stop is unconfirmed. In particular, `NarrationRecoveryBinding`
  preserves it even if the user closes that reader, so the next app
  session can offer manual recovery without automatically speaking.
  If the stop eventually confirms success after the binding is disposed,
  the conservative recovery marker may remain: this favors avoiding
  a false clean-shutdown claim.

## Operational caveats

- This is a **bounded wait**, not a native OS watchdog, forced termination,
  cancelable Dart Future, proof of acoustic silence or Android foreground
  service recovery. The engine might remain active after timeout.
- Cloud generation already in progress cannot be assumed to be unbilled.
  No retry or extra synthesis is initiated automatically.
- Timer deadlines are session-only and do not survive process death.
- Pending lookahead/cloud requests and OS audio focus still require real
  Android/Windows verification.
- The media-session error status is visible through the player's
  `lastError`; exact accessibility and notification UX remain untested.

## Authored regression coverage — NOT executed

`test/audio/native_stop_timeout_test.dart` has eight tests:

1. Hung Stop returns `SpeechStopTimeout` and denies overlap.
2. A late success leaves narration paused until explicit Play.
3. A timed-out Seek cannot resume a stale segment.
4. A Play queued before the timeout is invalidated.
5. Repeated Pause cannot launch another Stop while uncertain.
6. Immediate or late native Stop error does not unlock the engine.
7. Android MediaSession Play rejects uncertain native Stop before focus.
8. A strictly positive timeout is required.

`test/audio/narration_recovery_binding_test.dart` additionally covers
closing the reader with uncertain native Stop while preserving its
SQLite recovery marker. Existing focus/Seek/Sleep timer tests remain
authored but unexecuted.

Final validation: `flutter analyze`, `flutter test`, then Android
device testing with TTS platforms that hang/fail on Stop, headset
removal, rapid Play/Pause/Seek, screen lock, task swipe, a call, an
expiring sleep timer, and both system/cloud providers. Check for
unwanted overlapping speech and compare audio focus/recovery marker
state against the actual system output.

See [Audio Transition Safety](AUDIO_TRANSITION_SAFETY.md),
[Narration Crash Recovery](NARRATION_CRASH_RECOVERY.md), and
[Android Background Media](ANDROID_BACKGROUND_MEDIA.md).
