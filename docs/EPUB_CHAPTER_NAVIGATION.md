# EPUB reading-order chapter navigation (M1)

Increment: 2026-10-23, `feature/m0-flutter-foundation`.
**Source authored; Flutter analyzer, automated tests and Android/Windows
builds intentionally deferred.**

## Shipped in source

- The EPUB2/EPUB3 OPF `spine` remains the **authoritative reading order**.
  Each extracted readable XHTML item now has a *display-only* chapter title:
  the first available highest-level visible `h1`/`h2`/`h3` from
  its `body`, stripped of metadata, scripts and `nav`, with whitespace
  normalized and a 120-character title limit. Untitled items receive
  `Chapter N`. XHTML text and UTF-16 offsets are *never* changed by a
  display heading.
- A chapter directory (list icon in the Reader app bar) shows readable
  spine items and highlights the current chapter. A selected item is
  mapped to the first actual TTS segment inside that item's source range,
  persisted using its existing `ReadingAnchor(kind: epubSpine)`.
  During manual scrolling the chapter indicator follows the visible text;
  during narration it follows the spoken segment. Standalone headings already
  present verbatim in the text receive larger typography and a screen-reader
  heading semantic; no duplicate chapter title is inserted into the book.
  The navigation bar also offers **previous/next chapter** and displays
  the current chapter title and index.
- Selecting a chapter pauses existing playback first. It does not
  automatically call Play, request new OpenAI synthesis, obtain new cloud
  permission, or change the saved PDF visual-page bookmark. An existing
  in-flight cloud operation may still complete based on the player's
  earlier authorized session, and voice casting remains source-bound.
- EPUB speech segmentation now starts fresh at each spine boundary, while
  the global source offsets remain unchanged. Quoted-fragment coalescing
  receives *hard* spine boundaries so it cannot undo that division when
  a quotation spans two XHTML files.
- TXT segmentation, PDF modes, reading search, bookmarks, and active
  character casting retain their preexisting behavior. No database
  migration is required.

## Publisher navigation added (2026-10-24)

An optional editorial EPUB3 NAV / EPUB2 NCX directory is now parsed and
displayed with nesting where available. The index's previous/next controls
follow publisher entries; the spine-chapter directory is retained as a
fallback. See [EPUB NAV/NCX and Footnotes](EPUB_NAV_NCX_FOOTNOTES.md).
The original source offsets, speech order and SQLite anchors remain
based on OPF spine, not the publisher's separate TOC document.

## Anchors and constraints

- A spine element is **not necessarily a semantic chapter**. Some EPUBs
  put many chapters in one XHTML document, split one chapter into
  several files, or use nested NAV/NCX entries. The first navigation
  increment deliberately uses readable spine items and their headings;
  it does **not** claim full EPUB3 NAV / EPUB2 NCX table-of-contents
  fidelity, nested TOC, footnote navigation, or EPUB CFI support.
- The visual EPUB view is still a **text-only segment-based renderer**,
  not a full-fidelity XHTML/CSS renderer. Images, tables, embedded fonts,
  true paragraph indentation, floats, accessibility semantics for
  XHTML headings and styles remain incomplete.
- EPUB DRM bypass and remote linked resources are out of scope.
  Archive path normalization, decompression budgets and script stripping
  continue to use the existing bounded extractor.

## Tests written but not executed

- `test/features/epub_chapter_navigation_test.dart`: six tests for
  source-exact UTF-16 positioning (including emoji), per-spine narration
  boundaries, quote coalescing restrictions, empty spine items, fallback
  labels, source-exact semantic headings, malformed ranges and TXT compatibility.
- `test/data/epub_text_extractor_test.dart`: two new tests for body-only
  heading extraction and display-title truncation without altering
  original text or offsets.

At integration time, verify with real EPUB2 and EPUB3 books: nested
navigation documents, language-specific chapter headings, footnotes,
dialogue spanning files, books with one large XHTML chapter, novels with
illustrations, large files, and progress recovery after force-stop.
Check Android touch and Windows keyboard/focus behavior as well as
media-session controls, pause before chapter jumping, and consented
cloud narration.

Related references: [Development Plan](DEVELOPMENT_PLAN.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
