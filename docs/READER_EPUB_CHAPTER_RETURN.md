# Return to the exact reading position before an EPUB chapter switch

Implemented on `feature/m0-flutter-foundation` · 2026-11-03 · draft PR #1.

## Update · 2026-11-03: bounded chapter visit history

The original one-shot chapter return described below is now backed by
a **20-entry session-only back stack**, rather than a single
`ReaderProgressReturnPoint`. The one-tap **Return before chapter change**
continues to restore the most recent source location, but preserves any
older chapter visits. The new **Recent chapter positions** sheet becomes
available after two or more chapter switches and lets readers select
an older saved location. See
[READER_CHAPTER_VISIT_HISTORY.md](READER_CHAPTER_VISIT_HISTORY.md)
for the current implementation, source identity and revision-safety
details. The older references to `_sectionReturn` below describe
the original milestone and are superseded by `_chapterHistory`.

## Reader workflow

Selecting a different EPUB section now remembers the **exact source location
you were reading immediately before the switch**. After the switch commits,
the **Return before chapter change** command appears under:

- Reader tools → Navigate & find.
- Quick navigation (the compass shortcut in the compact reader AppBar).

The return action navigates back to the saved source position and then
removes itself. It is a **one-shot session affordance**, not a persistent
reading-history log. Changing chapters again establishes a fresh origin.
A canceled index sheet, a failed chapter seek, an invalid target or a
no-op switch never overwrites the earlier return point.

The feature applies consistently to chapter arrows in the compact
reader, chapter arrows in immersive focus mode, advanced chapter
navigation, keyboard chapter shortcuts, first/last section actions,
and explicit selection from the searchable publisher NAV/NCX or OPF
fallback chapter directory.

## Source accuracy and independent history

An EPUB chapter source destination is still selected exclusively
through the existing reader source-selection system:

1. Before requesting the move, capture the current **visual source offset**
   (or the narrated source position when speech owns follow), and the
   optional silent OPF `spineIdref` that disambiguates equal offsets.
2. Route the chapter target through `_navigateToSourceOffset` for the
   author-supplied directory or `_jumpToChapterIndex` for OPF fallback.
   Both eventually use `_select`, the native stop/seek arbitration,
   latest-intent selection gate and persistent SQLite reading anchor.
3. Only the `_select(onCommitted: ...)` callback, after a winning,
   durable checkpoint, may record the chapter origin in the separate
   `_sectionReturn` instance of `ReaderProgressReturnPoint`.
4. An explicit Return invokes the existing original-source Go pathway
   with the preserved `spineIdref`, then consumes history only in its
   winning commit callback and only if the same revision remains active.

This matters for an EPUB illustrated cover and ordinary text that
share source offset zero. Returning to the cover must use its original
OPF identity, not jump to the first spoken paragraph.

**Three types of navigation return remain independent:**

- Return before chapter change — newest successful chapter selection.
- Return to position before jump — newest successful percentage Go.
- Return from internal link — existing bounded EPUB note/link stack.

Returning from a chapter change does **not** consume the percentage
return or the footnote/link return. All histories are in-memory only
and clear on book reload; none is serialized as a separate bookmark.
Normal confirmed navigation still writes the actual current reading
position to SQLite through the existing checkpoint pipeline.

## Regression coverage authored

- `test/features/reader_chapter_return_point_test.dart`: verifies
  separate chapter/percent/link histories, silent visual OPF identity,
  invalid/no-op moves preserving a saved origin, revision protection
  against stale return consumption and clearing on reload.
- `test/features/reader_tool_menu_options_test.dart`: validates menu
  availability for navigable EPUB contents only; confirms Quick
  navigation exposes chapter return independently of percent/link
  return and does not offer it for TXT, PDF, silent-only or nonnavigable
  documents.
- `test/features/reader_focus_epub_integration_test.dart`: uses a
  self-contained EPUB3 ZIP with two publisher TOC entries. One
  scenario moves to 50% of chapter one, changes to chapter two,
  returns to that **exact mid-chapter position** via Quick navigation,
  confirms the chapter return was consumed while the percentage return
  remained available, then uses percentage return to get back to the
  original text position. A second scenario tests selecting a chapter
  from the directory and returning to the original location.

## Manual QA

1. Read partway through an EPUB chapter and tap Next EPUB section.
   Open Quick navigation → Return before chapter change. Confirm
   the previous **exact paragraph** is restored, not just the
   chapter start.
2. Repeat through the publisher directory, first/last section, OPF
   fallback, keyboard shortcuts, focus mode and the advanced controls.
   A canceled sheet must not create a return.
3. Open the section percentage chooser, Go somewhere, switch chapter,
   then return from the chapter switch. Verify the separate percentage
   return still works and neither opens TTS automatically.
4. Test silent illustrated OPF covers and two image-only sections
   sharing a canonical source offset. Returning must restore the
   prior illustrated spine identity.
5. Reload/change book while a seek is pending. An old completion must
   not create or consume a return entry for the new book.
6. Check TXT and PDF do not offer chapter return. Confirm the action
   disappears after one successful return.

**Validation status:** code and tests committed and statically
inspected. Flutter analyzer, widget/integration execution and native
device acceptance have not run. No Windows build or GitHub Actions
triggered. Draft PR #1 remains open for review.
