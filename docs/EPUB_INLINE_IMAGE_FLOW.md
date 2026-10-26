# EPUB inline image and text flow (M2)

**2026-10-26 — implemented on** `feature/m0-flutter-foundation` (draft PR #1).
Code and test fixtures committed. Flutter/Dart analyzer, unit/widget tests and
native Windows/Android rendering have **not been run** in this editing session.

## Motivation

An EPUB illustration inside a normal text-bearing XHTML chapter previously
appeared **after the entire rendered paragraph**, even if its original
`<img>` occurred before a caption or between two fragments of a sentence.
Image-only OPF items were addressed separately in
[EPUB_ILLUSTRATED_SPINE.md](EPUB_ILLUSTRATED_SPINE.md).

## Implemented behavior

- `epubVisualFlow(EpubVisualBlock)` builds a bounded presentation-only
  sequence of text groups and embedded local images, sorted by canonical
  source UTF-16 position. Two images with the **same** offset maintain their
  original extraction order.
- When an image lies **inside** an existing text run, its run is split only
  for painting. Both visual subruns preserve the same speech segment index,
  bold/italic/heading style, search source offsets, internal-link destination,
  note/footnote marker, and optional auxiliary note key. The original
  `SpeechSegment`, source string, character voice and SQLite anchor are not
  changed, regenerated or duplicated.
- `EpubParagraphTile` renders those mixed text/image groups in source order,
  rather than appending every image to the bottom of its paragraph. It keeps
  local `Image.memory` decoding, bounded resolution and accessibility alt
  text. An image-only OPF tile still has zero `EpubVisualRun` objects.
- The lazy progressive layout and eager/reference EPUB layout now both
  constrain each picture to the range of blocks belonging to its **original
  OPF spine item**. An illustration at a chapter's text end cannot migrate
  to another spine or accidentally attach to a same-offset illustrated cover.
  The eager renderer now also retains visual-only OPF blocks and its
  OPF-to-block navigation index for parity with progressive rendering.
- The image source projection normally comes from validated XHTML DOM
  boundaries. If stale or synthetic metadata places it inside an UTF-16
  surrogate pair, visual slicing moves the image after the entire Unicode
  scalar rather than producing malformed text spans.
- The existing ZIP import continues to reject untrusted remote resources,
  SVG, unsupported MIME types, oversized/malformed raster data and unsafe
  raster dimensions, and enforces the same 32-image-reference/12 MB unique
  image-data limits. No new network request or TTS quota is introduced.

### What is not supported

This is **source-order vertical interleaving** inside a paragraph, not a
full EPUB3 XHTML/CSS compositor. Floats, absolute positioning, background
images, responsive CSS columns, SVG, arbitrary HTML and exact original
figure geometry are not reflowed. Tables still render as bounded previews
after the paragraph; image placement inside table cells is not reconstructed.
Image-only books with no readable text anywhere remain outside the
supported text-oriented EPUB reader.

## Regression coverage authored (NOT executed)

`test/features/reader/epub_image_flow_test.dart` exercises:

1. An image between text fragments covered by a **single** TTS segment,
   with bold, italic, clickable-footnote metadata preserved on both sides
2. Pictures before text, after text, and two at the same offset with
   stable ordering
3. No-image paragraph unchanged and fully image-only block without TTS
4. UTF-16 emoji positions and malformed image offsets inside surrogate
   pairs, keeping text and source intact
5. Two physical OPF chapters, with pictures in the body, at the end of
   the first and at the beginning of the second: identical ownership and
   visual flow between eager and lazy renderers
6. A Flutter widget fixture verifying the original *before → image →
   after* visual sequence

## Manual acceptance (Windows and Android)

1. Run `tool/run-all-tests.ps1` locally, reviewing
   `epub_image_flow_test.dart`, `epub_illustrated_spine_test.dart`,
   extractor tests and existing EPUB rendering regressions.
2. Open a real EPUB with a paragraph containing an illustration between
   two sentences. Inspect the order, selectable text, link tap targets,
   reader highlighting and voice/cast transitions.
3. Use consecutive image tags, images immediately before/after paragraphs
   and illustrations at OPF chapter boundaries; no image should migrate.
4. Compare the same EPUB with the eager and lazy layout test fixtures;
   verify no new spoken text or provider billing for image alt labels.
5. Test emoji and mixed RTL/accented text around illustrations, chapter
   jumps, saved source anchors and reopen.
6. Exercise repeated open/scroll/close on Android and Windows; capture
   image decode errors, frame-time samples and memory usage. No FPS,
   latency or peak memory improvement is claimed without actual samples.

**Roadmap:** M2 qualitative estimate remains about 70%; M0–M6 overall
approximately 55%, pending Flutter analyzer and on-device validation.
