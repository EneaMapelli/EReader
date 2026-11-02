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
