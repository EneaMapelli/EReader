# Playback session safety: rapid seek, pause, voice and rate changes

Source increment: 2026-10-23 on branch `feature/m0-flutter-foundation`. **No Flutter or Dart tests, native Windows/Android builds or audio timing measurements have been run**; the owner requested compilation only at final integration.

## Motivation

The optional cloud one-chunk synthesis prebuffer and second native MP3 decoder improve readiness but make asynchronous session transitions more sensitive. A queued native Stop, audio decoder file load or platform voice change may complete after a newer request. EReader must never let that completion move the reader back to an obsolete segment, adopt an out-of-date voice or interrupt an already restarted clip.

## ReaderPlayer navigation ordering

- `pause()` supersedes pending auto-resuming navigation, invalidates the active speaking session and serializes `SpeechEngine.stop` calls.
- `seekTo()` uses a monotonic navigation epoch. If two seeks overlap while Stop is slow, **only the most recent seek** can set the position and optionally restart playback. The second seek inherits the original desire to continue playing. Earlier completions are ignored.
- An explicit Play after a pending seek supersedes that seek. Play still waits until the prior native stop has completed before speaking, preventing overlapping voices.
- `dispose()` invalidates both session and navigation generations and is idempotent. A disposed ReaderPlayer cannot start new speech.
- Errors from abandoned sessions do not overwrite the current session's error state.

## Voice and playback-settings ordering

- `selectVoice()` serializes in-flight native voice changes. A later choice replaces an earlier one; a canceled older native completion forces subsequent playback to reassert the intended narrator or cast voice.
- A reader who changes voice during narration resumes the current segment only after the winner has been applied. Selecting a voice while paused does not start playing automatically.
- A failed current voice change clears its pending-resume request and reports an error instead of unexpectedly restarting narration later.
- Rate and pitch sliders continue to update their displayed value while dragging. When the user releases the slider (`onChangeEnd`), ReaderScreen restarts the current source-aligned segment using the committed settings, invalidating old cloud/native prebuffer generations. Language selection similarly commits a restart; changes made while paused stay paused.
- Neither voice changes nor restarts rewrite the underlying book, source offsets, manual speaker assignments or cached text-to-speech model data.

## Native MP3 decoder isolation

- Each of the two reusable decoder slots serializes its native `setFilePath` and finishing Stop operations. A new generation must not begin a load against an old load still in progress on the same decoder.
- Old-session playback completion checks its generation again before stopping a decoder or removing temporary files. The same applies after an awaited native stop, which might overlap a newer request.
- When an older load finally returns, it may clean up **only its own** private temporary MP3, not a file belonging to a newer generation. Speed- or source-mismatched prepared audio is discarded before a cold load.
- Stop invalidates all pending work and stops both players. An in-progress load that eventually completes remains unable to start its old clip. Dispose releases both native decoders. Deletion retries after Windows file locks remain best-effort.

## Cloud privacy and quota

This increment does not initiate any additional TTS HTTP calls or background synthesis. The pre-existing opt-in one-ahead cloud audio feature remains **OFF by default**, and the per-book consent, character budget, separate key and response cache remain unchanged. Requests already transmitted before pause, seek or revocation may still be billed. Once an old request is canceled, a later explicit playback may need a new request if the original audio was never successfully cached; no guarantee of zero duplicate provider billing is made for in-flight cancellation.

## Authored, unexecuted regression tests

- `test/audio/rapid_playback_navigation_test.dart`: **9 tests** for rapid two-seek last-wins behavior, user Pause overtaking a delayed seek, overlapping native voice choices, committed speed restart at the same segment, paused settings, disposal during a delayed voice switch, direct Play overriding pending navigation, paused voice selection and no playback after disposal.
- `test/audio/mp3_preload_test.dart`: extended to **10 tests** including a delayed previous `play()` completion that must not stop new audio, and an old pending native load that must not delete a newer warmed MP3.
- Existing `test/audio/cloud_prefetch_test.dart` covers default opt-in, bounded lookahead, cloud consent, HTTP failures, pause/seek and current/next voice pairing, but remains unexecuted.

## Integration still required

`dart format`, `flutter analyze`, `flutter test`, native Windows/Android builds and end-to-end timing tests should cover repeated rapid chapter seeking, slider interactions, asynchronous failed voice selection, Android lifecycle/backgrounding, Windows decoder file handles, cloud input quota accounting and native voice restoration. These tests must run during the owner's final build phase before PR #1 can leave draft status.
## 2026-10-26 — audio focus interruptions and accurate clip checkpoints

Android AudioSession noisy/interruption events share one in-flight native
Stop per attached reader, including notification of newer Play invalidation.
A settled idle player releases focus without an unnecessary TTS Stop, while
a pending Seek or unconfirmed native Stop still requires a real stop barrier.
ReaderPlayer now offers an optional completed-utterance hook; the actual
reader persists the next audible source position only after a finished
clip, never after cancelling it. EPUB note skip ranges are respected.
Authored but **not executed** tests for interruption floods and persistent
SQLite checkpoints. See
[AUDIO_INTERRUPTION_CHECKPOINTS.md](AUDIO_INTERRUPTION_CHECKPOINTS.md).
