# EPUB original semantic typography — safe inline styling

Increment: 2026-10-24. Branch: `feature/m0-flutter-foundation`.
Status: **source committed; Flutter analyzer, tests and native builds NOT run**.

## Behavior

EPUB2/EPUB3 XHTML source now contributes *display-only* semantic marks:
- `<b>` / `<strong>` → bold;
- `<i>` / `<em>` / `<cite>` / `<dfn>` → italic;
- `<h1>` through `<h6>` → levelled heading typography and semantic
  heading accessibility when a visual block contains a complete heading.

Nested and adjacent markup can produce different font attributes within
**one speech segment**. The paragraph renderer splits the visual
`TextSpan` runs at both the TTS boundaries and the original semantic
style boundaries. Speech still uses the unchanged extracted source text;
cloud consent, budget reservations, voice casting, bookmarks, search,
spine offsets and recovery markers do not receive XHTML style metadata.

## Offset safety: no substring guessing

The existing EPUB extractor preprocesses `<br>` and block closing tags
to line breaks, removes unsafe/nonreading nodes, strips spaces immediately
before newlines, then trims the result. A naive `indexOf("italic text")`
is not enough: duplicated words or trimming can point to the wrong
location. The new `extractEpubInlineStyles`:

1. Parses the **same preprocessed** XHTML body and removes `script`,
   `style`, `nav`, `svg`, `head` and `noscript` nodes.
2. Traverses actual text nodes with a bounded nesting depth (256) and
   tags each raw span with inherited bold/italic/heading semantics.
3. Projects original UTF-16 offsets through exactly the extractor's
   space-before-newline removal and leading/trailing trim.
4. **Compares the entire normalized result** to the authoritative
   `EpubTextExtractor` output. On mismatch, returns *no* styling for
   that spine item, never a guessed style location.
5. Converts verified positions to global offsets in the OPF reading order.
   Invalid, overlapping or out-of-bounds spans fail validation before
   being displayed.

The extractor permits at most 100,000 style runs in a single item and
100,000 across the book. If the book-level limit is exceeded, its entire
style metadata falls back to empty; source text remains available.

No DB migration or persisted style records are introduced. Styling is
deterministically recomputed from the imported local EPUB.

## Rendering

`EpubVisualRun` now includes optional `bold`, `italic` and
`headingLevel`. The visual run builder intersects these with the
original speech segment IDs and maintains exact text concatenation.
`EpubParagraphTile` displays the corresponding font style while
preserving its per-segment selection gesture and audio highlight.
Heading tags appearing after the first chapter heading can also receive
heading typography, not just the first spine title.

The system/sepia/night reader palettes are unchanged, and the original
readable-width/line-spacing rules still apply.

## Authored tests, not executed

- `test/data/epub_text_extractor_test.dart`: 4 new cases for nested
  emphasis, original headings, repeated words, ignored unsafe nodes
  and normalization through removed whitespace.
- `test/data/epub_inline_style_test.dart`: 4 tests for a mismatched
  source, UTF-16 emoji offsets, nested strong+emphasis and ignored
  nonreading markup.
- `test/features/epub_visual_layout_test.dart`: 3 new cases for
  intersections of text style and spoken spans, Unicode heading blocks,
  and invalid/overlapping style bounds.
- `test/features/epub_paragraph_tile_test.dart`: 2 new widget tests for
  emphasis during TTS highlighting and accessible semantic headings.

No `flutter analyze`, `flutter test` or Android/Windows runtime
verification has been performed as agreed.

## Deliberate limitations

This is **not** arbitrary author CSS: inline `style=`, external CSS,
custom font embedding, layout floats, margins, tables, linked images,
hyperlinks, footnotes, ruby pronunciation marks, page-break rules,
SVG/math and full EPUB3 navigation/CFI are not yet supported.

Inline markup is only treated as typography; no scripts, network
requests, third-party resources or active document code are executed.

Next integration gate: real EPUB2/3 corpus with repetitive paragraphs,
nested quotations, emoji, whitespace-heavy markup, deeply nested
elements, multiple headings within a single spine item and mismatched
navigation structure. Verify selectable text, source anchors, TTS
speaker/voice continuity and screen readers on Android and Windows.

Related: [EPUB Paragraph Renderer](EPUB_PARAGRAPH_RENDERER.md),
[EPUB Chapter Navigation](EPUB_CHAPTER_NAVIGATION.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
