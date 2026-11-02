# Searchable EPUB chapter directory

2026-11-02 · `feature/m0-flutter-foundation` · draft PR #1

## Why

EPUB navigation previously opened a virtualized contents sheet near the
current section, but books with hundreds or thousands of authorial
navigation entries required extensive manual scrolling. The same issue
affected OPF spine fallback lists, especially illustrated or
non-narratable sections.

## Implemented

- A **Find a chapter or section** field now appears in the EPUB
  contents sheet. Search is case-insensitive and matches *all* entered
  whitespace-delimited words against each entry's title.
- Results preserve the original publisher TOC order and, critically,
  the **original directory indices**. The first matching row does not
  become section zero. Selecting a filtered entry returns its original
  index to the reader's existing source-exact navigation pipeline.
- Publisher TOC and OPF spine remain distinct. If a publisher TOC is
  available it takes priority, retains its indentation depth and
  labels, and may target visual content that cannot be narrated.
  Otherwise every original spine section remains accessible, including
  empty/image-only sections that share UTF-16 source offsets.
- The active/current row remains selected and labeled; unfiltered lists
  open near that section, while a filtered list opens near the first
  result. Rendering remains virtualized through
  `ScrollablePositionedList.builder`.
- Search result counts, a clear-search action and a no-results message
  make the sheet usable on long books. Search does not invoke TTS,
  change the visual/audio cursor, or write SQLite progress.
- On narrow Android screens the modal grows into available space
  **above the on-screen keyboard**, and collapses secondary header
  metadata when space is tight. Search has no automatic keyboard
  activation on opening the contents.
- If a book changes/reloads while the sheet is displayed, the returned
  selection is discarded. The existing source-selection revision gate
  still handles overlapping native Pause/Seek once an action is chosen.
  Closing the sheet or clearing the query is never a navigation action.

## Changes

- New `lib/features/reader/reader_chapter_directory_sheet.dart`:
  pure original-index mapping/filter and a separate searchable,
  keyboard-aware, virtualized picker.
- `lib/features/reader/reader_screen.dart`:
  invokes the picker and validates active book, player, loaded document
  and load epoch before routing the original index through existing
  `_navigateToSourceOffset` / `_jumpToChapterIndex`.

## Regression tests authored

`test/features/reader_chapter_directory_sheet_test.dart` covers:
1. Matching multiple words case-insensitively while preserving
   duplicate publisher labels, nested depth and editorial order.
2. Silent OPF spine entries with identical source offsets retaining
   their separate destination indices.
3. A **2,000-entry** publisher directory, virtualized near the current
   section; filtering to one remote result must return its original
   index (not filtered-row index zero).
4. Search without results, query clearing, and dismissing without
   selecting a destination.
5. Small **320px** layouts at 200% text scaling.

## Manual acceptance

Open a large EPUB with a valid NAV/NCX, use Contents from the AppBar
or compact Quick navigation, search for a title, verify the correct
section and source position, then search a duplicate label and
confirm each original row retains its own destination. Repeat with
silent illustrated spine sections and while audio is playing. No audio
should start merely because a query is typed. Cancel must not update
book progress. Verify with keyboard visible on Android and with
screen-reader navigation.

These changes and tests have been committed, but **Flutter tests,
analyzer and real Windows/Android runtime checks were not executed**.
Per project preference no Windows build or GitHub Actions were
launched. PR #1 remains draft pending execution and manual QA.
