# EPUB paragraph renderer — source-aligned visual reading

Increment: 2026-10-23 on `feature/m0-flutter-foundation`.
Status: **source written and reviewed, automated tests authored but NOT run**.
Flutter/Dart analyzer, compilation and Android/Windows device tests remain
deferred until integration, as agreed.

## Scope of this increment

The earlier EPUB screen displayed one isolated TTS sentence or quoted chunk
per card. It now presents the extracted text in **paragraph-sized,
typographically styled blocks**, lazily built by `ScrollablePositionedList`.
The text remains source-exact and selectable.

- Consecutive text within a paragraph is rendered as a unified paragraph.
  Native line breaks and paragraph breaks come from the existing,
  security-bounded EPUB text extraction; visual blocks never span a
  separate XHTML spine document.
- Very long paragraphs are split into blocks no larger than approximately
  2,400 UTF-16 code units. Splits prefer whitespace and never separate
  surrogate pairs (emoji included). This bounds per-item Flutter layout
  costs without modifying the underlying TTS segments or anchors.
- Each block's **source-aligned text runs** retain the exact original
  character offsets and optional speech segment indices. Spoken runs are
  individually tappable and the current segment is highlighted in-line
  without duplicating or rewriting any book content.
- Reader viewport tracking maps paragraph indices back to the first
  playable segment in that block; manual scroll, chapter navigation,
  restore-from-anchor and automatic audio follow map segment indices
  back to paragraph indices. Automatic scrolling occurs when the audio
  reaches a different visual block, not every spoken sentence in the
  same paragraph.
- Exact standalone EPUB headings are displayed with larger, semibold
  typography and Flutter heading semantics. Chapter directory and
  previous/next navigation from the preceding increment remain intact.
- The visual EPUB width is limited to 760 logical pixels for readability.
  Body text uses a serif family with measured line spacing and paragraph
  gaps. Font-size controls still operate.
- Three **session-only** color palettes are available from the reader:
  follow device, warm sepia paper, and night. This increment does not
  claim persisted appearance preferences or synchronized colors with
  an OS-level custom theme.

## Narration, privacy and source consistency

- An EPUB read-aloud segment is segmented at the original spine boundary
  as before. Quote coalescing now also honors paragraph boundaries, with
  binary search to avoid quadratic work on long ebooks.
- The original source offsets, `epubSpine` reading anchors, cast span
  hashes, manual voice assignments, speech text and OpenAI consent remain
  unchanged. The visual renderer is purely a presentation projection.
- Tapping a spoken run invokes the preexisting explicit segment selection
  path. It does **not** start speaking or send text to cloud services.
  Selecting the Play action later still follows the user's consent,
  focus, native-stop timeout and character-budget guards.
- No EPUB HTML executes: there is no WebView, active scripts, external
  requests, arbitrary CSS or resource loading. EPUB images and external
  links are not rendered. The ZIP/XHTML safety restrictions from the
  extractor remain.
- TXT and PDF paths continue using their existing segment/page views,
  without new migrations or changes to PDF visual-page recovery.

## Code

- `lib/features/reader/epub_visual_layout.dart`: immutable paragraph and
  run model; source offset/segment mapping; paragraph merge barriers;
  Unicode-safe long-paragraph splitting.
- `lib/features/reader/epub_paragraph_tile.dart`: Flutter paragraph
  presentation, safe text spans, run-level tapping, heading semantics,
  and day/sepia/night palettes.
- `lib/features/reader/reader_screen.dart`: EPUB-specific list,
  synchronized scroll/resume mappings and palette selector.
- `lib/domain/dialogue_segmenter.dart`: efficient sorted hard-barrier
  search during quote coalescing.

## Authored regression coverage (unexecuted)

`test/features/epub_visual_layout_test.dart` covers seven scenarios:
source-exact paragraph/run reconstruction, chapter offsets and headings,
TTS boundaries between paragraphs, emoji/surrogate-safe long text,
unspoken gaps, malformed/overlapping segments, and empty/invalid input.

`test/features/epub_paragraph_tile_test.dart` covers four Flutter widget
scenarios: spoken-span tap mapping and in-line highlighting, accessible
chapter headings, palette contrast/readability and safe replacement of
tap recognizers when the list recycles a widget.

## Limitations and final acceptance

This is a **safe paragraph renderer**, not yet a full CSS/XHTML EPUB engine.
It does not restore author-defined fonts, typographic emphasis inside HTML
(`<em>`/`<strong>`), embedded pictures, mathematical formulas, tables,
indentation/floats, hyperlinks, footnotes, nested NAV/NCX semantics or
full EPUB CFI coordinates. Very long paragraphs may have an extra
non-semantic visual division for memory safety.

Before release, run `flutter analyze`, `flutter test`, and real
Windows/Android smoke tests on representative EPUB2 and EPUB3 books.
Verify source-exact copy/selection, 10k+ chapter navigation, landscape
layout, narrow Android phones, font scaling, screen readers, Unicode/RTL
texts, duplicate paragraphs, large quotes and cloud/native TTS cursor
tracking. Check that rapid chapter changes never re-synthesize or
lose the saved source position.

Related: [EPUB Chapter Navigation](EPUB_CHAPTER_NAVIGATION.md),
[Implementation Status](IMPLEMENTATION_STATUS.md),
[Development Plan](DEVELOPMENT_PLAN.md).
