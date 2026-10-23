# Interrupted narration: crash-only checkpoint and manual recovery

Implementation: 2026-10-23, `feature/m0-flutter-foundation`.
Status: **code authored, SDK/device validation pending**.

## What changed

SQLite schema **v16** adds a single private `speech_recovery_marker` table:
`slot = 1`, `book_id`, and UTC `started_at`. Only the book ID and a
local timestamp are stored there. It does not contain text, secrets, voice
metadata, player state, audio filenames, cloud credentials, consent, an API
request ID, or pending billing.

The reader's `NarrationRecoveryBinding` owns the checkpoint as part of
its `ReaderPlayer` lifecycle. Immediately before the first speech attempt
for each segment, it atomically:
1. Saves the segment's authoritative source anchor and legacy UTF-16 offset
   to `books`, and
2. Inserts/replaces the single active checkpoint for that book.

Both writes are one SQLite transaction (WAL and normal database error
handling still apply). On ordinary user pause, a headphone/system
interruption, a sleep-timer expiry, a completed book, a speech error,
replacement of the player or leaving the reader, the player notifies its
binding and clears the checkpoint. All relevant transport controls,
including lock-screen controls, share the same `ReaderPlayer`.

A failure after checkpointing but before native synthesis may still leave
a recovery notice. This is intentional and harmless: it never implies
audio was produced or billed.

## What happens after process death

At the **next** local library startup, `LibraryStore.initialize()`
consumes any marker once in a transaction. It keeps only the book ID in
memory for that new app session. If the managed book file is still
available, LibraryScreen displays a **Narration interrupted** card.

Tapping the card reopens the standard reader at the source anchor/UTF-16
position already stored for that book. It does **not** invoke Play or
initiate a cloud request. The existing provider settings, cost reservation,
explicit per-book consent and voice selection checks continue to apply
when the user *later* presses Play.

The notice can also be dismissed; this changes only an in-memory
indicator, not the saved reading position. An unavailable or deleted
private book never produces a broken recovery shortcut.

The initial startup **does not** reconstruct a Flutter TTS player, request
Android foreground-service privileges, resume any interrupted utterance,
or retry an in-flight OpenAI HTTP request. A killed/suspended process may
terminate mid-segment. The next manual Play may generate that segment
again and could incur new charges if its original response was not cached;
this is why auto-resume is explicitly disabled.

## Fail-closed and multibook behavior

- There is only one active checkpoint for the app, owned by one book.
- An obsolete reader can delete a checkpoint only if its book ID matches;
  its cleanup cannot erase a checkpoint for another book.
- Deleting the checkpoint book cascades its marker through SQLite FK.
- A process that starts with a stale marker consumes it exactly once;
  further restarts without another active speech attempt do not repeat it.
- Legacy v1–v15 SQLite/JSON books receive an empty recovery table during
  v16 migration; no old reading session is fabricated.
- Rendering text or merely opening books never creates a TTS checkpoint.
- PDF visual pages stay in `pdf_visual_page` (v15), independent from
  both spoken position and the new recovery table.
- If the engine is stopping due to Pause, Seek or voice changes, the crash
  marker stays in place until native stop completes. It is not cleared during
  a temporary `isPlaying=false` state if playback should resume. Errors in
  native stop settle the idle notification, but device validation remains
  required. See [Audio Transition Safety](AUDIO_TRANSITION_SAFETY.md).

## Unexecuted regression tests

- `test/data/narration_crash_recovery_test.dart`: 10 cases for simulated
  abrupt termination, single-use notice, manual reopening/dismissal,
  clean stop, different books, missing/deleted files, atomic rejection,
  v15→v16 migration, and checkpoint privacy.
- `test/audio/narration_recovery_binding_test.dart`: 7 tests using an
  injectable fake `SpeechEngine` with a real `ReaderPlayer`, covering
  pause/completion/failure cleanup, process-loss recovery, and checkpoint
  retention during delayed Seek, Pause, and narrator voice changes.
- The preexisting SQLite v13→latest and PDF v13→latest migration tests have
  been updated to expect v16.

Neither the tests nor Flutter analyzer or Android/Windows builds have
been run in the current development environment, as agreed.

## Real-device acceptance still needed

Run the complete Flutter/SQLite tests and Android/Windows builds; then
kill Android during both system and consented cloud speech, reopen EReader,
confirm the interruption card and source position, and ensure absolutely
**no** synthesis occurs until an explicit Play. Repeat after pause, sleep
timer expiry, task swipe, notification dismissal, network interruption,
a completed book, removal/reimport and consent revocation. Verify no
unexpected second API charge from automatic recovery (there must be no
automatic recovery API call).

See also [Session Resume and Lifecycle](SESSION_RESUME_AND_LIFECYCLE.md)
and [Android Background Media](ANDROID_BACKGROUND_MEDIA.md).
