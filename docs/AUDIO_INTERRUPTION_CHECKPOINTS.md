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

## 2026-11-03 — cancel superseded recovery probes and avoid double timeouts

A recovery probe can begin while the cross-book native Stop barrier
has not settled. Even if that Stop ultimately succeeds, another book
may be attached or the Android media service closed during the await.
Previously the fast success branch returned `true` before checking
the binding/barrier revision and close state. The probe could report
an obsolete session as recovered (the Play path still checked command
epochs before dispatching speech). Now **both** successful and failed
probe outcomes validate that the original barrier is unchanged and
the service remains open.

A second issue affected retries after a Stop timeout: the handler
could re-await the already unconfirmed native Future for another full
`nativeStopTimeout`. Recovery now immediately rejects an affected
player whose native Stop is still marked unconfirmed. A later,
genuinely successful callback clears that flag and an explicit Play
may recheck the original engine; a real native exception remains
fail-closed. No recovery path performs an unsolicited Play.

Three targeted tests cover close during pending successful recovery,
book replacement during the same await, and prompt refusal of a
second wait after a known timeout. Source/test/docs are committed
without running Flutter, Dart analyzer, native builds or GitHub
Actions; Android behavior still requires device validation.

## 2026-11-03 — coalesce concurrent TTS recovery and re-lock on later failure

Two near-simultaneous requests for recovery after a late, successful
native Stop previously inspected the same failed barrier independently.
The first request could verify all old engines and replace the barrier
with a ready Future. The second would then treat the changed Future as
a superseding operation and return false, even though that change was
the *successful recovery it was waiting for*. A newer Play could
therefore fail spuriously instead of starting the new book.

`ReaderMediaHandler.tryRecoverAfterConfirmedNativeStops()` now shares
one in-flight recovery Future between callers. An old, invalidated
book/close still makes the shared verification return false, and a
future explicit Play can initiate another fresh verification after
the current one completes. Recovery continues to require actual
positive native Stop acknowledgments, and never starts TTS itself.

Two regressions in `test/audio/native_stop_timeout_test.dart`
cover simultaneous recovery calls sharing the positive result without
automatic narration, and a *second*, genuinely failed native Stop
after an earlier timeout had been successfully recovered. The later
failure must re-lock controls, suppress new focus, and preserve the
current book's metadata. The test code is authored but not executed;
Dart analyzer, Flutter/native tests, builds and GitHub Actions
remain deferred.

## 2026-11-03 — direct reader actions invalidate pending MediaSession Play/recovery

The Android handler tracks its own command/binding revisions, but a
ReaderScreen may also issue `ReaderPlayer.seekTo()`, `pause()`, or
another playback operation directly. Such an action changes the
player's independent `narrationControlRevision` without incrementing
the handler's command epoch. An earlier lock-screen Play waiting on
consent or Android focus could therefore start speech *after* an
explicit direct Pause/Seek.

`ReaderMediaHandler.play()` now snapshots this additional player
revision and rechecks it after all asynchronous consent, Stop-barrier,
recovery and focus waits. When an intervening direct reader command
wins, the earlier Play quietly exits rather than starting stale
narration. Existing focus release remains serialized by the player
state listener.

Recovery probes now capture the bound player's identity and direct
control revision, too. A direct Seek during an older Stop
acknowledgment invalidates the obsolete recovery result. Before
rearming a failed cross-book barrier, recovery additionally requires
the *current* player to be settled idle; an in-flight direct native
Stop must not be ignored merely because it never passed through
the Android transport.

Four new regression tests in
`test/audio/reader_media_handler_test.dart` and
`test/audio/native_stop_timeout_test.dart` cover direct Seek during
cloud consent, direct Pause during Android focus acquisition, direct
navigation during older recovery, and a direct native Stop while
recovery is eligible. The code and tests are committed but have not
been executed; Flutter/analyzer, device builds and GitHub Actions
remain deferred until stabilization.

## 2026-11-03 — release unsafe native Stop recovery sources on shutdown

