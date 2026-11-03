# EPUB chapter visit history (session-only)

Implemented on `feature/m0-flutter-foundation` · 2026-11-03 · draft PR #1.

## Reading workflow

After **two or more successfully committed EPUB chapter changes**, the
**Recent chapter positions** action becomes available under both
**Reader tools** and **Quick navigation**. It opens a scrollable list,
**newest first**, showing each original publisher/OPF chapter title,
its source chapter number, and its percentage in the **whole book**.
The list records **locations immediately before chapter changes**; it
is not a log of every manual scroll, TTS segment, bookmark or note.

Tap an entry to return to that **exact original reading location**,
including a mid-chapter position, and then discard that entry plus
all more recent entries. Any older locations remain available.
The existing **Return before chapter change** continues to provide
the one-tap latest return, but now it pops only the most recent item
rather than replacing the entire previous history.

Opening, browsing, scrolling or canceling the history sheet does not
start narration, change the visual location or save a checkpoint.

## Storage, identity and safety

`ReaderChapterVisitHistory` is an **in-memory, bounded (20 visits)**
stack. It retains immutable `ReaderChapterVisit` objects with:
- Canonical original UTF-16 source offset.
- Optional OPF `spineIdref` for visually distinct covers/illustrations
  sharing identical source offsets.
- Publisher NAV/NCX or OPF fallback title and original 1-based section
  number/count as of the committed switch.

The newest 20 visits are retained. On overflow, the oldest item is
evicted. The history clears when the reader reloads the book. It
is **not persisted to SQLite**; only the actual current reading
checkpoint is saved by the existing source-navigation pipeline.

On every chapter switch the reader captures the origin before
navigating, but **pushes it only after the winning `_select` seek
has persisted the new checkpoint**. Invalid/no-op/failed/superseded
operations do not overwrite previous history.

When showing the history:
1. Create a read-only newest-first snapshot of the exact
   `ReaderChapterVisit` objects; the sheet returns an object, not
   a displayed list position or an inferred EPUB offset.
2. On selection, revalidate book ID, loading epoch, player, document
   and the history **revision**. Ignore a stale sheet after reload
   or a different committed chapter navigation.
3. Return using `_jumpToSourceProgress`, supplying the stored OPF
   spine identity to restore illustrated-only pages correctly. The
   existing latest-wins source gate and durable SQLite checkpoint
   remain authoritative.
4. After a winning return commit, consume the chosen entry and all
   newer entries using object identity and the exact history revision.
   A canceled, failed or superseded seek cannot consume anything.

The chapter stack, percentage-return point and EPUB footnote/link
history remain independent. Returning from chapter history never
erases another return channel.

## UI

`reader_chapter_visit_history_sheet.dart` implements a bounded,
keyboard- and screen-reader-accessible modal list with a clear close
button. On narrow phones and enlarged text, chapter labels are
limited to two lines and the list remains scrollable. TXT and PDF
readers do not show EPUB chapter history actions; a single chapter
return does not add a redundant history command.

## Regression tests authored

- `test/features/reader_chapter_visit_history_test.dart` covers newest
  order, 20-entry eviction, immutable history snapshots, selecting
  older entries while retaining older history, invalid/no-op records,
  outdated revisions, equal-offset illustrated spine identity, and
  separation from percentage and internal-link history.
- `test/features/reader_chapter_visit_history_sheet_test.dart` covers
  identity-accurate selection, cancellation/close with no mutation,
  an empty history, and 20 scrollable entries on a 320px phone at
  200% text scale.
- `test/features/reader_tool_menu_options_test.dart` verifies menu
  and Quick navigation visibility only when two or more EPUB visit
  origins are available (never TXT/PDF).
- `test/features/reader_focus_epub_integration_test.dart` uses the
  existing generated two-chapter EPUB3 ZIP to accumulate three
  committed chapter switches, open/cancel the history, return to the
  oldest origin, then confirm history actions disappear after its
  successful consumption.

## Manual acceptance

1. Read partway into chapter 1. Jump to chapter 2, back to chapter 1,
   and to chapter 2 again. Verify **Recent chapter positions** shows
   multiple entries, newest first.
2. Open and dismiss the history without selecting anything; confirm
   narration and the saved position are unchanged.
3. Pick an older entry and verify an exact return. Reopen the sheet:
   selected/newer entries should be gone; older ones remain.
4. Test **Return before chapter change** repeatedly; each committed
   return should pop one entry without clearing the entire stack.
5. On EPUBs with silent illustrated covers sharing the same text
   source offset, verify the correct OPF visual item is restored.
6. Rapidly switch chapters while a return is pending, or reload the
   book with the history sheet open: old completions must not remove
   newer entries or navigate in the reloaded session.
7. Check 320px / 200–300% accessibility text, split-screen, TalkBack,
   and both Quick navigation and full Reader tools.

**Validation:** implementation, widget/unit/integration test sources
and documentation are committed. Flutter analyzer and tests have not
been executed in this environment. No Windows executable or GitHub
Actions were triggered; PR #1 remains draft.
