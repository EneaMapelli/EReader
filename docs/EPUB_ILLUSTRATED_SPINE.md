# EPUB illustrated XHTML spine blocks — M2

_Date: 2026-10-26. Implemented in feature/m0-flutter-foundation, PR #1.
Source and tests committed; no Flutter analyzer, automated run or native
Windows/Android visual playback executed in this GitHub editing session._

## Supported behavior

An EPUB may contain one or several OPF spine XHTML items that contribute no
text but embed a cover, map, picture or figure. Their source UTF-16 length is
ZERO and is NEVER padded with an invented title, alt text or empty TTS
segment. The existing text-only reader must nonetheless offer a visual
navigation destination for those resources.

- `EpubTextExtractor` retains zero-length OPF entries; now also calls
  `extractEpubStructure(html, '')` to discover images from image-only
  XHTML resources. These use the same manifest-local resource lookup, MIME
  and PNG/JPEG header/dimension validation, 2 MB-per-image cap, global
  image-reference count and 12 MB unique-image-byte budget. External
  resources and unsupported media cannot load into a Flutter image widget.
- `EpubEmbeddedImage.spineIdref` carries immutable originating OPF
  identity, separately from source offset. Two consecutive illustrated
  sections may share offset 0 or the same chapter boundary but MUST receive
  different pictures and separate blocks.
- `verifyEpubSourceIntegrity` now permits zero-length OPF items ONLY at
  the previous narrated item's end (or 0 before the first). Each nonempty
  spine must still cover canonical text in order, separated by exactly two
  newlines. Duplicate OPF IDs, overlap, source holes, altered separators
  and invalid Unicode boundaries still fail import.
- The existing `ProgressiveEpubBlocks` LRU materializes one lightweight,
  illustration-only visual block per zero-length OPF entry, without
  allocating fake `EpubVisualRun` text. It associates verified local
  images by OPF idref, not by ambiguous UTF-16 offsets, and renders a
  source-independent section title plus image; a no-image case shows a
  factual unavailable-text placeholder. Text paragraphs still load lazily.
- `EpubVisualLayout.blockForSpine(idref, offset)` provides exact
  programmatic visual navigation. A reverse block-to-idref map keeps
  manually scrolled images distinct. `EpubVisualSourceCheckpoint` can
  pin the exact virtualized block index while the list settles, even if
  nearby OPF resources share a single source offset.
- Virtualized Flutter tiles now use a composite `(sourceOffset,
  visualBlockIndex)` key, not the source offset alone. This prevents a
  pair of illustrated sections at identical UTF-16 positions from sharing
  a Flutter element's cached image/gesture/semantics state.
- ReaderScreen saves visual-only progress as a genuine `ReadingAnchor`
  with `AnchorKind.epubSpine`, original OPF `sourceId`, and
  `localOffset=0`. A later open resolves that source ID to the correct
  illustrated block rather than assuming the following text block.
  Ordinary sentence, paragraph, link and spoken-note checkpoints remain
  source-exact and unchanged.
- The narrated cursor is independent of pictures. A trailing
  illustrated item resolves to speech EOF; pressing Play there is an
  explicit restart rather than silently speaking the preceding clip.

## Hard boundaries and limitations

- A book with **no readable text anywhere** is still rejected by the
  current *text-oriented EPUB extractor*, even when it contains pictures.
  A complete graphic novel / all-image EPUB reading mode is a different
  milestone and is NOT claimed here.
- Only embedded, accepted local PNG/JPEG are shown; complex CSS,
  remote images, SVG, scripts, DRM, reflow composition, and original
  precise image coordinates are not supported. The illustration appears
  in its own section rather than reconstructing author-defined XHTML
  layout. Image.decode/GPU memory limits still require device tests.
- A title or alt label is display/accessible semantics only and never
  billed, synthesized, saved as book source text, or included in
  character/speaker attribution.
- OPF source IDs must remain stable for precise illustrated bookmarks;
  a later replaced ebook can invalidate them, consistent with EPUB
  context-based reading anchors.

## Regression tests authored (not run)

- `test/data/epub_anchor_integrity_test.dart`: leading, middle,
  consecutive and trailing zero-length spine entries; rejects corrupt
  positions, overlaps, duplicate IDs and fabricated text.
- `test/data/epub_text_extractor_test.dart`: real ZIP fixture with
  image-only XHTML and local manifest-declared PNG; validates bytes,
  original OPF idref, unchanged spoken text and existing empty range
  compatibility.
- `test/features/reader/epub_illustrated_spine_test.dart`: two cover
  items sharing offset 0, a narrated chapter, and illustrated trailing
  appendix; each picture belongs to its own virtual block, exact
  structural bookmark can restore the second cover, trailing visual
  scroll selects speech EOF, target pin is distinct, and Flutter renders
  a local image without a text TTS run.

## Windows and Android manual QA

1. Run `tool/run-all-tests.ps1` locally. Review changed extractor,
   integrity, EPUB illustrated-spine and source-navigation suites.
2. Import an EPUB with a cover.xhtml containing only an embedded local
   PNG or JPEG, followed by a text chapter. Confirm the cover is visible
   as an independent destination and no cover title/alt is spoken.
3. Import a mixed EPUB with TWO consecutive image-only OPF items,
   followed by text and a final image-only appendix. Jump between the
   two covers, scroll away and back, close/reopen from the second cover
   and inspect persisted OPF anchors.
4. Press Play from a middle illustrated item: only a subsequent real
   speech segment may be synthesized. From the illustrated appendix,
   Play must deliberately restart, not replay the last sentence.
5. Test malformed raster headers, oversized dimensions, missing manifest
   entries, remote tracker URLs and a totally image-only EPUB. Verify
   safe omissions/error messaging and no network fetch.
6. Stress a long EPUB with rich paragraphs and images: monitor scrolling,
   lazy block-cache size, Android memory/decoder behavior, Windows
   temporary file cleanup and audio focus after quick page changes.

**Status:** code/test/documentation ready for manual validation.
No analyzer/test results or performance improvements are asserted here.
M2 qualitative estimate ~70%; full roadmap ~55%.