The Android media handler intentionally keeps references to older
`ReaderPlayer` instances after an unconfirmed Stop. This is needed
to inspect the **actual native engine acknowledgment** on a later,
explicit Play. Once `ReaderMediaHandler.close()` completes, however,
that handler is permanently closed and no recovery can happen.
Previously its `_unsafeStopPlayers` set could continue retaining
players, associated speech engines and their book/session resources.

Native Stop confirmation callbacks now refrain from adding players
to the unsafe recovery set once the handler is closed. The terminal
close path drains its tracked Stop barrier, then clears all retained
recovery sources and its completed/pending recovery reference.
The closed handler **does not reset** the unsafe Stop latch or
authorize any playback, and `close()` remains shared across callers.

Two deterministic tests exercise a genuine Stop failure followed by
close, and a timeout followed by a native confirmation that arrives
after close. A pre-existing positive recovery test also asserts that
the recovery set is emptied after successful re-arming. A read-only,
`@visibleForTesting` count measures retained recovery sources
without exposing any IDs, text or speech data.

Test code was authored and source patches checked, but Dart/Flutter
test execution, analyzer, native builds and GitHub Actions were not run.

## 2026-11-03 — serialize speech engine disposal after native Stop

`ReaderScreen.dispose()` calls `ReaderMediaHandler.detach(player)`
and then `ReaderPlayer.dispose()` synchronously. The handler's detach
may already have started `ReaderPlayer.pause()` with a pending native
`SpeechEngine.stop()`. Previously `ReaderPlayer.dispose()` immediately
dispatched `SpeechEngine.dispose()`, often another platform Stop,
while that older native call was in flight. Those independent native
operations could race (and a delayed disposal Stop could interfere
with a new book).

`ReaderPlayer.dispose()` still cancels the player session, timers,
and notifier immediately, so widget teardown remains synchronous.
It now captures the pending native Stop and voice-change chains and
schedules best-effort engine disposal **only after those operations
settle**. A completed native Stop exception does not prevent terminal
cleanup. A native Stop timeout is explicitly **not** treated as an
acknowledgment: if the old platform Future hangs forever, its engine
remains quarantined instead of racing a second native dispose. If
the late callback finally settles, engine disposal proceeds exactly
once. This is a deliberate safety tradeoff; a permanently hung native
plugin still requires platform/process-level recovery.

Four regressions in `test/audio/native_stop_timeout_test.dart`
check disposal order with an in-flight native Stop, late success
following a Stop timeout, a completed native Stop error, and repeated
idle disposal. Test code and source patches are committed but were
not executed; Dart analyzer, Flutter tests, device builds and GitHub
Actions remain deferred. Cross-engine native plugin ordering on
Android still requires device validation before merging.

## 2026-11-03 — fence outgoing native engine retirement before a new Android Play

The earlier disposal fix serialized `ReaderPlayer.dispose()` **after**
its own native Stop/voice-change operations, but the Android
`ReaderMediaHandler` cross-book barrier only awaited `stop()`.
On Android, `SystemSpeechEngine.dispose()` itself calls
`FlutterTts.stop()`. If the new book claimed focus and synthesized
as soon as the old Stop completed, the old engine's delayed Dispose
could interrupt the new book's already-started native speech.

A disposed `ReaderPlayer` now exposes a bounded, failure-consuming
`waitForEngineRetirementConfirmation()` and a read-only confirmed
retirement flag. Real completion of `SpeechEngine.dispose()` sets
the flag; timeout or disposal failure does **not** claim native
silence. `ReaderMediaHandler.retireDetachedPlayer(player)` starts
ordinary synchronous player disposal and tracks its entire native
retirement behind the existing cross-book transport barrier.
`ReaderScreen` uses this path after unbinding/removing the old
reader, both on reload and on page teardown. No UI await or
automatic audio restart is introduced.

The replacement book may start only after the retired engine
finishes. If native Dispose hangs, Play fails closed after the
bounded deadline; a later genuinely successful disposal allows
a fresh explicit Play to verify and recover the handler. Recovery
also checks the disposed old player's retirement confirmation in
addition to its native Stop confirmation. A rejected engine
dispose can never rearm the same audio handler.

