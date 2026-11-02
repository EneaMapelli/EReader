# Committed navigation handoff — search, bookmarks, TOC and TTS follow

_Status: 2026-11-02, source implemented on `feature/m0-flutter-foundation`;
draft PR #1. Flutter/device verification pending._

## Issue

Temporary auto-follow suspension is for *consulting* another passage while
narration continues. It must not survive an intentional, confirmed source
seek such as selecting a search result, bookmark, chapter, EPUB hyperlink,
or percentage. Conversely, merely opening or dismissing the search dialog,
cancelling a source seek, or losing an async seek to a newer selection must
not reattach the viewport or paint a success highlight.

Previously, the common `_select` method had no path to clear temporary
detachment after an explicit selection, and the EPUB search UI assigned the
selected highlight before the asynchronous source navigation was confirmed.

## Implemented contract

1. `ReaderNarrationFollowPolicy.onCommittedNavigation()` clears only a
   **temporary** manual-scroll detachment. It never turns on a
   deliberately disabled **Follow narration** preference.
2. All in-reader source selections share the existing
   `ReaderScreen._select` pipeline: requested speech/source Seek,
   latest-selection revision and native intended-cursor check, durable
   library checkpoint, **second latest-selection guard**, then update
   visual position and narration-follow state. A failed, superseded or
   canceled operation does not change follow ownership.
3. The common commit updates UI for **EPUB, TXT and PDF extracted text**.
   Previously the post-selection `setState` path was limited to EPUB:
   TXT/PDF could retain a stale floating return control.
4. EPUB search passes `BookSourceMatch` through the navigation pipeline,
   but applies the source-exact highlight **only at the winning commit**.
   Failed search navigation preserves the preceding highlight rather than
   presenting an unconfirmed result. Selecting another destination clears
   the previous search highlight once the new destination commits.
5. The media handler invokes `onRemoteNavigation` only after a winning
   remote audio Seek. Paused explicit remote chapter navigation resets a
   temporary detachment and aligns the viewport, while active remote
   movement during detached browsing continues to leave visual reading
   independent of audio. Explicitly disabled follow stays disabled.
6. **Return to narrated passage** continues to be a distinct visual-only
   action: it reconnects the viewport without doing a source seek or
   writing a reading checkpoint. **Pause/Play while detached** continues
   to resume the existing audio cursor rather than jumping to viewed text.

No speech synthesis, provider, network, database schema, or saved follow
preference was changed.

## Tests added or extended

- `test/features/reader_narration_follow_policy_test.dart` now covers
  successful committed navigation, canceled/uncommitted transitions,
  the difference between disabled and temporarily suspended follow,
  and paused remote chapter completion.
- Existing source-accurate EPUB paragraph search/tap tests and
  `reader_position_ownership_test.dart` remain part of required
  regression coverage.

## Manual verification (Windows and Android)

1. Start EPUB narration, manually scroll away and observe the detached
   audio-status chip. Open then **cancel** Search: detachment and the
   previous highlight should remain unchanged.
2. Search for a different word and choose a hit. Confirm navigation
   completes, the return button/status chip disappear, and only the
   newly selected source range is highlighted. No unsolicited Play.
3. Repeat with a bookmark, publisher TOC, silent EPUB spine chapter,
   internal hyperlink, Go to percentage, and Return after jump. Each
   successful seek must remove temporary detachment and preserve its
   precise UTF-16/OPF anchor.
4. Disable **Follow narration** explicitly, then navigate using search
   or a bookmark: the preference must stay OFF and no temporary
   detachment button should appear.
5. Repeat TXT and PDF extracted-text selection: no stale return chip,
   progress display and visible position correspond to new selection.
   Native PDF page mode must not be affected.
6. While detached, pause and press Play *without* selecting a new
   destination: audio resumes its prior speech cursor, view stays put.
7. Trigger rapid successive navigation requests (e.g. two chapter
   jumps). Only the winning seek should update the highlight/return
   history, even when the native Stop/Seek barrier runs slowly.
8. Use lock-screen or hardware media next/previous while paused and
   detached. After a successful seek the viewport should reconnect;
   while narration continues it should stay detached.
9. Repeat with layout/rotation changes, long books and screen reader.
   Validate that canceled operations do not rewrite saved progress.

**Validation:** changes and tests are committed, but `flutter analyze`,
unit/widget suites, and real Windows/Android media tests have not been
run. Per project preference no Windows build or GitHub Actions were
triggered. Keep PR #1 draft until verified.
