# EPUB progress recovery across extractor changes

Increment: 2026-10-24 on `feature/m0-flutter-foundation`.

**Implementation and regression tests committed. No Flutter analyzer,
Dart/Flutter test runner, Android/Windows build or device QA executed.**

## Why a version-2 EPUB anchor

A version-1 `ReadingAnchor` stores an OPF spine `idref` and a
UTF-16 offset relative to that spine item. This protects against
inserted/removed text *in earlier chapters*, but **cannot detect**
a parser update adding line breaks inside the *same* chapter.
The old offset may still be within range while pointing to a
different word.

Version 2 retains the existing `kind`, `sourceId` and
`localOffset` and adds `contextBefore` / `contextAfter`:
two **32-hex-character truncated SHA-256 hashes**, derived from up
to 32 **non-whitespace UTF-16 code units** on either side of the
saved position, in their original order. No clear-text excerpt,
remote URL, embedded file or new cloud request is stored.

The fingerprints deliberately ignore whitespace to tolerate
paragraph separators changing from spaces to newlines. Hashing
raw UTF-16 units prevents accidental Unicode replacement when
emoji/surrogate pairs are involved. SHA-256 digests identify nearby
source context but are **not encrypted secrets**; all values remain
local in the existing SQLite JSON columns.

`ReadingAnchor.fromJson` continues to read version-1 anchors
unchanged. New version-2 data is validated strictly: EPUB kind,
both hashes present, lowercase hexadecimal characters and exactly
32 characters each. Malformed or unknown versions are rejected.
**No SQLite schema migration** is required.

## Recovery decision policy

At EPUB open, the reader examines stored progress:

1. **Exact:** matching v2 hashes at the stored local offset and
   inside the same spine item. Resume there.
2. **Relocated:** hashes no longer match at the old offset, but
   there is exactly **one** match in that same readable spine item.
   Resume at the new UTF-16 offset and persist a fresh v2 anchor
   after the reader has initialized. No playback is started.
3. **Needs review:** zero or multiple matching locations, vanished
   source item, or an out-of-range saved anchor. Resume at the
   beginning of the same chapter when it still exists (otherwise
   the beginning of the book) and show a visible warning. Never
   silently select the nearest repeated phrase or a raw absolute
   offset from another chapter. The unverified old position is
   not automatically overwritten.
4. **Legacy unverified:** v1 spine anchors and pre-anchor absolute
   offsets remain readable. A v1 anchor whose local offset is
   invalid now falls back to that chapter's start with a warning.
   Without historical context, v1 cannot prove that a still-valid
   numeric offset refers to the same words: this remains a known
   limitation until newer checkpoints replace it.

Full-chapter uniqueness matters: **the first or closest match is
not sufficient** if identical text occurs twice. Source scanning
is bounded to 160,000 UTF-16 units per spine item (otherwise
the system asks the user to review), and skips unanchorable
whitespace positions and Unicode half-surrogates. Scans happen
only when an existing v2 progress anchor has changed. The hot
path for exact anchors does not scan the chapter.

The normal narrator is never auto-started and there is no
additional consent, API call, generated speech or voice change.
Only a uniquely verified relocation may update the progress
checkpoint automatically. Database write failure is visible
but does not prevent reading.

## Bookmarks and other anchored metadata

- New EPUB bookmarks and checkpoints use v2 context hashes
  via `DocumentContent.anchorAt`.
- For bookmarks, `showBookBookmarks` uses the same local recovery
  decision (cached per open sheet). A unique relocation is usable.
  An ambiguous or unverifiable bookmark is displayed as **Needs
  review**, with navigation disabled rather than silently jumping
  to another sentence. Deletion remains available.
- Casting, annotations and attribution continue to call
  `DocumentContent.offsetOf`: mismatched v2 fingerprints yield
  `null`, not an invented new location. This increment **does
  not** automatically rewrite cast regions or move their boundaries.
- PDF and TXT anchor behavior is unchanged.

## Changed files and regression fixtures

- `lib/domain/reading_anchor.dart`: backwards-compatible v1/v2
  JSON persistence and strict digest validation.
- `lib/domain/epub_anchor_context.dart`: bounded two-sided
  source fingerprint capture, exact matching and unique relocation.
- `lib/data/book_decoder.dart`: new EPUB anchors receive
  fingerprints; outdated source offsets are refused.
- `lib/data/epub_progress_recovery.dart`: explicit exact,
  relocated, legacy-unverified and needs-review states.
- `lib/features/reader/reader_screen.dart`: safer initial
  position, confirmed relocation checkpoint write and warning
  for unverified progress; no automatic TTS.
- `lib/features/reader/reading_tools.dart`: safe EPUB bookmark
  navigation with visibly disabled unverifiable bookmarks.
- `test/data/epub_progress_recovery_test.dart`: nine authored
  scenarios for exact, relocated, repeated, vanished, changed
  paragraph and legacy positions plus persisted JSON.
- `test/domain/epub_anchor_context_test.dart`: six source-hash
  and malformed-JSON scenarios.
- `test/data/library_store_test.dart`: SQLite restart round-trip
  for v2 metadata using the existing JSON column.

## Known limitations and integration gate

Whitespace-insensitive hashes cannot recognize arbitrary wording
edits inside the local context window. A position inside whitespace
may require manual review. Chapters longer than the scan budget
are deliberately not searched automatically. Repeated text has
no reliable automatic result. Old v1 anchors never had a context
hash and cannot be upgraded to certainty retroactively. A
publisher reassigning `idref` values across spine items also
requires manual review.

These are deliberate conservative fallbacks, not evidence that
positions have been fully recovered. At final integration,
exercise an EPUB corpus with changed `br` handling, duplicate
phrases, long chapters, Unicode, app restarts, SQLite upgrades,
background narration, and saved bookmark/annotation behavior.
Run analyzer, tests and Windows/Android builds **then**, per the
existing project testing plan.

See [EPUB Import Diagnostics](EPUB_IMPORT_DIAGNOSTICS.md) and
[Implementation Status](IMPLEMENTATION_STATUS.md).