Three new deterministic regressions in
`test/audio/native_stop_timeout_test.dart` cover successful
outgoing engine retirement delaying a new book, timeout followed
by late disposal confirmation and explicit recovery, and
permanently failed Dispose. The tests and source changes have
been committed but not executed; Flutter tests, Dart analyzer,
Android builds and GitHub Actions remain deferred. Native
cross-instance TTS behavior still requires device validation.

## 2026-11-04 — guard native disposal from an obsolete reader screen

An Android `ReaderScreen` may remain mounted even after a different
book has attached to the shared `ReaderMediaHandler`. If that
obsolete screen finally disposes **after** the new book starts
speaking, its old `SystemSpeechEngine.dispose()` may call a
platform-wide `FlutterTts.stop()` and interrupt the active book.
The earlier retirement barrier only tracked this Stop **after
scheduling it**, which is too late to protect already-audible speech.

The handler now tracks deferred native retirements before allowing
future Play commands. `ReaderPlayer.retireWhenMediaQuiet()` cancels
the obsolete player's session and notifier immediately but holds its
final native `dispose()` until the bound current reader is truly
settled idle. The handler wakes these waiters on confirmed native
silence, including a book detach with a pending native Stop; a
failed or timed-out Stop resolves the waiters **unsafe**, never
dispatching the stale engine's global Stop. A long ongoing book does
not acquire an arbitrary retirement deadline: the native engine
retirement timeout starts only **after** the quiet gate opens.
Android Play also rechecks the latest Stop/retirement barrier
*after* focus acquisition so a late retirement registered during
focus cannot be bypassed.

Four deterministic regressions exercise an obsolete screen disposing
while the new book is speaking, disposal appearing while Play waits
for Android focus, another book replacement with a delayed Stop,
and a failed outgoing Stop that must quarantine stale disposal.
The code and tests are authored but have **not** been executed
with Flutter/Dart/Android or GitHub Actions. Native cross-engine
safety still needs physical Android device validation.

## 2026-11-04 — release late Android focus when retirement is unsafe

The fresh post-focus native-retirement check introduced for an
obsolete screen may discover a failed `SpeechEngine.dispose()`
*after* Android has already granted the new Play's focus lease.
Rejecting playback without giving back that lease would hold focus
despite there being no permitted speech. The handler now queues a
serialized focus release when this final Stop/retirement gate fails.
It rechecks the player/binding/command revision afterwards, so an
obsolete failure cannot be surfaced as an error for a newer Play.
No cloud synthesis or playback is started on failure.

One additional regression verifies failed old-engine disposal during
delayed focus acquisition suppresses new speech, surfaces the safety
error, and releases focus exactly once. As with all stabilization
changes, this test was authored but not run; Flutter/analyzer,
Android device builds and GitHub Actions remain deferred.

## 2026-11-04 — serialize multiple obsolete native engine disposals

The quiet-retirement mechanism protected the currently speaking book
but completed all waiting old-reader gates together. If two obsolete
screens were disposed while a new book was speaking, both older
`SpeechEngine.dispose()` calls could start simultaneously on the
shared Android TTS subsystem as soon as the new book paused. Some
adapters implement dispose by invoking a global native Stop, so
concurrent old-engine cleanup is not a safe substitute for confirmed
serial retirement.

`ReaderMediaHandler.retireDetachedPlayer()` now snapshots the
previous **actual** native retirement outcome before scheduling the
next old-engine disposal. The old `ReaderPlayer` UI/notifier is
invalidated immediately, but each physical engine retirement starts
only after its predecessor reports successful native completion and
the current reader is settled silent. A preceding native disposal
exception fails the later gate closed, without issuing another
potentially global Stop.

The handler keeps finite deadlines independent from this physical
queue. It times out a pending predecessor before reporting safe
handoff, without assuming the native call finished; if the
predecessor later **really** acknowledges disposal, the next engine
may retire in order, and a new user Play can explicitly revalidate
the failed transport fence. The quiet wait itself has no arbitrary
deadline because a live book may legitimately narrate for hours.

Four regression tests verify serialized two-engine retirement,
bounded refusal with a stuck predecessor followed by late
acknowledgment, permanent quarantine after disposal failure, and
a bounded terminal close when the active book's native Stop hangs
with two older engines queued. Code and tests authored only:
Dart analyzer, Flutter/native tests, Android builds and GitHub
Actions were not executed.

