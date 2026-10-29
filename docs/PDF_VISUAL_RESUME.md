# PDF visual page resume — independent from read-aloud offsets

Implemented as source on `feature/m0-flutter-foundation`, 2026-10-23.
**Flutter tests and native builds have not been run**, per the approved
integration-later workflow.

## Contract and storage

- SQLite **v15** adds a nullable `books.pdf_visual_page` field with a
  `1..100000` validity constraint. Previous database versions are upgraded
  transactionally (including sequential v13 → v14 → v15 migrations).
- `LibraryStore.getPdfVisualPage(bookId)` defaults to page 1 when there is no
  visual page saved; it refuses IDs that do not exist or are not PDF.
  `savePdfVisualPage` validates the page number and the PDF record.
- Visual page updates touch **only** `pdf_visual_page`. They never update
  `progress_offset`, `progress_anchor`, casting spans, cloud permission,
  quota or the last-opened timestamp.
- This works for PDF files **without a selectable text layer**. Import and
  visual rendering are independent from experimental PDF TTS extraction.
- A missing or deleted book has no usable visual page. Reimporting identical
  content can recover a missing private file while retaining the database's
  page bookmark, as in the existing deduplication path.

## Reader behavior

- `PdfViewer.file` initializes with the stored page number and uses
  `PdfViewerParams.onPageChanged` to capture the currently reported page.
- Rapid page changes are debounced for 350 ms. Pending changes are flushed
  synchronously when the app enters background, the reader closes or the user
  enters experimental PDF text mode.
- When switching from text reading back to the visual PDF viewer, the latest
  observed visual page remains selected. Stale text scroll callbacks and
  pending visual-text timers cannot rewrite the spoken-text anchor while the
  PDF page viewer is displayed.
- The PDF viewer itself clamps the initial page number to an available page
  when the file has changed. EReader restricts page values independently to
  the storage domain; the actual page count is only known by the PDF engine.

## Test coverage authored but unexecuted

`test/data/pdf_visual_resume_test.dart` adds seven deterministic SQLite
tests for first-page default, restart persistence, separate audio/text anchor,
scanned/no-text PDFs, invalid/non-PDF references, v14→v15 and v13→v15
migrations, and cleanup after removal. It uses PDF-signature fixture imports
without invoking the native PDFium engine.

Remaining *device* validations:
- Save page 12 of a text PDF, reopen the app and verify exact visual page.
- Repeat on a scanned PDF without enabling OCR or spoken extraction.
- Jump pages rapidly and background/kill the app before debounce completes.
- Switch visual ↔ text mode, confirm each preserves its own position.
- Test large PDFs and verify `onPageChanged` page reporting under landscape,
  continuous scrolling, nonstandard paper dimensions and rotation.
- Confirm Flutter analyzer, SQLite migration and Windows/Android build.

The implementation is **page-granular**, not a precise vertical scroll/zoom
bookmark, and it does not add OCR or synchronize text highlighting to page
coordinates. Native device tests are essential before declaring full
reliability.

API references:
- https://pub.dev/packages/pdfrx
- https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageChangedCallback.html

## 2026-10-29 — Quick page scrubbing for faithful PDF view

The native PDF viewer now has a **physical-page scrubber** below its
existing Previous / page-number jump / Next / Zoom toolbar.

- Dragging the slider previews a page number and physical page
  percentage, **without** loading each intermediate page.
- Releasing the slider requests **one** page jump through the existing
  `_goToPdfPage` callback. Native PDF page rendering and the usual
  debounced visual-page persistence remain owned by ReaderScreen.
- A one-page PDF has no scrubber; an uninitialized page count also has
  none. The exact numeric Go-to-page dialog remains available.
- For PDFs with 201 pages or fewer the slider has one step per page.
  Long PDFs have at most 200 slider divisions. Entering a specific page
  number is still exact.
- The percentage represents physical page position (first page 0%,
  last page 100%), **not** EPUB/TXT offsets, text coverage, elapsed
  playback or PDF OCR. Scanned PDFs use the same visual navigation
  without synthesizing speech.
- Slider semantics announce the page number and count. It does not
  request cloud audio, alter book text or update TTS checkpoints.

Regression cases were authored in
`test/features/pdf_page_navigation_widget_test.dart` for the one-shot
release event, physical page percentage and semantic label, coarse
long-document stepping with exact numeric fallback, and absent slider
when no multi-page PDF is loaded. The legacy PDF migration fixture
also now expects the current SQLite user_version **18**, not 17.

**No tests or platform builds were run** in this editing environment;
no GitHub Actions were dispatched. Device verification is still
required for PDF decoder responsiveness, accessible controls and
visual-page checkpoint persistence.
