# M2 — Exact source resume, PDF page-safe speech and EOF

**Date:** 2026-10-26. Implemented on `feature/m0-flutter-foundation`,
PR #1. Tests have been authored, NOT executed in this GitHub-only edit session.

## Problem addressed

The reader previously used the same speech-index resolver for an **explicit
source jump** and for a **persisted completed-book checkpoint**. The old
resolver deliberately clamps to the last playable segment, so reopening
after the last confirmed utterance could mark its final sentence as unread.
In addition, PDF speech was segmented across the entire text layer;
a TTS utterance could therefore cross a physical page and receive the
wrong page provenance for its end, its character cast or a saved checkpoint.

## Source resume vs explicit navigation

- `speechResumeIndexForOffset` returns `segments.length` at or beyond the
  final audible chunk's end. `ReaderPlayer` uses that sentinel for complete
  books. This is only for restoring a previously saved progress position.
- `speechSegmentIndexForOffset` still returns the last actual clip for an
  explicit TOC, search, text-link or bookmark jump.
- ReaderScreen shows **Reading complete — Play to restart** at the end.
  Pressing Play on an untouched completed book starts again from the first
  clip, not merely the last. If the user has navigated to an earlier visual
  paragraph, explicit user navigation still wins.
- The visual-list selected index remains bounded even when the audio
  cursor equals the number of segments; the first passive viewport event
  must not regress the final saved reading position.
- An old EPUB source checkpoint with no reading anchor is still
  unverified, but its valid `source.length` EOF position is now retained.
  Earlier implementation clamped the old integer to `source.length - 1`.
- The completed-utterance `NarrationRecoveryBinding` callback can now
  receive a canonical `anchorAtOffset` mapping. At the final utterance
  the actual EPUB spine/context or PDF physical page/within-page offset
  is saved in the existing transaction, not just an absolute integer.

## Page-safe PDF TTS

- `segmentPdfPages` segments each text-layer page **independently**, in
  physical page order and using the existing unchanged global UTF-16
  source coordinates. Image-only pages without text cannot be narrated.
- A segment may not cross a verified `PdfPageRange`; page separator text
  must be whitespace only. Invalid/overlapping ranges are rejected.
- PDF quote-group tracking resets at each physical page so an unclosed
  quote on an earlier page does not attribute speech on the next page.
  The same page starts act as hard merge boundaries for character voice
  attribution. TXT and EPUB extraction/quote behavior is unchanged.
- This does NOT fix reading order inside multicolumn or scanned PDFs.
  A physical PDF page remains distinct from a virtualized EPUB paragraph.
- The independent PDF *visual page control* still does not overwrite a
  saved TTS source checkpoint; only the explicit **Read text aloud**
  action starts speech at the selected page's text.

## Test coverage (authored, not run)

`test/features/reader/pdf_speech_navigation_test.dart` verifies
cross-page separation, quote-group reset, Unicode UTF-16 offsets, missing
image-only pages, rejection of invalid source ranges, explicit jump vs
completed-book resume, final PDF page anchor roundtrip and EOF.

`test/audio/narration_recovery_binding_test.dart` now also asserts the
final source anchor is retained. The pre-existing tests for interrupted
clip checkpoints, delayed native Stop and skipped EPUB notes remain.

`test/data/epub_progress_recovery_test.dart` tests both contextual EOF
anchors and old offset-only EOF bookmarks.

## Manual acceptance on Windows and Android

1. Run the locally available `tool/run-all-tests.ps1` and save its reports.
   Pay attention to the three suites above plus navigation tests.
2. Finish a TXT, EPUB and text-layer PDF, close and reopen each. The player
   should show a **completed** state instead of replaying the last clip;
   pressing Play should start over intentionally.
3. Navigate to a stored EPUB link/bookmark near the end and verify the
   intended source sentence still plays. A normal explicit jump is NOT EOF.
4. Use a multi-page text-layer PDF with short paragraphs around page
   boundaries; no TTS audio clip should include text from both pages,
   and subsequent checkpoints must preserve the actual page number.
5. Confirm that turning PDF visual pages alone does not change the saved
   audio progress. Then select **Read text aloud** and verify the
   requested page is used as the speech start.
6. Test quotes continuing across physical PDF pages, accented Unicode,
   multi-character cast assignments and Android interruption/reopen.
   Preserve any Windows native decoder or Android MediaSession error logs.

**Known gate:** no Dart formatter/analyzer, no Flutter tests and no native
Windows/Android builds or audio measurements executed here. The work does
not claim word-level read-along or gapless playback.
