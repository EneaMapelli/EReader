# PDF library thumbnails — M1 improvement (2026-10-26)

## Behavior

- When a PDF row first becomes visible, EReader renders **page one** with the
  existing `pdfrx`/PDFium backend. There is no network access and no cloud
  provider involvement; the entire PDF remains on device.
- A preview is bounded to **180 × 260 pixels**, preserving page aspect ratio,
  converted to PNG and cached under `covers/<sha256-book-id>.png` in the
  application's private support directory. Render output above 1 MiB is
  rejected; source PDF imports remain capped by existing book limits.
- The list uses the cached file immediately on subsequent visits and app
  starts, including on devices where PDFium cannot render a new thumbnail.
  Rows without a valid preview retain the PDF icon. EPUB2/3 cover behavior is
  unchanged; TXT rows retain the book icon.
- Concurrent requests for the same book share a single generation future.
  An error or invalid preview is memoized for the rest of the current app
  session, preventing repeated expensive attempts as a user scrolls. Restart
  permits a fresh attempt. Removing a book deletes the derived preview.
- A source deleted during an in-flight render is checked again before and
  after the atomic cache rename, to avoid leaving a thumbnail for a removed
  book. A failed thumbnail never blocks import, opening, reading or TTS.

## Architecture

- `lib/data/pdf_cover_thumbnail.dart`: narrow PDFium → PNG adapter.
  It disposes the PDF document, page image and decoded UI image.
- `LibraryStore.ensurePdfCover`: validates the content-derived book ID and
  managed source path, caches, deduplicates and cleans up thumbnails.
- `LibraryBookCover` in `library_screen.dart`: renders an EPUB cover from
  existing storage synchronously, starts PDF rendering only for visible
  rows, and falls back to a format icon.
- `PdfCoverRenderer` is injectable to unit/widget tests that cannot link
  native PDFium. Injection is a test seam, not an external plugin surface.

## Manual Windows/Android qualification (still open)

Run from the checked-out `feature/m0-flutter-foundation` HEAD:

1. Execute `tool/run-all-tests.ps1` in PowerShell and publish only the
   sanitized summary using the repository runner documentation.
2. Import a small text-layer PDF and verify page-one image appears without
   freezing the list; restart the app and check that the same cached thumbnail
   is displayed without rerendering.
3. Import an encrypted PDF, an invalid PDF with a `%PDF-` signature, and a
   large-page PDF; verify the fallback icon and normal import/list controls.
4. Rapidly filter/sort/scroll a 100+ PDF library and watch private cache size
   and memory use. Remove a book while its image is being created; ensure no
   orphan `.png` or `.part` remains.
5. Check PDF thumbnails and the existing EPUB covers on real Windows x64
   and Android arm64 devices, including cold start and poor-storage cases.

**Status:** source and synthetic unit/widget cases added but **not yet run**
in this GitHub editing environment (no Flutter/Dart or native PDFium SDK
available). Real first-page rendering and UI responsiveness remain acceptance
gates, not verified achievements. This does not improve the release-readiness
estimate until the local and device runs confirm the feature.
