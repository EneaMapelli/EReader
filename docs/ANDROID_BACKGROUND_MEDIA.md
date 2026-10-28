# Android background speech and media controls (M2/M3 increment)

Status: **implemented in source, not yet compiled or tested on Android**.
Branch: `feature/m0-flutter-foundation`.

## Scope

- `audio_service 0.18.19` registers a media service and exposes Android media
  notification / lock-screen / wired and Bluetooth headset transport actions.
- `audio_session 0.2.4` configures speech audio focus. A focus interruption
  (including ducking), an unknown interruption or headphone removal pauses
  speech conservatively; audio never auto-resumes.
- `ReaderMediaHandler` maps OS Play/Pause/Stop/Next/Previous to the existing
  `ReaderPlayer`, which remains the **only** audio cursor and cast/consent
  implementation. No second audio queue, duplicate TTS stream, word timing,
  fabricated seek bar or chapter-clock offsets were introduced.
- Only **Android** constructs `AudioService`. Windows keeps the original reader
  route and does not initialize an unsupported Windows service plugin.
- A bound book produces the notification title; the notification is removed
  when its reader page is closed. The foreground service is kept during pause
  while a reader is bound to avoid Android 12+ foreground-service restart
  restrictions. Unbinding clears its media item and sends the idle state.
- Lock-screen / headset Play performs a fresh **per-book cloud consent check**
  before acquiring focus or invoking `ReaderPlayer.play`. Future requests
  remain subject to the engine's existing cloud quota, credentials and cache
  checks. The service never fetches an extra segment on its own.
- If focus activation or media-service initialization fails, playback isn't
  auto-started. The app can continue reading locally if the service did not
  initialize. An error from the reader's own Play control is surfaced to the
  existing UI; remote-only failures require real-device observation.
- Navigation to another book unbinds the prior player. Late authorization,
  audio-focus requests and old view disposals cannot start an obsolete book.
  System audio interruptions only pause; they cannot trigger a new paid
  generation or silently change voice, speaker attribution or progress.

## Bootstrap

The native `android/` platform project is still generated, not checked in.
After `flutter create`, `tool/bootstrap.sh` and `tool/bootstrap.ps1` copy
`tool/android/AndroidManifest.xml` to the generated Android source directory.
This template configures:

- `AudioServiceActivity` as the launcher; `AudioService` with
  `foregroundServiceType="mediaPlayback"`, and `MediaButtonReceiver`.
