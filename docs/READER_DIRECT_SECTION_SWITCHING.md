# Direct previous / next EPUB section controls

Implemented on `feature/m0-flutter-foundation` · 2026-11-03 · draft PR #1.

## Reader experience

When the reader is displaying an EPUB with a publisher table of contents
(NAV/NCX) or OPF spine fallback, **Previous EPUB section** and
**Next EPUB section** buttons now flank the current chapter shortcut:

- In the **compact narration panel**, the chapter row has a previous
  section arrow, a central **Open table of contents** label/percentage,
  and a next section arrow. The spoken-segment previous/next transport
  buttons remain in their original separate row below.
- In **immersive focus mode**, the same chapter arrows appear on the
  48px EPUB section header below the existing 44px global-progress
  bar, without showing the narration transport.

At the first section, **Previous EPUB section** is disabled. At the
final section, **Next EPUB section** is disabled. No arrows are shown
when no valid chapter metadata is available, including normal TXT and
PDF readers. The existing advanced reader chapter controls and
keyboard shortcuts still use the same destination logic.

Tapping the chapter title/number still opens the searchable directory.
Tapping the optional local percentage in focus mode still opens the
chapter-local Go dialog; tapping the whole-book progress bar still
opens global Go. The new arrows are independent from both dialogs and
from the TTS previous/next segment controls.

### Accessible, narrow-screen layout

The EPUB chapter row uses a separate button for each action, with
individual keys, tooltips and disabled states. Icons provide
48x48 logical-pixel touch targets. The central chapter title truncates
rather than pushing the buttons off a small screen.

For focus mode at text scale 200% on a 320px viewport, the visible
ordinal is omitted to preserve enough width for the title and buttons;
its **full ordinal and chapter name remain in the central button's
TalkBack semantics**. The compact narration row continues to provide
its own truncating chapter title and index.

## Source and TTS behavior

Both new buttons call the existing `ReaderScreen._jumpDirectoryRelative`
method. That method resolves the active **visual EPUB directory
position**, calculates the adjacent original publisher TOC or OPF
spine index via `adjacentReaderSectionIndex`, and delegates to
`_jumpDirectoryIndex`.

There is **no duplicate source-selection or native speech pipeline**.
The existing source-exact seek, latest-wins selection gate, Stop
barrier and SQLite reading-anchor checkpoint remain responsible for
confirmed navigation. Navigating between sections does not
automatically resume narration; ordinary TTS segment transport
remains distinct. An unavailable direction is disabled before
dispatch.

The displayed chapter name, ordinal and local progress continue to
track `_visualProgressTick` when the user scrolls away from the
narrated passage.

## Regression tests authored

- `test/features/reader_compact_controls_test.dart`: separate
  callbacks for the two EPUB arrows, TOC entry and TTS previous/next;
  verifies disabled previous/next at book edges and the existing
  320px / 200% text-scaling layout with both arrows enabled.
- `test/features/reader_focus_progress_strip_test.dart`: independent
  focus-header actions, disabled first/last buttons and no overflow
  with large text; full chapter ordinal remains available via
  semantic labels when hidden visually.
- `test/features/reader_focus_epub_integration_test.dart`: an
  in-memory, self-contained EPUB3 fixture is imported through
  `LibraryStore`. The test jumps to chapter two in focus mode,
  verifies the stored source checkpoint and disabled next arrow,
  jumps back to chapter one, restores compact narration controls
  and repeats the jump via the compact next-section arrow.

## Manual acceptance checklist

1. Open a two-chapter EPUB, verify first-chapter Previous is
   disabled, select Next, and confirm the second chapter appears
   without starting narration.
2. At the final chapter, verify Next is disabled. Navigate Previous
   and check the saved reading location and visual highlight.
3. In focus mode, verify the arrows work without displaying audio
   controls. Restore controls and verify chapter/segment actions
   remain distinct.
4. Repeat with a publisher TOC in non-spine order, and with OPF-only
   content containing multiple silent illustrated sections sharing
   source offsets. Explicit chapter selection must continue to
   preserve source anchors.
5. Rotate a 320px phone at 200–300% text scale, with a long
   translated chapter name. Verify all three EPUB navigation targets
   remain reachable without text overflow.
6. Confirm TXT and PDF show no EPUB section arrows; check that
   changing layout alone never writes a reading checkpoint.

**Validation:** code and regression test sources committed; static
inspection only. Flutter analyzer, widget/integration execution and
native Windows/Android acceptance were not run. No Windows builds or
GitHub Actions were triggered; PR #1 remains draft.