## 2026-11-04 — idempotent obsolete-player retirement

A reader's screen teardown and lifecycle callbacks can both request the
same obsolete player's retirement. Previously, a repeated request could
enqueue another *bounded* native-retirement fence even though the first
request was correctly waiting for the new reader to become silent. The
second fence could expire while the new book was legitimately speaking,
then falsely quarantine the MediaSession when the first cleanup completed.

`ReaderMediaHandler.retireDetachedPlayer()` now registers each player only
once using an `Expando` weak-key marker. Duplicate requests do not
create another quiet waiter, native dispose, or transport deadline; unique
old engines remain serially retired under the existing fail-closed policy.
A regression covers duplicate teardown during ongoing speech, silence
and native disposal, a subsequent explicit Play, and a third duplicate
after retirement. Flutter/Dart tests and Android native/device validation
remain **not run**; the PR stays draft.

## 2026-11-04 — guard late retirement after media detach

A delayed obsolete screen can request native TTS engine retirement after
the **last active book has already been detached**, but while that outgoing
book's native Stop is still pending. Merely checking `_player == null` as
proof of silence allowed an older engine's `dispose()` (which may issue a
global TTS Stop) to overlap the outgoing native operation.

`ReaderMediaHandler` now records a separate, bounded cumulative native-Stop
confirmation chain across detach events. An obsolete engine retirement waits
for this chain before checking the currently bound book. A false confirmation
quarantines disposal instead of interpreting a timeout as silence. When a
quiet-book waiter awakens, it rechecks the latest detached Stop chain and
current binding to avoid an obsolete quiet snapshot. The chain deliberately
does not include engine-retirement futures, avoiding self-deadlock.

Two synthetic regression tests cover detaching an actively narrating book
before late retirement arrives, including a Stop that times out and must
fail closed. An unsafe retired engine may remain quarantined until the
handler/session is replaced; never retry its native disposal based solely
on a timeout. This is source-level hardening only. Flutter tests, analyzer,
GitHub Actions and Android audio-device checks have **not been run**.

## 2026-11-04 — active-reader retirement is detached first

A lifecycle callback may call `retireDetachedPlayer(player)` before
`ReaderScreen.detach` has detached that very same player. Previously,
retirement would synchronously dispose its notifier while it remained
the active MediaSession owner. A later engine Dispose could issue a
native global Stop without first serializing the active speech Stop,
while the handler still advertised an active book.

Retirement now checks identity against the **currently bound** player.
Only for that exact player it calls `detach(player)` first. That path
invalidates remote transport requests, issues the bounded native Stop,
tracks its acknowledgment, removes the media notification and requests
audio-focus release. Engine retirement then waits behind the existing
detached Stop/quiet retirement barriers. A stale reader that is not
currently bound cannot detach its replacement.

Two additional synthetic regressions cover (1) active retirement with
a delayed Stop and immediate replacement-book Play, ensuring replacement
audio waits for Stop plus Dispose, and (2) a rejected active Stop,
ensuring engine disposal remains quarantined. No Flutter/Dart test,
analyzer, GitHub Actions or native Android test ran in this session.
The PR remains draft and its device-level safety is not proven.

## 2026-11-04 — coalesce duplicate Android media Pause/Stop

Two closely spaced Android media Pause/Stop calls previously invoked
`ReaderPlayer.pause()` twice while its serialized native Stop was still
outstanding. This queued an additional underlying `SpeechEngine.stop()`
instead of merely waiting for the original result. On shared native
speech backends a delayed redundant Stop can disrupt subsequent playback.

`ReaderMediaHandler.pause()` now shares the original transport Future for
the exact same player and narration-control revision. Every incoming media
Pause still increments the handler command epoch and invalidates pending
remote Play or skip intent, even when its Stop is coalesced. A new direct
Play, Seek or voice operation changes the player's control revision, so a
subsequent Pause starts a fresh cancellation/Stop instead of treating it
as an obsolete duplicate. The original Stop failure and focus-release
completion propagate to all sharing callers.

Detaching a player clears the retained coalescing references. This avoids
holding an obsolete book through a stalled asynchronous transport Future,
while leaving existing native Stop and engine-retirement fences intact.

