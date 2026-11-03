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

## 2026-11-03 — task-removal cleanup is scoped to its media binding

A pending Android task-removal event can await a slow native Stop. In
that interval a later reader may attach a different book to the same
`ReaderMediaHandler`. Previously the old `onTaskRemoved` continuation
unconditionally called `detach()`, removing the **new** MediaSession,
notification metadata and remote controls after the new book had opened.

`onTaskRemoved` now captures the handler's monotonic binding epoch
before pausing. Its `finally` block detaches and awaits the associated
focus cleanup only if that epoch is still active. This also handles
failure of the old native Stop and reattaching the same player under a
new binding. A task removal that still owns its original session
continues to stop, detach, and release focus exactly as before.

Three self-contained regressions in
`test/audio/reader_media_handler_test.dart` simulate delayed native
Stop success, delayed Stop failure, and same-player rebinding while
the old task-removal Future is outstanding. The new book must keep its
media metadata and transport capability; no playback starts without
an explicit subsequent Play. These tests have been authored but not
run, consistent with the postponed Flutter/device test phase.

## 2026-11-03 — suppress superseded asynchronous consent failures

The Android MediaSession waits on a per-book speech-consent check
before requesting audio focus or issuing Play. An old request could
return `false` (or throw) after the reader had attached a different
book, another Play was accepted, or an intervening Pause invalidated
the request. Previously the old denial was reported *before* the
binding/command freshness check, producing an unrelated consent error
over the current session.

`ReaderMediaHandler.play` now snapshots the consent callback and
checks the original binding epoch, player identity, command epoch and
closed state **before propagating a denial or callback exception**.
Only a still-current Play may report cloud consent denial. An
obsolete request performs no focus acquisition or speech dispatch
and cannot alter the newer book's controls. Existing denials for
the active book remain enforced.

Four deterministic tests cover delayed denial after book replacement,
an earlier denial following a newer successful Play, a late consent
exception after Pause, and preservation of the current consent
exception. Tests and documentation have been authored; Flutter tests,
native builds, and GitHub Actions have not been run.

## 2026-11-03 — active ownership of Android focus and remote Seek errors

Two more asynchronous errors can outlive their original media command.
Android audio focus may reject with a platform exception **after**
a newer Pause/Play or a different book's attachment. Previously the
focus-acquisition Future was awaited without a stale-command catch,
so the old error could be delivered to Android despite losing ownership.
`ReaderMediaHandler.play` now checks the original player, binding
epoch and command epoch before propagating a focus exception. Denials
and thrown failures of the **current** focus request remain visible.

Likewise a remote Next/Previous Seek may fail only when its delayed
native Stop settles. `_skipRemote` now checks its original binding,
player, remote command and pending skip revision before reporting such
a failure. A superseded remote seek must not report an obsolete failure
after a new book or newer media command, but the current seek still
propagates a real Stop failure. The existing `finally` continues to
clear only the matching skip accumulator.

Five deterministic tests in `test/audio/reader_media_handler_test.dart`
exercise stale focus exception after book handoff, stale focus exception
after Pause, live focus exception, obsolete remote Seek failure after
book replacement, and live remote Seek failure. No audio/test/build
commands or GitHub Actions were executed.

## 2026-11-03 — handler-owned native Stop barrier across media bindings

Android focus release/acquisition is serialized, but that is distinct
from the native TTS engine's own Stop acknowledgement. A removed book's
`onTaskRemoved` Pause or a lock-screen Next/Previous Seek can remain
unsettled after another book has attached. Previously the new
`ReaderMediaHandler.play` could claim focus and synthesize a new book
while the previous native Stop was still pending.

The handler now observes each **handler-originated Pause and remote
Seek** as it is issued and accumulates a cross-binding Stop barrier.
A new Play awaits this barrier **before requesting Android audio
focus or dispatching speech**. Old requests are still invalidated by
binding/command epochs while waiting. If any tracked native
Stop/Seek fails, the barrier stays failed and the handler refuses
another Play; it does not infer that a timed-out/failed native engine
has stopped. This conservative policy requires recreation of the
media session after a stop failure. Existing explicit Play, voice
consent and pause semantics remain unchanged.

Three test cases in `test/audio/reader_media_handler_test.dart`
cover delayed successful task-removal Stop, failed old Stop,
and a pending remote Seek across book replacement. They verify
that new audio/focus cannot start before confirmed settlement and
that a failed old Stop cannot erase new media metadata. This gate
covers operations issued through `ReaderMediaHandler`; direct
`ReaderPlayer` shutdown outside the handler retains its own
native Stop lifecycle. Flutter/device tests and GitHub Actions
were not run.

## 2026-11-03 — direct ReaderPlayer Stop and Seek at book handoff

The existing cross-binding handler barrier only observed Pause and
Next/Previous issued through Android MediaSession. A direct reader UI
`ReaderPlayer.pause()` or `seekTo()` can initiate native Stop without
passing through that transport. If a different book was attached while
the old Stop was pending, its Play could start another speech engine.
A pending direct Seek could also silently auto-resume the **old** book
after the handler removed its media controls.

`ReaderPlayer.waitForNativeStopConfirmation()` exposes a read-only,
failure-consuming snapshot of its latest native Stop operation. A
handler detachment now observes this fence and, unless the outgoing
player is already settled idle, issues a final Pause to supersede any
latent Seek auto-resume. The existing cross-book Stop barrier must
settle before the replacement Play obtains focus or synthesizes audio.
A failed native Stop leaves the handler fail-closed and a fresh
handler instance is required. `ReaderMediaHandler.close()` now
waits for detached native Stop settlement as well. Stale binding
callbacks still cannot overwrite the new book's media metadata.

