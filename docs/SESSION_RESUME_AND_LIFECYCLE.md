# Android lifecycle and local Continue reading

Increment: 2026-10-23, branch `feature/m0-flutter-foundation`.
**Source only.** Flutter/Dart analyzer, unit tests and Android/Windows
compilation deliberately deferred until final integration.

## Recovering the last opened book safely

- Database migration **v13 → v14** adds nullable `books.last_opened_at`
  in its own transaction. Fresh installations migrate to the same v14 schema.
  Previously imported books get no synthetic opening date.
- The LibraryScreen updates the timestamp **only** on explicit navigation
  into that reader, then shows a `Continue reading` tile upon subsequent
  launches. A book without its existing private source file cannot appear.
- Tapping the tile goes through the original `ReaderScreen` load path.
  That path already resolves `progress_anchor` against the decoded EPUB/TXT
  text or PDF text mode, falling back to `progress_offset` if necessary.
  It never treats last-opened time as a segment index.
- The shortcut stores only a local timestamp. It does not persist playback
  state, pending HTTP operations, consent, login, keys, downloaded MP3,
  ephemeral prefetch state, or a service-restoration request.
- Reopening never automatically speaks or makes billable cloud requests.
  A new Play must pass the existing consent and quota checks.
- Removing a book deletes its last-opened marker with the book row.
  If the latest file is missing, the shortcut falls back to the most recent
  older book whose private file is still available. The missing source
  remains in the library for a potential reimport/repair.

## Android lifecycle transitions

- The reader subscribes to Flutter's application lifecycle. During
  `hidden` / `paused` it cancels pending delayed viewport writes to avoid
  overwriting the audio cursor saved by the next segment.
- **Media handler attached to this exact player:** an Android background
  transition does not stop audio. Only the Android audio service is permitted
  to keep its currently bound book speaking with the screen off.
- **No media handler, or it belongs to a different player:** Android pauses
  narration. This fails closed when foreground-service setup is unavailable.
- On `resumed`, `inactive`, or `detached` events, this policy never
  automatically calls `play()`. OS interruption handling remains the source
  of stop events for an active media session.
- Non-Android platforms preserve existing minimization rules.

## Media service exit and asynchronous focus

- Focus **acquisition and release** are queued on a single serial future
  chain. A focus grant still in flight cannot become the last native operation
  after a more recent Pause or a book switch.
- A task swipe calls `onTaskRemoved`: pause, detach and clear media
  metadata/controls, even if the native stop throws. No invisible book can
  continue to receive new service-originated transport events.
- A deleted notification calls `onNotificationDeleted`: pause without
  automatically playing again. The reader remains attached if its UI is open.
- App-level buttons verify that the current reader owns the MediaSession
  before routing Play to it; an old screen cannot accidentally start another
  book's narration. Remote Play continues to enforce per-book OpenAI consent.
- Existing speaker selection, voice-casting hashes and source ranges are
  preserved. The native system TTS engine may restart the active *segment*
  after manual resume and the cloud engine has its original prefetch/cost rules.

## Regression evidence required later

Authored tests, **not run**:

- `test/data/recent_book_resume_test.dart`: four tests for last opened,
  anchored progress persistence, missing/deleted file and v13 → v14 migration.
- `test/audio/reader_lifecycle_policy_test.dart`: three tests for screen-off
  media ownership, fail-closed Android background and no automatic foreground
  resume.
- `test/audio/reader_media_handler_test.dart`: 12 tests total for metadata,
  consent, transport, focus/seek races, interruption, task-swipe stop (including
  native stop failure), notification dismissal and stale book bindings.

At integration time: run the Flutter analyzer and all tests, launch Android,
read for a long period screen-off, interrupt using phone/music, restart
the app and check Continue reading, remove the task from recents, dismiss
the notification, revoke consent while paused, and verify source anchors
and cost counters. Check Windows and Android migrations under SQLite WAL.

## Deliberately not claimed

The app is **not** guaranteed to outlive Android process termination.
It does not automatically reconstruct an engine after process death, recover
unfinished cloud requests, persist the timer deadline, or restart narration.
PDF rendered-page restoration is now implemented as source via separate SQLite v15 `pdf_visual_page` and `pdfrx` callbacks; **device behavior remains unverified** (see [PDF Visual Resume](PDF_VISUAL_RESUME.md)). Android
13+ notification behavior, vendor battery policies, media service shutdown,
Bluetooth controls and real audio focus timing require physical device tests.

See also [Android Background Media](ANDROID_BACKGROUND_MEDIA.md) and the
[Implementation Status](IMPLEMENTATION_STATUS.md).
