# M2 — Android interruptions and completion-aware source checkpoints

_Date: 2026-10-26. Implemented in the feature branch; Flutter/native tests not run._

## Goal

Keep the reader's source position honest when an OS audio-focus interruption
or headset removal occurs, including rare transitions **between** two TTS
clips. Prevent repeated Android interruption events from causing unnecessary
native Stop requests or unintentional cloud narration when focus returns.

## Android AudioSession and MediaSession

`ReaderMediaHandler.pauseForSystemInterruption()` now shares a single
in-flight pause Future for repeated noisy/interruption callbacks from the
same attached book. Duplicate callbacks still invalidate any new pending
Play command that was initiated after the first interruption. Attaching a
different book resets this coalescing scope.

The normal interruption event handler consumes asynchronous failures safely;
native Stop errors remain reported by `ReaderPlayer` and do not authorize
automatic playback. A native focus gain never triggers an automatic Play.

`ReaderMediaHandler.pause()` skips SpeechEngine.stop when
`ReaderPlayer.isSettledIdle` is already true, avoiding unnecessary native
operations when a focus grant is still being awaited or a book is already
quiet. It **still cancels outstanding Play commands** and queues the focus
release. An in-flight Seek, voice switch, or unconfirmed Stop is NOT
`isSettledIdle` and therefore still requires the normal stop barrier.

## Source-exact reading progress

`ReaderPlayer.onSegmentCompleted` is an optional callback, triggered only
after the entire awaited speech-engine utterance completes in the current
live session. It is NEVER called for an interrupted or cancelled utterance.

`NarrationRecoveryBinding` now persists the next **audible** segment's
source offset and anchor after the preceding clip finished. A source-verified
EPUB note skipped by the user's explicit session setting is bypassed when
selecting that next anchor. A final successfully narrated segment persists
its source end offset before clearing the active crash-recovery marker.

The existing pre-synthesis `onSegmentStarted` checkpoint is retained. Thus:

| Situation | Persisted source position | Recovery marker |
| --- | --- | --- |
| Current segment begins synthesis | Current segment START | Active |
| Interrupted midway through speech | Same current START | Cleared ONLY after native Stop confirmation |
| Segment ends successfully | Next audible segment START, or final END | Active until confirmed settled idle |
| OS audio-focus lost before a pending Seek completes | Original segment START (unless it finished) | Active while Stop is outstanding |
| Normal confirmed Pause | Last committed source position | Cleared |
| Unconfirmed/failed native Stop | Do not infer silence | Marker remains conservatively active |

These are source UTF-16 offsets, not invented word timings, audio seconds,
CFIs or sentence duration guesses. The narration progress callback is
synchronous up to its SQLite transaction and does not transmit book content.

## Regression cases added (NOT executed)

- `test/audio/reader_media_handler_test.dart`: idle focus grant cancelled
  without a gratuitous Stop; repeated interruption events share one
  in-flight Stop; a second interruption revokes an intervening Play request.
- `test/audio/narration_recovery_binding_test.dart`: successful segment
  completion advances the persisted bookmark; mid-utterance pause retains
  its start; skipped note advances to the next spoken segment; normal
  full-book completion records end offset; Android MediaHandler + SQLite
  marker stays active until delayed native Stop completes.
- Existing `native_stop_timeout_test.dart`, `rapid_playback_navigation_test.dart`,
  `reader_player_test.dart` and `reader_lifecycle_policy_test.dart` must
  remain green when manually executed.

## Manual on-device acceptance

1. Locally execute `tool/run-all-tests.ps1`; retain its structured results
   and check the two changed suites plus native Stop-timeout cases.
2. On Android, start narration in the middle of an EPUB chapter. Trigger
   incoming call, notification/navigation audio interruption, loss of focus
   and headphone unplug. Verify speech pauses, never auto-resumes on focus
   gain, and restarts the interrupted sentence after explicit Play.
3. Interrupt after a sentence **fully completed** but before the next
   audible chunk. Reopen the app and confirm the saved source position is
   the next actually spoken chunk (not a verified skipped footnote).
4. Repeat rapid Pause/Play and Seek during slow native Stop; ensure there
   is no overlap, unexpected new HTTP prefetch, duplicate Stop storm or
   abandoned private temporary MP3.
5. Validate the Android lock-screen notification and task removal, speech
   checkpoint restoration after force-stop, and the final completed-book
   position in an EPUB, TXT and PDF.
6. Compare desktop Windows behavior; AudioSession focus policy is Android
   specific and desktop is not changed by the media handler.

**Status:** committed source/tests/docs, no Dart formatter/analyzer, no
Flutter test run, no native Windows/Android builds and no measured audio
performance in this environment. M2 estimated 70% and overall ~55%
until native release gates are verified.
