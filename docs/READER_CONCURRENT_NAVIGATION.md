# Concurrent reader navigation — latest explicit intent wins

Implemented on `feature/m0-flutter-foundation` on 2026-11-02.
Draft PR #1; source-level verification only (Flutter SDK unavailable in
this execution environment). No Windows builds or GitHub Actions invoked.

## Race closed

Prior to this increment `ReaderScreen._select` acquired its
`_selectionRevision` only after a caller's `await player.pause()`.
This left a narrow but real race:

1. Select a search result while TTS plays; the handler awaits native Pause.
2. Immediately select a different bookmark/chapter. Its Pause/Seek finishes
   first and the new source selection commits successfully.
3. The *older* handler resumes from its Pause, then enters `_select`,
   incrementing the revision **after** the newer operation. It can seek
   backward and persist the wrong reading checkpoint.

The existing guards inside `_select` could not protect this pre-Seek
window because the older handler had not yet registered its intent.

## Current contract

`ReaderSourceSelectionGate` is a pure in-memory revision guard.
Each user source-selection operation reserves a monotonically newer
revision **before** any asynchronous native Stop/Pause. On returning,
it checks the reservation and passes the same token into `_select`.
Only a current token may initiate a Seek, write a manual checkpoint,
or change the visual cursor. The common `_select` still rechecks after
the player Seek and after the SQLite write before repainting.

The reservation is shared by:

- EPUB publisher TOC and spine-section jumps.
- EPUB full-source search, bookmark navigation, internal links and
  footnote return.
- Clicking source-aligned spoken spans (including EPUB active audio).
- TXT/PDF text-mode percentage jumps and their return points.
- Existing immediate previous/next segment and text selection via
  the same `_select` method.

A confirmed media-handler navigation invalidates older local intents;
reopening/reloading a book invalidates all pending selections. A local
explicit **Play** also reserves a fresh intent and rechecks it after
any pending source Seek but before starting playback. This prevents an
old Play continuation from automatically restarting speech after a
newer chapter/bookmark selection.

The EPUB link-history push/pop and the post-search highlight remain
commit-only and now additionally verify that the intent is still
current before mutating the return stack. The previous policy for
temporarily detached vs explicitly disabled auto-follow is preserved.

### Limitations

This guard governs **local application continuations**, not native
speech-provider cancellation. Once a platform Pause/Seek operation has
been issued, its actual interruption behavior is controlled by
`ReaderPlayer` and the engine. A native SDK test remains necessary.

`LibraryStore.savePosition` performs its SQLite UPDATE synchronously
before returning a Future. This guard prevents starting an obsolete
write but cannot undo a write already completed before a newer request
was made. The newer successful selection must persist its own location.

## Authored regression tests

`test/features/reader_source_selection_gate_test.dart` covers:
- Older Pause completing after a newer bookmark selection.
- A failed/newer request not resurrecting previous requests.
- Remote media navigation invalidating an older local selection.
- A late Play continuation suppressed after a later explicit selection.
- Reloading the reader invalidating pending source navigation.

These tests are committed, **not run**.

## Manual QA

1. Play an EPUB and rapidly choose two different publisher TOC entries.
   Verify only the final request sets the viewport, progress, and bookmark.
2. During TTS playback select a search result, then immediately a bookmark.
   Observe that the older search cannot highlight another chapter or
   restart audio after the bookmark commits.
3. Follow an EPUB internal link and rapidly invoke Return while a
   subsequent chapter selection starts. The return stack must not pop
   on behalf of the obsolete navigation.
4. Repeat with spoken-segment tapping, silent OPF chapters and full-text
   search in long EPUB books.
5. In TXT and PDF extracted-text reading, start a percentage jump then
   a different passage selection; verify the latest intended position.
6. Start Play from one passage while a native voice engine is slow, then
   navigate to another chapter. The late Play callback must not launch
   an unsolicited playback after the newer source selection.
7. Use hardware/lock-screen Next or Previous while a local source Seek
   is pending. Verify current audio location, active TTS highlight,
   displayed cursor, and saved progress remain coherent.
8. Switch books or close the reader during an in-flight Seek. The older
   selection must not modify the new book or open a stale screen.
9. Repeat with both native system and alternate offline TTS engines.
   The latest-choice behavior must be consistent regardless of Stop
   latency and the engine's auto-resume behavior.

No automated tests, builds, or GitHub Actions have been launched.
Keep PR #1 in draft until Flutter analyzer and native verification pass.

## 2026-11-03 — stale return commands in open reader tool sheets