Two synthetic regressions cover duplicate Pause + Stop on the same active
utterance, and a fresh direct Play between two Pauses while native Stop
is delayed. **Tests are authored, not executed**: Flutter/Dart SDK and
Android device verification are not available here. Actions were not
triggered. The PR remains draft pending actual build/audio validation.

## 2026-11-04 — revalidate post-focus retirement fence before Play

Remote Android Play already waits for the stop/retirement barrier before
obtaining audio focus, then checks it again after focus has been granted.
There was still a smaller asynchronous gap: Play could snapshot the
*current* post-focus barrier, suspend while awaiting it, and receive a
positive result after an obsolete ReaderScreen appended a **new** native
Dispose to `_pendingTransportStops`. The older positive result did not
establish that the new disposal had finished, so speech could start
while another Android TTS engine was shutting down.

The final post-focus Play gate now loops on a captured barrier Future
and checks identity against the **latest** `_pendingTransportStops`
after each awaited result. If a new Stop/retirement was registered, it
rechecks the newer barrier before dispatching `ReaderPlayer.play()`.
The identity check and dispatch have no intervening `await`; existing
command-epoch, binding and direct-control revision guards continue to
invalidate superseded Play requests. If the latest fence fails, Play
returns an error and relinquishes audio focus rather than attempting
speech.

Two synthetic regressions exercise:
- positive first retirement followed by a second delayed retirement
  registered while Play already awaits the first post-focus barrier;
  no speech is allowed until both disposals actually finish;
- a late second retirement that throws: Play remains blocked, reports
  the unsafe handoff and releases focus.

Test support allows a per-player larger `nativeStopTimeout` for these
deliberately held native gates, without changing the short timeout used
by the original timeout regressions. This is **source-level only**:
Flutter/Dart SDK, analyzer, test runner, native Android audio and
GitHub Actions have not been run. PR #1 remains draft.

## 2026-11-04 — explicit recovery also re-arms future detached disposals

After a detached book's native Stop timed out, the handler correctly
retained an unsafe native-Stop latch until a late **positive** platform
acknowledgment was verified by a fresh, explicit user Play. However,
the separate cumulative `_detachedNativeStops` fence still held its
historical `false` result after that successful recovery. As a result,
a completely unrelated older screen retiring later could remain
unnecessarily quarantined, despite the session having positively
verified every failed source.

The successful recovery branch now resets `_detachedNativeStops`
alongside `_pendingTransportStops`, but **only after** every tracked
unsafe source player is confirmed silent, no native disposal is unsafe,
and binding/revision/current-control guards still match. This does not
re-attempt any retirement already denied by its original false gate.
It also does not automatically retry Play, obtain Android focus or
trust the expiry of a timeout as a silence confirmation.

Two source-level regressions cover an original Stop that times out,
later confirms, and is explicitly recovered before a *subsequent*
obsolete engine is retired; and a real native Stop exception that
must keep later engine disposal quarantined. The success test awaits
the actual confirmed retirement Future, not merely the start of
`dispose()`.

No Flutter/Dart analyzer/tests, Android native audio/device test or
GitHub Actions were executed. PR #1 remains a draft pending validation.

## 2026-11-05 — separate native Stop confirmation from checkpoint latency

`ReaderMediaHandler._trackTransportStop` previously treated the full
`ReaderPlayer.pause()/seekTo()` command Future as proof of native Stop
completion. Yet `ReaderPlayer._stopCurrent` can confirm `SpeechEngine.stop()`
while its command Future continues waiting for the preceding
`onSegmentCompleted` durable SQLite checkpoint. If that checkpoint
stalled, a book replacement's Play or even `MediaHandler.close()` could
wait indefinitely despite an already silent physical TTS engine.

The handler now consumes the full original Pause/Seek Future (including
exceptions) while registering a separate **bounded**
`player.waitForNativeStopConfirmation()` as its cross-book audio fence.
`ReaderPlayer.pause()/seekTo()` remain responsible for their own
checkpoint sequencing and source cursor correctness. Remote command
callers still await and surface their own operation failures, including
database errors. A failed, timed-out or never-confirmed native Stop
still poisons the transport and requires explicit verified recovery;
checkpoint slowness by itself no longer masquerades as an unsafe TTS
engine.

