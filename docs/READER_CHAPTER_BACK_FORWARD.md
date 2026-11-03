# EPUB Back / Forward through chapter visits

Implemented 2026-11-03 · branch `feature/m0-flutter-foundation` · draft PR #1.

## Update · 2026-11-03: accessible direct history shortcut

A **single contextual history icon** now exposes Back, Forward and
Recent chapter positions directly from the compact transport row or
from the immersive AppBar, without adding a new bar or showing TTS
controls. The recent-positions sheet has explicit TalkBack action
labels for every saved visit. The existing navigation/back-stack
semantics below remain unchanged. See
[READER_CHAPTER_HISTORY_SHORTCUT_A11Y.md](READER_CHAPTER_HISTORY_SHORTCUT_A11Y.md).

## Update · 2026-11-03: modal snapshot safety

Reader tools and compact Quick navigation now check that a chapter
Back/Forward/Recent history action still refers to the same history
revision captured when the menu opened. A different committed chapter
change while the sheet is open invalidates only the old return command;
it cannot silently target the new Back/Forward entry. Percentage and
EPUB-link returns have separate snapshot guards. See
[READER_CONCURRENT_NAVIGATION.md](READER_CONCURRENT_NAVIGATION.md).

## Reading experience

The reader now supports **both directions** through committed EPUB chapter
visit history, separately from the TTS segment controls:

- **Return before chapter change** moves **Back** to the most recent
  previous original-source reading location.
- **Recent chapter positions** lets readers choose an earlier Back entry.
- **Forward to next visited position** appears only after a completed
  Back navigation, when a later visited position can be revisited.

All commands are available in **Reader tools** and mobile
**Quick navigation**, when their actual history state permits.

Example: from chapter position A navigate to B, then C and D.
Choose A from the history sheet. The reader returns to A and retains
B → C → D as the Forward path. Successive **Forward** commands
restore B, then C, then D, in chronological order. After the last
Forward, its menu action disappears. Back history is restored step by
step as Forward progresses.

If the reader returns from D to A and then **intentionally chooses a
new chapter E** with the EPUB section arrows, the directory,
keyboard or advanced controls, this establishes a new branch:
the previous B → C → D Forward path is cleared. The backward
history of actual committed moves remains available.

A failed, canceled, invalid, no-op or superseded chapter jump does
not erase Forward history.

## Source accuracy and safety

`ReaderChapterVisitHistory` now maintains two bounded in-memory
stacks of original source positions: Back and Forward, both capped at
20 entries. Each visit retains its publisher/OPF section title, 1-based
ordinal, original canonical UTF-16 offset and optional illustrated-only
OPF `spineIdref`. The Forward stack is never saved as SQLite data.
Both stacks clear on book reload.

The source seek remains owned by the existing reader pipeline:

1. Before Back/Forward, capture the current **visual** chapter source
   offset and optional silent OPF identity via
   `_captureChapterVisit`, using the same visual/narration ownership
   rule as normal EPUB chapter navigation.
2. Request the return through `_jumpToSourceProgress`, never a
   separate TTS audio seek or a blind `savePosition`.
3. After the winning `_select(onCommitted)` persists its SQLite
   reading checkpoint, and only then, mutate Back/Forward using the
   exact expected revision and an entry's **object identity**.
4. A Back to an older visit transfers the traversed later positions
   plus the just-departed current location to Forward in the correct
   reverse-stack order. A successful Forward pops its immediate
   target and pushes the departed location back onto Back. The
   remaining Forward path is not cleared by a Forward operation.
5. An explicit successful chapter change records a new Back origin
   and clears Forward. Invalid/no-op selections leave both alone.

The original **percentage Go return point** and **EPUB note/link return
stack** remain independent. Neither is added to chapter Back/Forward,
nor consumed by those actions. Manual scrolling alone does not create
a Back/Forward event or overwrite the active history.

## Tests authored

- `test/features/reader_chapter_visit_history_test.dart`:
  immediate Back/Forward, chronological Forward after choosing an old
  visit, new-branch invalidation only after committed navigation,
  stale revisions, object identity, same-offset silent OPF sections,
  bounded capacity and unchanged legacy Back behavior.
- `test/features/reader_tool_menu_options_test.dart`:
  Forward menu and Quick navigation gating, including availability
  with **no Back entries**, absence in TXT/PDF/unplayable EPUBs,
  and distinct action ordering.
- `test/features/reader_focus_epub_integration_test.dart`:
  the self-contained two-chapter EPUB fixture creates three
  switches, returns to the oldest, traverses all three Forward
  destinations in sequence, and verifies that a different
  committed chapter switch invalidates redo.

## Manual device acceptance

1. Navigate A → B → C → D. Back to A using the visit sheet.
   Forward three times; verify positions B, C and D in order.
2. Return to A again and choose an unrelated chapter via the normal
   EPUB directory. Verify Forward disappears only after the seek
   successfully commits.
3. Test Back and Forward in both immersive focus and normal compact
   modes. Narration must not automatically start.
4. With visual EPUB covers/illustrations sharing equal UTF-16 offsets,
   verify both directions restore the correct OPF spine identity.
5. Rapidly issue competing chapter actions; older asynchronous
   source completions must not mutate current Back/Forward.
6. Switch/reload the book; verify old session history cannot navigate
   the new session. TXT and PDF must not show EPUB Back/Forward actions.
7. Check TalkBack and large-font mobile Quick navigation. The Forward
   command is distinct from both *Next EPUB section* and *Next spoken
   segment*.

**Verification status:** implementation and regression test code have
been published and statically inspected. Flutter analyzer, widget and
integration tests, device playback tests, Windows builds and GitHub
Actions have **not** been run. PR #1 stays draft.
