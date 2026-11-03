# Immersive EPUB reading: chapter context and local navigation

Implemented on `feature/m0-flutter-foundation` · 2026-11-03 · draft PR #1.

## Reader behavior

Immersive focus mode previously hid narration controls and showed only
the overall **whole-book** source-text progress. In EPUBs this made
finding the current chapter harder than in the normal reader, which
already shows the chapter title and local percentage.

The immersive AppBar now has:

1. The existing whole-book source progress row (**44 logical pixels**),
   with its separate **Go to book position** action.
2. An additional compact EPUB-only row (**48 logical pixels**)
   containing a one-line, ellipsized chapter title, **section number
   / section count**, and when unambiguous, its **local source progress
   percentage**.

The chapter title and section count open the existing searchable EPUB
table of contents / OPF directory without navigating anywhere.
The optional local percentage opens the existing **Go to section
position** dialog. It is not the same operation as whole-book Go.
If the section range is ambiguous, illustrated-only or empty,
the local percentage button is omitted, but the chapter shortcut
remains available. Plain TXT and PDF keep the original single-row
focus header with no fabricated chapter metadata.

All action targets have independent TalkBack semantics:
- **Book text position:** current whole-book percent, open global Go.
- **Current EPUB section:** chapter label and section ordinal, open TOC.
- **Section text position:** chapter-local percent, open section Go.

No new source-of-truth has been added for source positions. The focus
header subscribes to the existing `_visualProgressTick`; the
section title, ordinal and percent all reflect the **visible** original
EPUB source cursor, not the current speech segment or elapsed audio.
As manual scrolling detaches from automatic narration follow, this
header can update without seeking or pausing audio.

## Source and persistence guarantees

The two Go dialogs reuse the existing guarded original-source
navigation pipeline. Merely opening the directory or Go chooser
does not issue a seek or persist an SQLite bookmark. Canceling
either dialog is a no-op. A confirmed chapter-local Go uses the
valid, unique `ReaderSectionRange` and remains inside the section.
A confirmed whole-book Go continues to support the full document
including true EOF.

`_openGoToProgress` already checks book ID, load epoch, player,
document and (for local Go) current section after the dialog closes.
The focus header only delegates to that method. It does not own
native Stop, TTS transport, source selection or return history.

## Test coverage authored

- `test/features/reader_focus_progress_strip_test.dart`
  verifies three independently actionable tap/semantics targets,
  global-versus-local percent labels, ambiguous and missing chapter
  metadata, updates without callbacks and a long EPUB title at
  320 logical pixels with 200% accessibility scaling.
- `test/features/reader_focus_epub_integration_test.dart`
  creates a real two-chapter EPUB3 ZIP fixture with a publisher
  navigation document, imports it through `LibraryStore`, opens
  focus mode, visits/dismisses TOC, cancels chapter Go and global
  Go without checkpoint writes, then confirms chapter-local 75%
  and checks its saved source coordinate is before chapter two.
- The existing TXT focus tests remain unchanged and should continue
  to show one row only.

## Manual device acceptance

1. Open an EPUB with publisher TOC. Enter focus mode, including via
   F11 on desktop. Verify both global progress and current chapter
   title/number in the AppBar.
2. Tap chapter name, dismiss the directory; check audio and durable
   reading position are untouched.
3. Tap the local percent, cancel; then tap whole-book percent and
   cancel. Confirm neither wrote progress. Confirm a local 75% jump
   remains inside the chapter and does not restart narration.
4. Scroll away from the narrated chapter while TTS plays and Follow
   is temporarily detached. Verify chapter context follows the
   **visual** viewport, not the independent speech cursor.
5. Test silent illustrated-only spine sections with duplicate
   source offsets: chapter shortcut remains, ambiguous local
   percentage does not appear.
6. Use a 320px wide phone, text scaling at 200–300%, rotation and
   split screen. Verify no row overflows and the restore-controls
   FAB remains reachable. TXT/PDF should still have only the
   original 44px whole-book row.

**Validation:** changes and widget/integration test sources committed
and statically inspected. Flutter analyzer and widget tests have
not been executed; no Android/Windows build or GitHub Actions was
started. PR #1 remains draft until runtime validation.