Three deterministic source-level regression tests cover:

- New-book speech after the old engine confirms native Stop, while
  the old completed-segment database acknowledgment is still held.
- MediaSession close bounded by confirmed native Stop rather than the
  delayed database acknowledgment.
- Failed native Stop still blocking replacement speech even if the
  old completed-segment checkpoint has not yet finished.

These tests have been **written, not executed**. No Flutter/Dart SDK,
runner, native Android audio or GitHub Actions were run in this
environment. PR #1 must remain draft pending host and device validation.

## 2026-11-05 — bound Android task removal by native silence

Android `onTaskRemoved()` previously awaited the *full*
`ReaderMediaHandler.pause()` Future before detaching its media session.
Even after the native TTS engine acknowledged Stop, the command Future
could remain pending on a completed-segment SQLite checkpoint. Therefore
swiping away an Android task could indefinitely retain media metadata and
focus if the checkpoint never returned, despite already silent audio.

Task removal now starts the same Pause, separately **observes its complete
Future including late failures**, and waits for the player's bounded
`waitForNativeStopConfirmation()` before detaching. An unconfirmed or
failed physical Stop still produces a `StateError` and detaches the
same binding; the original checkpoint continues independently, retaining
its source-accuracy guarantees. After detaching, the handler awaits
the latest transport fence so a direct Play/Seek that raced the first
Pause cannot leave native audio in flight.

In `detach()`, if the same MediaSession Pause has already invalidated
the same player's latest control revision, it is reused: no duplicate
global native `SpeechEngine.stop()` is sent solely because storage
has not acknowledged the completed source segment. A new direct
ReaderPlayer Play/Seek increments its control revision; this
explicitly requires a fresh Stop during detach to avoid unwanted speech.

Four deterministic tests now cover task removal with a held durable
checkpoint (one native Stop and a completed teardown), a new direct
Play that supersedes the pending Pause (a fresh Stop required), a
failure in that *second* superseding Stop (reported rather than silently
accepted), and a failed original native Stop (task detaches, remains
unsafe, does not wait for the SQLite callback). Existing task-removal
tests retain checks for book reattachment and Stop errors.

These are **source-level changes only**. Neither Flutter/Dart tests,
GitHub Actions, nor Android on-device background/audio lifecycle tests
were executed for this change. PR #1 remains draft.

## 2026-11-05 — release native audio focus independently of delayed source checkpoints

The earlier change separated physical Stop **confirmation** from a
delayed `onSegmentCompleted` SQLite checkpoint in transport barriers.
Two other uses of `ReaderPlayer.isSettledIdle` still inadvertently
treated an unfinished durable checkpoint as audible native speech:

1. The media player's change listener did not release Android audio
   focus after a confirmed Stop until the SQLite checkpoint completed.
2. A retired old Android TTS engine remained queued behind the *current*
   book's checkpoint, even after the current engine had confirmed native
   silence. This could strand deferred engine disposal (and related
   lifecycle verification) on a slow database callback.

`ReaderPlayer.isNativeAudioQuiet` now expresses exactly the audio-only
quiescence condition: no live Play, no queued native Stop, no unconfirmed
or failed Stop, and **no pending navigation intended to auto-resume**.
It deliberately does not wait for the completed-segment checkpoint.
The existing stronger `isSettledIdle` still includes that checkpoint
and remains the guard for seek/pause/navigation decisions, preventing a
pending source cursor change from being mistaken for settled navigation.

`ReaderMediaHandler` uses the new audio-only condition for Android
focus release and the waiters controlling late obsolete engine Dispose.
A direct Play or an auto-resuming Seek continues to block disposal and
retains focus until native speech is genuinely quiet. Native Stop errors
remain fail-closed.

Three source-level regressions check: focus releases while a completed
segment checkpoint stays held; a retired engine can finish disposal
after confirmed native silence despite that checkpoint; and a queued
auto-resuming Seek still blocks focus release and obsolete-engine disposal
until its restarted audio has been stopped. None of these tests or Android
device lifecycle scenarios has been executed in this environment.