Four new deterministic media-handler tests cover direct Pause with
slow Stop, failed direct Pause, immediate book replacement during
live narration, and replacement during a direct Seek's pending
auto-resume. The earlier obsolete remote Seek-failure regression
was aligned with the safety invariant: a new book must not Play
after a failed old native Stop. No Flutter tests, analyzer, builds
or GitHub Actions were run.

## 2026-11-03 — bound detached native Stop confirmation

The cross-book handoff fence added in the previous step observed the
original native `SpeechEngine.stop()` Future. While `ReaderPlayer.pause`
already has a finite `nativeStopTimeout`, the new
`waitForNativeStopConfirmation()` accessor could wait forever if a
native plugin never completed its Stop Future. That inadvertently
prevented `ReaderMediaHandler.close()` from finishing and left a
replacement book's Play indefinitely pending instead of returning a
clear, safe failure.

The read-only confirmation accessor now uses the same finite
`nativeStopTimeout` as Pause. An elapsed deadline returns **false**,
not success: the media-handler barrier remains fail-closed for its
lifetime and another book cannot obtain Android focus or start audio
from it. The original Stop Future is still observed by the player's
existing late-completion handler, so no platform error is unhandled.
The change does not claim that the native engine became silent after
timeout or reset the safety lock on a late acknowledgment.

Three tests in `test/audio/native_stop_timeout_test.dart` cover
finite confirmation snapshot time, handler close after a stuck direct
Stop, and prompt denial of replacement Play without new speech or
focus. All tests are authored only; Flutter/native execution,
analyzer, builds and GitHub Actions were not run.

## 2026-11-03 — concurrent close joins native Stop and focus release

A first `ReaderMediaHandler.close()` call previously detached the
current book, marked `_closed = true`, and then awaited stream
cancellation, Android focus release and the native Stop handoff
barrier. A second caller arriving during those awaits returned
immediately because `_closed` was already true. Its completed Future
could falsely indicate safe shutdown while a native engine remained
active or a focus release was still pending.

`close()` now returns a single cached shutdown Future. Only
`_closeOnce()` performs detachment and native cleanup, while every
concurrent or later caller waits for the **same** completion (or
failure). Pending cloud consent is still invalidated by the binding
epoch at detach; it cannot dispatch speech after close. No duplicate
native Stops or duplicate focus releases are issued merely because
two callers close the handler.

Three deterministic regressions in
`test/audio/reader_media_handler_test.dart` cover concurrent close
while Stop and focus release are separately held, close during an
in-flight consent check, and an Android focus-release exception.
The pre-existing stuck native Stop test in
`test/audio/native_stop_timeout_test.dart` now asserts both callers
join the bounded shutdown. Code/tests/docs authored only: no Dart
analyzer, Flutter/native tests, builds or GitHub Actions executed.

## 2026-11-03 — surface permanent native Stop lock in Android controls

The cross-book native Stop barrier already prevented a replacement
book from synthesizing after an old engine's failed or timed-out Stop.
However, the newly attached book's `ReaderPlayer.lastError` was
empty. Its MediaSession consequently advertised `ready` playback,
including Play and Next/Previous buttons that could not succeed. This
misrepresented an unsafe shared audio service as ready to play.

`ReaderMediaHandler` now latches `requiresFreshAudioSession` if
any observed Stop confirmation is false, publishes an Android
`AudioProcessingState.error`, and suppresses compact transport
buttons while unsafe. The prior book's media metadata can still be
replaced safely; it is the **audio transport** that stays locked.
A late confirmation of a previously failed handler operation does
not automatically rearm it. Only a fresh, separately initialized
audio service can recover, after ensuring the earlier native engine
is actually stopped. The current player's own
`nativeStopUnconfirmed` also disables transport while unsafe.

One new deterministic media-handler test covers the failure-to-
replacement-book state. Earlier delayed Stop-failure and
Stop-timeout tests now verify the lock-screen error state and
absence of misleading Play controls. Test code was authored and
source patches checked, but Flutter tests, analyzer, native builds
and GitHub Actions were not executed.

## 2026-11-03 — explicit recovery after a late confirmed native Stop

A native Stop timeout is a bounded wait, **not** proof of silence.
Previously the handler latched every expired cross-book Stop barrier
permanently, so a platform that finally acknowledged its old Stop
could not resume audio in a new book without recreating the Android
audio service. That was unnecessarily restrictive for a **late,
successful** Stop, while genuine errors still require fail-closed
handling.

The handler now retains the precise `ReaderPlayer` instances whose
Stop/Seek/transport operation could not be confirmed. On a **new
explicit Play request**, `tryRecoverAfterConfirmedNativeStops()`
rechecks each affected player's actual native Stop Future through its
bounded confirmation accessor. Recovery is allowed only when every
recorded engine is no longer playing, has no pending/unconfirmed
Stop, and no new media Stop or book attachment has invalidated the
inspection. The handler then rearms its cross-book barrier, republishes
the media controls and proceeds with the user's Play. A genuine
native Stop failure never passes the confirmation check. Neither a
focus-gain event nor a late native callback automatically starts TTS.

The unsafe-player set retains only sessions that failed their
original Stop barrier, avoiding retention of every successfully
closed book. The previous `requiresFreshAudioSession` flag still
means the current handler is unsafe *until an explicit successful
recovery*; if recovery fails, the lock-screen error state and disabled
controls are preserved.

Two tests in `test/audio/native_stop_timeout_test.dart` simulate
a timeout followed by a late positive acknowledgment and an
irreversible native Stop exception. They verify there is no automatic
speech or audio-focus acquisition, that an explicit retry can safely
resume the new book, and that native errors cannot bypass the lock.
Source patches verified; Dart/Flutter test suites, analyzer,
Android/Windows builds and GitHub Actions not run.