- `WAKE_LOCK`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` and `INTERNET` permissions.
- Flutter's standard launch theme, embedding marker and Android text-processing
  query.

Review the full generated/merged release manifest and plugin permissions
before shipping. Re-run the bootstrap copy whenever Flutter regenerates the
platform directory. Package ID, min/target SDK and notifications must be
checked on actual target devices.

## Session guarantees and deliberate limitations

1. While the ReaderScreen is alive, locking the screen should allow Android to
   route media controls to the foreground media service. This **is not yet
   verified on a device** and cannot guarantee survival after OS process death.
2. Back navigation intentionally stops/disposes the current `ReaderPlayer` and
   detaches media controls. No orphaned background speech or book switching is
   attempted without an active reading page.
3. Restarting the Android process does **not** silently restore the last book,
   request cloud synthesis or start speaking: the user must reopen the reader.
   SQLite v16 now provides a crash-only **manual reopening notice** when
   narration may have been interrupted, but headless service reconstruction
   remains future work ([details](NARRATION_CRASH_RECOVERY.md)).
4. System native TTS may still restart the current segment after pause; cloud
   audio is sequential with one-ahead opt-in prefetch, not guaranteed gapless.
5. Audio focus is conservative: ducking also pauses because mixed TTS engines
   cannot guarantee uniform volume ducking. No automatic resume after a call.
6. The Android MediaSession advertises no duration/seek timestamp because
   sentence-level speech has no reliable wall-clock mapping. Next/Previous
   moves across original source segments, not invented time units.
7. Android Auto browsing, Bluetooth reconnection policy, background timers
   while process is killed, user-visible audio focus notifications, notification
   icon polishing and accessibility are still release work.

## Authored tests and final integration checklist

`test/audio/reader_media_handler_test.dart` contains eighteen authored but
**unexecuted** unit tests: metadata lifecycle, nonblocking Play and transport
seek, remote consent denial, denied/delayed focus, serialized focus release,
interruption without auto-resume, in-flight seek interruption, stale book
replacement, late granted focus cleanup, task removal/stop failures and
notification dismissal. Three additional lifecycle policy tests live in
`test/audio/reader_lifecycle_policy_test.dart`.

On a real Android device, once the user elects to compile:

1. Bootstrap Flutter and run `flutter pub get`, `flutter analyze` and
   `flutter test`. Inspect AndroidManifest merger output.
2. Start OS TTS, lock screen, use media controls, wired and Bluetooth controls.
   Validate foreground notification and doze/battery-restriction behavior.
3. Take a call or start another audio app. Verify pause without surprise resume,
   no overlapping voices, no duplicate source segments and no lost anchors.
4. Unplug headphones while narrating. Verify immediate pause with no speaker
   or text-position corruption.
5. Repeat with consented OpenAI Speech; revoke consent while paused and ensure
   a remote Play cannot transmit billable text. Confirm quota/prefetch semantics.
6. Switch reader books, dismiss reader, rapid play/pause/skip/voice changes,
   expire a sleep timer and test service teardown without any orphan audio.
7. Try Android 12/13/14/15/16, including screen-off for a long chapter and
   low-memory process restart; document vendor-specific failures.
8. Build Windows to verify importing the Android-only service has no impact
   when it isn't initialized.

## References

- https://pub.dev/packages/audio_service
- https://pub.dev/packages/audio_session
- https://developer.android.com/media/media3/session/background-playback

## Recent lifecycle hardening

- Native audio focus gains and releases now share a serialized operation
  queue, including delayed grants made obsolete by a newer Pause.
- `onTaskRemoved` pauses and detaches media items (also if the native stop
  fails); `onNotificationDeleted` pauses without implicit resume.
- Android screen-off/hidden lifecycle handling leaves active speech running
  **only** when that same book has a live media handler. Otherwise the
  reader pauses; pending visual save timers are cancelled.
- The last opened book is tracked locally by SQLite v14, accessible with
  an explicit Continue reading tile. It never auto-plays, auto-requests
  cloud speech or promises process-death background reconstruction.
  See [Session Resume and Lifecycle](SESSION_RESUME_AND_LIFECYCLE.md).

## Settled native stop and focus ownership

- `ReaderPlayer.isSettledIdle` distinguishes a genuine Pause or completed
  book from an in-flight Seek/voice switch. The foreground media handler
  releases the audio-focus lease only once native stop is complete, while
  retaining focus for pending automatic continuation.
- Direct pauses originating inside the player (sleep-timer expiry, settings)
  now release focus without requiring a duplicate Android transport request.
- Concurrent remote Play calls cannot multiply focus grants or initiate
  duplicate speech runs; the active lease is reused and the latest Play
  intent prevails.
- The existing SQLite v16 recovery marker survives temporary navigation
  gaps. See [Audio Transition Safety](AUDIO_TRANSITION_SAFETY.md).

## Native Stop timeout

- An 8-second default bounded wait allows Android Pause/Seek commands to
  return an error if a provider does not acknowledge native Stop.
- The original Stop is still pending, and **no new Play/focus grant** is
  authorized until it confirms success. An outright Stop failure keeps
  that player locked against new speech.
- A hung engine is not killed or guaranteed silent by this timeout.
  A reader closed in this uncertain state preserves its crash-recovery
  checkpoint. See [Native Stop Timeout](NATIVE_STOP_TIMEOUT.md).

No native build or device run is claimed by this document.

## Share-sheet entrypoint (2026-10-28)

The tracked `tool/android/MainActivity.kt` now subclasses
`AudioServiceActivity` rather than naming the library activity directly in
the manifest. This retains the audio-service Flutter engine while enabling
native document shares. Bootstrap and manual verification workflows install
the matching Kotlin file and manifest. This is **not Android-compiled**;
notification, focus and background controls must be rechecked on a device
after the manifest merge. See [Android share import](ANDROID_SHARE_SHEET_IMPORT.md).
