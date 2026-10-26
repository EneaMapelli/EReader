# M2 — EPUB figure captions and table previews in source order

Date: 2026-10-26. Branch `feature/m0-flutter-foundation`, draft PR #1.

## Why

The reader already interleaved safe local EPUB pictures between source text.
However, table previews were appended after every paragraph, regardless of
the XHTML `<table>` position, and the original semantic `<figcaption>`
was rendered indistinguishably from ordinary prose.

These changes improve vertical source-order readability without
reconstructing arbitrary HTML/CSS, changing the text extraction or
producing duplicate TTS requests.

## Table previews

- The original table cell text **remains selectable, source-aligned and
  spoken once**. A structured preview is OPTIONAL: it stays collapsed
  unless the user taps its `ExpansionTile`. It never enters the TTS
  input or search index.
- The preview is attached to the text block containing the **last source
  character** of the verified table, not necessarily the block where
  the table started. This preserves position for long tables split by
  paragraph-level virtual scrolling.
- `epubVisualFlow` emits table previews as source-order visual events
  anchored at `table.end`, interleaved with images and styled text.
  Equal-offset images retain source order. Tied table events follow
  images. Text fragments are divided **for painting only**; original
  UTF-16 source, voice, links, offsets and bookmarks remain unchanged.
- Existing bounded table extraction limits continue to apply
  (at most 120 tables, up to 40 rows and 12 cells per row, cell text
  capped to 300 source characters in the preview).
- The table preview is NOT a faithful browser-like layout. It does not
  reconstruct `rowspan`, `colspan`, nested tables, CSS widths,
  embedded image cells or author-defined borders.

## Figure captions

- `extractEpubStructure` records a bounded, verified source interval
  for each semantic XHTML `<figcaption>`. It uses exactly the same
  normalization and UTF-16 projection as already narrated source text.
  Mismatched extracted text yields no invented annotation.
- The interval travels through `EpubTextResult.figureCaptions` and
  `DocumentContent.epubFigureCaptions` into both the eager and lazy
  reader layouts, including the EPUB worker/isolate adapter.
- Source runs touching an actual caption are split **only visually** and
  marked `figureCaption`. The reader paints them italic and slightly
  smaller. The caption's ORIGINAL letters, TTS segments, speaker voice,
  link/footnote targets, search result and stored source anchor stay
  exactly the same, even if a picture falls mid-caption.
- Overlapping, empty, out-of-order or out-of-source caption intervals
  fail layout validation instead of guessing a caption boundary.
- This is visual emphasis, not a separate TTS voice or a second
  synthetic caption reading. Image `alt` remains visual/accessibility
  metadata only.

## Regression test cases authored (NOT run)

- `test/data/epub_embedded_content_test.dart`: exact caption projection
  and rejection when flattened XHTML source does not match.
- `test/data/epub_text_extractor_test.dart`: a ZIP-imported XHTML
  `<figcaption>` survives to `DocumentContent`, appears exactly once
  in extracted speech source, and is not synthesized separately.
- `test/features/reader/epub_image_flow_test.dart`:
  table preview inserted at source end between two spoken text fragments,
  original text/voice/link retained; styled caption span equality; eager/
  progressive parity; overlapping caption rejection and a Flutter widget
  test of a collapsed/expanded table in the middle of a paragraph.

## Manual Windows/Android acceptance

1. Run `tool/run-all-tests.ps1` locally. Inspect targeted EPUB
   extractor, embedded-content, visual flow and reader widget results.
2. Open a real EPUB with `<figure><img .../><figcaption>...</figcaption>`.
   Verify image then caption position, appropriate caption styling,
   accessibility labels and identical TTS narration.
3. Open EPUBs with short/long `<table>` elements between paragraphs
   or between images. Verify only one optional preview appears at the
   table end, can be expanded horizontally, and does not overwrite the
   original source/selection.
4. Navigate and save bookmarks before/after tables and captions;
   reopen the book and verify narrator/character voice continuity.
5. Test malformed EPUB source maps, Unicode emoji, footnotes and
   chapter-boundary tables; check native memory/rendering on Android
   and Windows. Complex rowspan/colspan are explicitly unsupported.
6. Compare progressive and eager test results, but do not infer release
   quality or frame timings from these unexecuted source-only checks.

**Verification status:** code, documentation and tests committed.
Flutter analyzer, formatter, test suite, native builds and real-device
audio/visual checks have **not** been executed in this session.
Qualitative milestone estimate M2 ~70%; total roadmap ~55%.
