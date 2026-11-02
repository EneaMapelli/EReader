# Compact reader: visible EPUB chapter status

Implemented on `feature/m0-flutter-foundation` · 2026-11-02 · draft PR #1.

## User-facing behavior

When reading an EPUB with publisher contents (NAV/NCX) or a fallback OPF
spine, the compact narration panel displays the current section's title
and source-directory position, e.g. `The Hidden Valley (5/18)`.

- The section row appears above the spoken-segment controls, so the
  displayed EPUB location and `Segment N of M` are distinguished.
- Tapping the section row opens the **existing searchable chapter
  directory**. This is a visual navigation action only: displaying
  the directory cannot start/pause cloud or offline TTS, seek to a
  segment, or save a bookmark.
- Choosing a directory entry continues to use the original
  latest-wins guarded source-exact navigation pipeline. Source-only
  and silent illustration chapters keep their OPF identity and are
  never fabricated as an extra speech segment.
- When the narrator continues while the user manually scrolls,
  the displayed section follows the **visible reader viewport**,
  not the narrator's unrelated audio position. While following
  narration normally, the section advances with spoken progress.
- The displayed title is limited to one line with ellipsis; section
  counts remain available, including long tables of contents.
  On 320 logical-pixel phones with 200% text scaling the row may
  coexist with the original wrapped transport controls.
- TXT and PDF do not gain a fabricated EPUB chapter indication.
  When an EPUB has no current valid directory index, the row stays
  hidden. The existing compact Quick navigation menu and full
  Reader tools menu remain unchanged.

## Implementation

- `lib/features/reader/reader_compact_controls.dart`: optional
  `sectionLabel`, `sectionIndex`, `sectionCount` and
  `onOpenSections` properties. The widget does not own any
  reader source or speech state.
- `lib/features/reader/reader_screen.dart`: the compact panel
  observes `_visualProgressTick`, which already updates when
  the viewport moves without playback changes. EPUB directory data
  comes from `_currentDirectoryIndex` and the existing preferred
  authorial TOC/fallback chapter list. Clicking delegates to
  `_openChapterDirectory`; the existing source-selection gate and
  stale book/document checks handle explicit jumps.

## Regression cases authored

`test/features/reader_compact_controls_test.dart` now exercises:
- A visible section that opens the directory callback exactly once
  without touching narration transport.
- A switch from a spoken section to an illustrated-only section,
  updating the label without starting an action.
- Missing, invalid and non-EPUB section metadata hiding the row.
- Very long chapter titles on 320px at 200% text scaling without
  overflow, while keeping the narration buttons present.

## Manual acceptance checklist

1. Open an EPUB with an authorial TOC; verify titles and (index/total)
   values agree with the searchable directory.
2. Tap the section row and dismiss: speech state and saved offset
   remain unchanged. Select a destination: existing EPUB exact
   navigation and persisted anchors must still work.
3. Start narration; manually scroll elsewhere and verify the
   chapter label follows the visual location while the speech
   segment counter continues at its own location.
4. Try silent cover and trailing illustrated OPF spines, duplicated
   source offsets, and a book without a publisher TOC.
5. Verify a very long translated chapter title in a 320px viewport
   with 200–300% accessibility text scaling, in portrait and landscape.
6. Confirm TXT/PDF readers do not show a misleading chapter indicator
   and that the advanced controls still navigate chapters normally.

**Validation status:** committed and source-inspected, not executed
with the Flutter analyzer or widget tests. Native Windows/Android
acceptance remains pending; no GitHub Actions or Windows builds were
triggered. Keep PR #1 in draft until runtime validation.
