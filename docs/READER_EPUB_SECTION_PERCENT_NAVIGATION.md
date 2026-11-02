# EPUB: navigate within the current source section

Implemented on `feature/m0-flutter-foundation` (draft PR #1),
2026-11-02.

## New reader experience

The regular **Reader tools** menu and mobile **Quick navigation**
now expose **Go to position in this section** when the visible EPUB
section has a uniquely resolvable, nonempty original-text interval.
Choose a whole percentage using the same 0/25/50/75/100 presets and
validated number field as whole-book navigation.

The compact EPUB narration toolbar also displays a small source
percentage beside the current directory section name when measurable.
The existing global source progress bar remains a separate percentage
for the whole book. Neither is a page count, elapsed duration or
predicted TTS time.

### Source boundaries

- With an authorial NAV/NCX table of contents, each entry's range
  begins at its resolved original UTF-16 offset and ends at the next
  **strictly higher** source offset. Because editorial TOC order may
  differ from reading order, all entries are scanned for the nearest
  higher boundary. The last entry extends to the document's end.
- Without authorial contents, exact OPF spine `start` and `end`
  ranges are used.
- If source offsets are invalid or multiple TOC/spine entries have
  the same start, the section-relative percentage is unavailable.
  This avoids assigning a false fraction or landing in a distinct
  silent illustrated item with the same source coordinate.
- **100%** resolves to the final original source position *within*
  the selected section, not the start of the following section.
  The ordinary global **Go to book position** still permits true EOF.

### Speech and persistent checkpoint safety

Opening/changing/canceling the chapter-percent dialog never starts
TTS, seeks or saves a bookmark. On explicit **Go**, the resulting
original-source position passes through the existing latest-wins
`_jumpToSourceProgress` / EPUB exact navigation and native Stop
barrier. The session's Return-to-position checkpoint is added only
after the destination commits.

A dialog result is ignored if the player or document has changed,
the reader is loading, or the active directory section has changed
while the dialog was open. A manual scroll that changes the visual
section during playback therefore cannot accidentally apply the
percentage to a different chapter. The compact section indicator
uses the existing visual progress notifier, not an independent
audio position.

## Changed files and regression coverage

- `lib/features/reader/reader_section_range.dart`: pure,
  bounded source range resolver and percent conversion.
- `lib/features/reader/reader_go_to_progress_dialog.dart`:
  configurable text for the existing validated percentage chooser.
- `lib/features/reader/reader_tool_menu_options.dart`: explicit
  availability for EPUB section Go; excluded on TXT, PDF and
  unresolvable sections.
- `lib/features/reader/reader_screen.dart`: visual position
  ownership, modal revalidation and source-exact navigation.
- `lib/features/reader/reader_compact_controls.dart`: independent
  section progress label when boundaries are known.

Tests authored include valid, out-of-editorial-order, duplicate and
out-of-bounds publisher TOCs; silent/zero-length and duplicate OPF
chapters; 100% boundary rules; option gating; modal
Cancel-versus-confirm behavior; and compact transport display.

## Manual acceptance

1. Open a large EPUB with an authorial TOC. Scroll into a section,
   open Quick navigation and select **Go to position in this section**.
   Confirm 25%/75% land inside that section, not at global 25%/75%.
2. Confirm 100% never enters the *next* section, while the global
   book-percentage dialog can reach real source EOF.
3. Open the section dialog, cancel and verify both TTS state and
   persisted offset remain unchanged. Confirm a jump and verify
   Return-to-position returns to the actual pre-jump cursor.
4. Browse elsewhere while speech continues; check the section label
   and local percentage match the visible chapter rather than the
   narration cursor.
5. Test an EPUB with a reordered TOC, nested headings, duplicate
   authorial anchor offsets, cover illustrations, silent trailing
   spine items, and 320px / large-font mobile layouts. No invented
   local percentage should appear on ambiguous sections.
6. While a dialog is open, move narration to another section or
   reload the book: the earlier result must be ignored.

**Validation status:** code and regression tests are committed
and source-checked but Flutter analyzer/widget tests and native
Windows/Android acceptance have not been executed. No Windows
builds or GitHub Actions were launched. PR #1 remains draft.
