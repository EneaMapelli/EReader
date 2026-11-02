# EPUB chapter directory: direct section lookup and return to current

Implemented on `feature/m0-flutter-foundation`, 2026-11-02
(draft PR #1).

## Reader workflow

The searchable EPUB directory now supports two complementary modes:

- Search by chapter title using the existing case-insensitive all-word
  search, including duplicate titles.
- Enter an explicit **1-based original section number** with a leading
  hash, e.g. `#125` or `# 125`. This matches exactly the 125th entry
  in the publisher NAV/NCX table of contents, or in the OPF spine
  fallback when the publisher has no TOC. It does not mean speech
  segment number, a filtered-row index, or percent of book progress.
  The search result retains its original directory identity.

The new **Show current section** compass button in the sheet header
clears the search and repositions the virtualized list at the current
source directory entry. It works after a failed search or numeric
lookup, and even if the user manually scrolled away from the current
entry without searching. The action never closes the sheet, seeks
speech, changes the EPUB source checkpoint, or saves a bookmark.

On very small Android screens with the on-screen keyboard open, the
same icon appears in the compact directory header rather than being
lost in a tall multi-line title.

Invalid section numbers (zero, greater than the number of sections,
or an integer too large to parse) return an empty result; they do not
jump to the beginning/end or create an audio cursor. Bare digits
without `#` continue to be ordinary title searches.

## Source safety

`readerDirectoryItems` generates immutable per-entry original
indices, and `filterReaderDirectoryItems` now recognizes numeric
lookup only when the entire trimmed query has the `#digits` syntax.
The result selection still returns the original index through the
existing `showReaderChapterDirectory` API, and the reader still
performs its own latest-intent source selection after the sheet
closes. Silent illustration-only spines and equal text offsets
remain distinguishable.

The current-section button increments a local virtual-list revision
so `ScrollablePositionedList` is remounted at the correct original
index even when the filter was already empty. It does not create
a second playback or source-position state owner.

## Regression coverage authored

`test/features/reader_chapter_directory_sheet_test.dart` now checks:

- `#1`, `#2`, `# 3`, invalid and overflow numbers, and ordinary title
  searches with embedded digits.
- Selecting `#2000` from a 2500-entry publisher TOC returns original
  index 1999, never filtered-row index zero.
- Clearing a numerical search through **Show current section** returns
  to a distant active entry without emitting a navigation action.
- Clicking the current-section action on an already unfiltered list
  forces a new virtual-list key/recenter while leaving selection unset.
- Existing silent-spine, duplicate-title, search and 200%-text-scale
  tests remain in the file.

## Manual checks

Open a large EPUB with a publisher TOC and one without (OPF fallback).
Use `#125` to locate a numbered section, cancel the sheet, then
reopen and tap **Show current section**. Confirm no reading checkpoint
or TTS state changes until a chapter is explicitly selected.
Repeat at 320px with a visible Android keyboard, and with duplicate
author TOC labels, silent illustrated spines, and 200% scaling.

**Validation:** commits and static source inspection only. Flutter
widget tests, analyzer and Windows/Android native interaction have
not been executed. No Windows builds or GitHub Actions started.
