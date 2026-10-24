# EPUB embedded illustrations, tables and in-book links

Increment: 2026-10-24. Branch: `feature/m0-flutter-foundation`.
**Source authored on GitHub. No Flutter/Dart analyzer, automated tests or
Android/Windows builds have been run** (integration deliberately deferred).

## Scope

The source-aligned, paragraph-based reader now supports three kinds of
**non-executable** EPUB presentation metadata:

1. **Local raster illustrations** referenced by `<img src>`, with
   author-provided alt text. Only ZIP-contained, manifest-declared
   `image/png` and `image/jpeg` items are eligible. They render via
   `Image.memory` next to the nearest reading paragraph; there is no
   `Image.network`, WebView, HTTP fetch, remote URL fallback or
   execution of resource-side scripting.
2. **In-book navigation links** from XHTML `<a href>` to a fragment
   target within a readable spine item, or to the beginning of another
   spine document. The target is resolved during import into the
   document's **global UTF-16 source offset**. No external HTTP(S),
   `javascript:`, file or data URL is opened. Tapping a source link
   takes the existing safe selection route: pause active audio, update
   the source anchor and scroll to the paragraph, **without auto-Play
   or new cloud synthesis**.
3. **Tables** in the readable XHTML body, exposed as optional
   expandable row/column previews. The existing extracted speech text
   stays in the paragraph unchanged, preserving text search, copied
   source, TTS order and saved positions. A table preview is deliberately
   secondary and may repeat visible words from the original text.

These features do **not** attempt full author CSS/layout fidelity.

## Source alignment and rejection policy

`extractEpubStructure` reparses the same preprocessed XHTML body used
by the original extractor, removes `script`, `head`, `style`,
`nav`, `svg`, `noscript` and disallowed reading nodes, then projects
marker positions through the same space-before-newline and leading/
trailing trim rules. It requires **entire-text equality** with the
authoritative extraction before accepting any markers. Unresolvable,
malformed, overlapping or external links are dropped. Link and table
overlays can never shift the speech segment, cast range or EPUB spine
anchor.

Images are resolved relative to the current XHTML spine resource;
archive paths must normalize inside the EPUB root and have an exact
corresponding image manifest declaration. No images are fetched without
that declaration.

### Raster safety budgets

- PNG/JPEG only in this increment (no SVG, GIF, WebP, remote/data URLs).
- At most **32 image placements** per book, at most **2 MiB** per
  compressed resource, and **12 MiB** total for distinct loaded raster
  resources; repeated placements reuse the decoded-byte reference.
- Check magic header and declared width/height, reject dimensions above
  4096 × 4096 or more than 8 million pixels. Decode into a width-bounded
  Flutter image (max visible height 440 logical px, requested cache width
  1200). Failed decoding shows a local placeholder without network
  fallback.
- ZIP entry count, per-entry size and expansion limits inherited from
  the existing EPUB importer still apply.

**These checks are a basic hardening layer, not a guarantee against all
malicious PNG/JPEG payloads or memory exhaustion in a native decoder.**
Real Android and Windows device/resource testing is required.

## Table and chapter limitations

- Up to 120 table previews per book, 40 rows per table, 12 cells per
  row and 300 displayed characters per cell. Varying column counts
  are padded for a stable Flutter `Table`.
- Table layouts, `colspan`/`rowspan`, nested tables, mathematical
  formulas, CSS widths, table captions and semantic header-cell behavior
  remain approximations. A table preview is a *visual aid*, not an
  alternative accessible table representation.
- Images in **image-only** spine XHTML items may not appear yet because
  the current extractor omits spine items without readable text. Image
  placement is tied to the nearest text block, not to an exact CSS
  positioning coordinate. No inline image wrapping, remote fetch or
  EPUB navigation-document artwork is supported.
- EPUB3 SVG, SVG `<image>`, `picture`/`srcset`, CSS
  `background-image`, external fonts, footnote/backlink history,
  true NAV/NCX nesting, EPUB CFI, and complete XHTML tables remain open.

## Code and test coverage

- `lib/data/epub_structural_markup.dart`: HTML body-only image,
  internal anchor and table markers with verified source projection.
- `lib/data/epub_embedded_content.dart`: immutable resource metadata
  plus simple bounded PNG/JPEG header checks.
- `lib/data/epub_text_extractor.dart`: manifest allowlist, safe local
  path/fragment resolution, resource quotas and verified global offsets.
- `lib/data/book_decoder.dart`: presentation metadata threaded
  independently of source/spine offsets.
- `lib/features/reader/epub_visual_layout.dart`: combines visual
  overlay placement and in-book links with exact styled TTS runs.
- `lib/features/reader/epub_paragraph_tile.dart`: controlled local
  images, tappable links, expandable table previews.
- `lib/features/reader/reader_screen.dart`: navigates link destinations
  through the existing no-autoplay paused source-position path.

Authored, **unexecuted** regressions:
- `test/data/epub_embedded_content_test.dart`: extraction and JPEG/PNG
  safety-policy tests for source offsets, hidden content and table rows;
- `test/data/epub_text_extractor_test.dart`: manifest-only local
  resources, cross-spine fragment resolution, table metadata and unsafe
  image path rejection;
- `test/features/epub_visual_layout_test.dart`: source-exact mapping of
  linked speech spans, image/table overlays and invalid link rejection;
- `test/features/epub_paragraph_tile_test.dart`: gesture priority,
  embedded raster UI and ragged-table preview.

**Next:** validate with real EPUB2/3 files and native platform tooling,
then implement accessible semantic tables, image-only spine documents,
caption position fidelity, footnotes/back history and full NAV/NCX.
See [EPUB Inline Formatting](EPUB_INLINE_FORMATTING.md),
[EPUB Paragraph Renderer](EPUB_PARAGRAPH_RENDERER.md) and
[Implementation Status](IMPLEMENTATION_STATUS.md).