A reader tools / compact Quick navigation sheet captured **visibility** for
Back, Forward, recent chapter positions, percentage return and EPUB
internal-link return at opening. Before this change, a remote media
navigation or another committed selection could change one of those
return channels while the sheet was open. Choosing its *old* menu row
would then silently navigate to the **new** origin, even though that
destination was not the one the user saw when opening the sheet.

The reader now snapshots the two versioned chapter/percentage return
revisions and the exact identity of the current EPUB link return object
when a tools sheet opens. After dismissal/selection and the existing
book/session/player guards, the selected action is checked against
those snapshots. An obsolete return action exits **without** a Seek,
checkpoint write, history consumption or narration start. Each return
channel is checked independently, so a newer percent jump does not
disable a still-current chapter Back action. Fresh destination actions
(search, contents, Go, bookmarks) and settings stay available.

This deliberately supplements, rather than replaces, the existing
latest-intent gate: the latter already guards asynchronous Stop/Seek;
the new check protects the **pre-navigation modal window**.

Added pure regression scenarios in
`test/features/reader_tool_menu_options_test.dart` for stale Back,
Forward, recent history, percentage and link returns, identity-unequal
link origins and cross-channel independence. Dart/Flutter tests are
authored but **not run**; no build, Action or native acceptance performed.

## 2026-11-03 — rapid EPUB navigation regression coverage

Added two real `ReaderScreen` widget integration scenarios using the
existing self-contained two-chapter EPUB fixture and temporary SQLite store:

- Rapid double-tap of **Next EPUB section** without an intervening
  settle must persist exactly one winning destination, create only one
  Back origin, and allow a subsequent Back → Forward traversal to
  restore both durable source offsets.
- Ctrl+End → Ctrl+Home → Ctrl+End in immersive reading mode (without
  intermediate settle) must leave both the SQLite source position and
  displayed publisher-section number at the latest intended chapter.
  Ctrl+Shift+Page Up / Page Down then navigate the committed history
  without revealing hidden narration controls.

Added two deterministic, pure gate/history model tests with delayed
native-Pause and delayed SQLite-Future continuations. They assert that
obsolete operations cannot append a chapter visit or repaint the
viewport, and that the final persisted offset belongs to the latest
successful intent. These are **contract simulations** of the production
gate and history, not substitutes for the widget/native tests.

Files:
`test/features/reader_focus_epub_integration_test.dart` and
`test/features/reader_source_selection_gate_test.dart`.

**Verification:** tests authored and source structure checked only;
Flutter tests/analyzer, device builds and GitHub Actions NOT executed.
The exact one-write expectation deliberately makes duplicate commits
a regression failure; it has not yet been validated against a native
player or a Flutter test runtime.

## 2026-11-03 — superseded failure reporting and redo branching

The chapter jump error handler now captures its local selection token
*before* waiting for native Pause. If a newer selection or reload
invalidates it, an old asynchronous failure is discarded rather than
displayed over the new chapter. The EPUB source-offset navigation
handler also remembers the initiating player/token for this purpose.
Actual current navigation failures still display their error.

An additional delayed-Pause gate/history regression explicitly models
an old **Back** request losing to a newly selected chapter: it asserts
that the final durable checkpoint and visual source point remain at
the new destination, all committed Back entries remain intact, and
Forward is not fabricated. A new full widget/SQLite EPUB test checks
that an actual **Ctrl+Shift+Page Down** issued after a new publisher
chapter branch produces no additional durable write or stale redo.
The tests complement the previously authored rapid chapter tests.

No Flutter analyzer/test or native runner was executed. The two
regressions and source error handling require final integration review.

## 2026-11-03 — stale TTS and navigation error notifications

A playback error is displayed in the next Flutter frame. Previously a
queued TTS error could be shown **after the player was reloaded**; in
addition, the reader's error deduplication object survived between player
sessions. The deferred notification now checks that its original
player is still installed and still owns that exact error. A newly
adopted player clears the old error deduplication reference.

The explicit Play/Pause handler and passage Next/Previous now check
source-intent freshness in their asynchronous error paths. For a
passage move, the intent is reserved before the Seek and handed to
`_select`, so a superseded seek cannot display a misleading error.
EPUB link return, tapping a text passage, and TXT/PDF percentage Go
have equivalent originating-player/token guards on their error
callbacks. Remote media callbacks now ignore a negative destination
before indexing speech segments or invalidating a pending local intent.

