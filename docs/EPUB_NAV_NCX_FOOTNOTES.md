# EPUB3 NAV, EPUB2 NCX, footnotes and return navigation

Increment: 2026-10-24 on `feature/m0-flutter-foundation`.

**Source and regression tests authored; no Flutter analyzer, Flutter tests,
Android build, Windows build or runtime verification executed.**

## Editorial table of contents

- EPUB3 OPF `manifest item properties="nav"` identifies a separate
  XHTML Navigation Document. EReader reads the first
  `<nav epub:type="toc">` or `<nav role="doc-toc">` and walks its
  ordered/unordered lists recursively, keeping the nesting depth and
  original editorial order.
- EPUB2 NCX is discovered through `spine toc="ncx-id"` and the
  `application/x-dtbncx+xml` manifest item. `navMap/navPoint`
  nesting, `navLabel` and `content src` are converted to the same
  model. If the EPUB3 NAV is absent or has no valid readable entries,
  an available NCX is tried.
- Both formats resolve **only in-book targets** that map to a readable
  OPF spine item and, when specified, a valid preverified XHTML
  fragment. External, `javascript:`, `file:`, absolute, traversing,
  absent, or ambiguous targets are excluded. DTD/entities in NCX are
  rejected. The EPUB2/3 parsing budget is 2 MiB per navigation file,
  maximum 2,000 entries and nesting at most 20 levels.
- If no valid author navigation exists, the existing **spine item
  directory** with headings is still available. Crucially, the
  editorial table of contents **does not change** the authoritative
  OPF spine order used for extracted text, TTS, character attribution,
  progress anchors or crash checkpoints.
- The reader's directory button shows editorial title hierarchy and
  indents child entries; the previous/next section controls and
  compact current-section label also follow the editorial directory
  when it exists. Active item selection matches the closest preceding
  original source position, regardless of NAV presentation order.

## Footnote and link-return behavior

- EPUB3 `epub:type="noteref"` and ARIA `role="doc-noteref"`
  are recognized from source-verified body links. Footnote markers
  receive accessible screen-reader labels without changing the
  visible or spoken text.
- Following any verified in-book link, including a note reference,
  pauses the TTS player, jumps to the destination's existing EPUB
  source anchor and **does not automatically synthesize or Play**.
- A **Return from note or internal link** toolbar action appears
  when an in-book link has been followed. Return positions use
  original UTF-16 offsets in a 20-entry session-only stack.
  A fragment inside a longer spoken sentence saves its **exact verified
  source position**, even though the audio engine seeks to the containing
  segment. Segment lookup uses binary search for large books.
  Nested link visits may be unwound in reverse order. A return
  entry is removed **only after a successful navigation**, preventing
  native Stop errors or failed seeks from losing the back target.
- Editorial directory jumps and ordinary text taps do not
  contaminate the note/link return stack. Rebuilding a reader
  session clears that temporary stack; there is no database
  migration, cross-book URL history or web navigation.

## Files

- `lib/data/epub_navigation.dart`: safe EPUB3 NAV and EPUB2 NCX
  parsers, immutable navigation entries and current-section lookup.
- `lib/data/epub_text_extractor.dart`: optional navigation manifest
  discovery and strict mapping to verified `EpubSpineRange` offsets.
- `lib/data/epub_structural_markup.dart`,
  `lib/data/epub_embedded_content.dart` and
  `lib/features/reader/epub_visual_layout.dart`: source-safe
  footnote link semantics, retaining spoken segment identity.
- `lib/data/book_decoder.dart`: carries TOC metadata independently
  of the existing original book text.
- `lib/features/reader/epub_link_history.dart`: bounded return stack.
- `lib/features/reader/reader_screen.dart`: authorial hierarchical
  TOC UI, editorial previous/next and fail-closed no-autoplay link
  and return navigation.
- `lib/features/reader/epub_paragraph_tile.dart`: accessible note
  reference semantics in the same clickable text span.

## Authored tests (not executed)

- `test/data/epub_navigation_test.dart`: EPUB3 nested NAV, EPUB2
  hierarchical NCX, fallback order, missing TOC, unsafe links, spine
  anchoring, fragment/path-only resolution, invalid XML and unchanged
  source text; plus editorial active item matching.
- `test/features/epub_link_history_test.dart`: nested returns,
  capacity limits, invalid/no-op entries and pop-after-success policy.
- `test/data/epub_embedded_content_test.dart`: EPUB3 and ARIA
  footnote marker source ranges.
- `test/features/epub_visual_layout_test.dart`: note-reference
  semantics and unchanged TTS run/offset mapping.

## Known limitations

This increment covers *usable hierarchical NAV/NCX and in-book
footnote navigation*, not every EPUB spec feature:

- Footnotes stored in XHTML **not included in the readable spine**,
  image-only note documents, scripted pop-ups and multi-document
  remote references are intentionally not rendered or opened.
- Recognized semantic note bodies now support a **read-only local
  preview popup**. An explicit **Open in book** command keeps the original
  full-document navigation and return button. Rich XHTML/CSS note rendering,
  backlink reconstruction from publisher markup and persistent browsing
  history across restarts remain unavailable. See
  [EPUB Footnote Preview](EPUB_FOOTNOTE_PREVIEW.md).
- Editorial landmarks, page lists, multiple alternative navigation
  collections, `navPoint` playOrder semantics, RTL tree indentation,
  very deep hierarchies beyond 20 levels, duplicate-target editorial
  nuances and EPUB CFI locations are not yet fully supported.
- Real Android/Windows UX, screen-reader accessibility, 10,000-item
  EPUB scalability and correctness on diverse EPUB2/EPUB3 books have
  not been validated.

Next practical step: targeted QA on a representative EPUB corpus,
then richer note semantics, better accessibility and release integration,
keeping the agreed compilation/test gate.

Related: [EPUB Embedded Content](EPUB_EMBEDDED_CONTENT.md),
[EPUB Chapter Navigation](EPUB_CHAPTER_NAVIGATION.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