The gate exposes its current revision for transport commands that
need to associate a later failure with the original intent. Two
deterministic asynchronous gate tests cover an obsolete native
failure suppressed after a subsequent selection and a still-current
failure that remains reportable.

No Flutter analyzer, widget tests, device builds or GitHub Actions
were run; source-level exact-match checks only.

## 2026-11-03 — queued viewport save invalidation before native Pause

An explicit EPUB source selection may need to wait for a slow native
Pause before calling the common `_select` source seek. Previously,
several routes only called `_saveVisualPositionTimer?.cancel()` at
intent time, or relied on `_select` to call
`_cancelPendingVisualSave()` after the Pause barrier. Canceling a Timer
alone does not invalidate an already-queued callback that captured the
old `_visualSaveRevision`.

All explicit selection routes now call `_cancelPendingVisualSave()`
immediately when reserving their source intent, **before** awaiting
native Pause/Seek. This covers publisher TOC/spine chapter changes,
EPUB bookmarks, internal link/navigation, note return, tapped
passages, TTS previous/next segment commands and extracted TXT/PDF
percentage jumps. The method both cancels the pending viewport
timer **and** increments the revision checked by delayed callbacks.
The common `_select` continues to invalidate again before seeking;
this is intentional, so an existing callback cannot persist between
the user's command and the actual source seek.

This protects two independent effects:

1. A stale asynchronous source command still cannot win over a newer
   command due to `ReaderSourceSelectionGate`.
2. A queued/debounced visual-scroll save from *before* that command
   cannot write an outdated source anchor during native Pause or
   after a newer durable chapter checkpoint.

Added a generated two-chapter EPUB widget regression in
`test/features/reader_focus_epub_integration_test.dart`:
it scrolls the reader, immediately changes EPUB section, then waits
beyond the 450ms viewport debounce. The resulting checkpoint must
still point into the committed chapter, with exactly one manual
source-position write relative to the original revision.

**Validation:** source edits and test authored, not executed under
Flutter or a native TTS engine. Windows builds and GitHub Actions were
not triggered; PR #1 remains draft.

## 2026-11-03 — failed manual-scroll checkpoint handling

The idle, debounced viewport save used to call
`LibraryStore.savePosition` from a synchronous Timer callback without
observing the returned Future. A SQLite failure therefore could surface
as an **unhandled asynchronous error** even when the reader remained
usable. That is distinct from an obsolete chapter selection.

The reader now routes those writes through
`persistReaderViewportCheckpoint`, which catches storage failures and
re-evaluates the original book, player, document, scroll revision,
settled-idle state and EPUB source coordinate before reporting the
result. A failure of a superseded write must not display a misleading
warning over the current chapter or during narration. A current failure
shows one actionable snackbar; repeat failures are coalesced until a
successful viewport checkpoint or a book reload, and the user may
scroll again to retry. A synchronous SQLite write already committed
before a later intent is not rolled back.

Added four deterministic tests to
`test/features/reader_viewport_save_gate_test.dart` for a rejected
write, canceled request before the write, rejected old Future after
a new source selection, and successful retry clearing the failure
indicator. These are source-level tests authored but **not run**;
Flutter/device/Windows builds and GitHub Actions were not invoked.

## 2026-11-03 — foreground/route boundaries for deferred viewport saves

An idle manual-scroll checkpoint was previously allowed after a timer
whenever narration was settled and no newer source selection had
invalidated its revision. An app can become `inactive` (for example
during a notification shade transition) without reaching the
`hidden`/`paused` lifecycle states that canceled that timer. Also,
a reader route can be covered by another page while it remains mounted.
Neither is evidence of a new user reading location.

`readerMaySaveVisibleViewport` now requires three independent
conditions: the reader is in the foreground, its route is the
current navigator route, and the viewport gate is authorized after a
real user scroll. This check is enforced both when receiving visible
item positions and immediately before/completing a delayed SQLite
save. Any non-resumed lifecycle state invalidates the pending
scroll-save revision and suspends viewport saves until a new verified
scroll gesture; merely resuming does not reauthorize old layout events.

The separate explicit chapter selection, source bookmark and Android
background speech/recovery checkpoint pipelines remain unchanged.
Two pure unit tests cover foreground/route/gesture eligibility and
resume-after-suspension behavior. A two-chapter EPUB widget regression
queues a user scroll, deactivates/resumes the app, waits beyond the
450ms debounce, and checks that the old SQLite checkpoint remains
unchanged; an explicit chapter jump must still commit afterwards.

Validation: patches and regression sources authored; Flutter analyzer,
widget tests, Windows/Android builds and GitHub Actions **not run**.
