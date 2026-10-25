# EPUB progressive visual paragraph index and bounded cache

Increment: 2026-10-25 on `feature/m0-flutter-foundation`.

**Code and regression tests committed on GitHub. Flutter analyzer, widget
tests, unit tests and Windows/Android builds have not been executed.**
The latest machine-run report remains `test-results/latest.json = NOT_RUN`.

## Objective

Large EPUBs previously constructed a full `EpubVisualBlock` and
`EpubVisualRun` object graph for every paragraph *before* the reader
appeared, even though `ScrollablePositionedList` only mounted a small
portion of those paragraphs. Avoid that eager work without changing any
speech source, persisted anchor, visual styling or link destination.

## Implementation

`buildProgressiveEpubVisualLayout` in
`lib/features/reader/epub_progressive_layout.dart` now builds only
an **ordered, source-exact paragraph metadata index**, containing
original UTF-16 `start/end`, chapter start flag and first speech segment.
It simultaneously builds `segmentToBlock` so auto-follow, chapter
navigation and playback synchronization remain O(1) per index.

The resulting `ProgressiveEpubBlocks` is a read-only, list-compatible
virtual collection. It constructs each paragraph's complete styled
run list **on first access**, using binary search into sorted speaker,
style and internal-link metadata. Book source text is not copied until
the paragraph widget actually needs a visible substring.

- **Cache:** bounded LRU, by default 48 materialized paragraphs, with
  a configurable range 1–256. Evictions discard display models only;
  canonical original text and saved progress remain untouched.
- **Overlays:** images and table previews are assigned to paragraph
  indices once at index construction. Opening a paragraph no longer
  scans all book assets.
- **Links and notes:** exact in-book source targets and independently
  verified auxiliary note keys are preserved, including read-only
  note previews with **no synthetic speech offset**. Unsafe metadata
  fails before a paragraph can be opened.
- **Unicode:** long paragraphs are bounded and split without cutting
  surrogate pairs; paragraph source offsets are never re-based.
- **TOC:** the existing chapter sheet now opens a virtualized
  `ScrollablePositionedList` at the active publisher NAV/NCX section,
  or the active OPF spine chapter when no publisher TOC exists.

The existing eager `buildEpubVisualLayout` remains available as a
**behavioral reference** while the reader uses the progressive path.
The model `EpubVisualLayout.blocks` remains a `List<EpubVisualBlock>`;
consumer widget signatures and the SQLite schema do not change.

## Authored regression tests

`test/features/epub_progressive_layout_test.dart` includes 8
**unexecuted** test scenarios comparing every property of eager vs.
progressive visual blocks, plus:

- Rich XHTML inline style, heading level, links, footnotes, tables,
  images and source-exact speech IDs.
- Two OPF spine items, gaps between speech segments and global offsets.
- Long emoji-only paragraphs, bounded splits and UTF-16 correctness.
- **12,000 paragraphs**: zero materialized rich blocks immediately
  after constructing the index, exact `segmentToBlock` lookup, cache
  ceiling of 6 and observable LRU eviction/re-materialization.
- Invalid source link/style and speech metadata fail closed without
  requiring any visible paragraph to be opened.
- Preview-only note markers remain available even when no speech
  chunk intersects a block.

These are source-authored tests rather than executed performance
benchmarks. On Windows/Android the final integration should compare
memory, opening time, scrolling responsiveness and cache churn against
the old renderer, and run the whole suite through
[`tool/run-all-tests.ps1`](../tool/run-all-tests.ps1).

## Scope and limits

The EPUB archive, canonical source, TTS segments and the lightweight
paragraph boundary index are still prepared at opening time.
Therefore this is **progressive construction of detailed visual
metadata**, not fully streaming ZIP import or on-disk chapter paging.

A pathological EPUB with more than **300,000** indexed paragraphs is
rejected to cap paragraph-index memory. EPUB ZIP and decompression limits
are unchanged. No cloud requests, scripts, CSS execution or consent
changes are added, and no speedup percentage is claimed until measured.

## Direct source-offset navigation and LRU regression (2026-10-25)

The reader can now scroll to an exact EPUB source paragraph for a note,
internal link, or publisher TOC target, even when the target falls outside
spoken TTS segments. The new `blockForSourceOffset` API uses O(log N)
search over metadata-only bounds in progressive layouts; lookup does
not hydrate rich runs. Eager layouts expose the same method for behavior
comparison. TTS selection and persisted source anchors are unchanged.

The 12,000-paragraph cache regression now requests seven distinct blocks
before checking eviction from a six-slot LRU (previously only six).
Added an unexecuted source-gap and no-materialization lookup regression.

## Precise EPUB bookmark/footnote resume (2026-10-25)

A stored EPUB position or note return may be inside a paragraph
that has no TTS segment, or in the middle of a long spoken segment.
The reader previously restored the **speech segment index** for its
initial visual scroll and used that same coarse segment on return,
even though the SQLite bookmark retained the precise original source
offset. This can visibly jump to a different paragraph after restart.

ReaderScreen now retains a session-only exact visual source offset
while restoring a saved EPUB checkpoint, following an internal link,
or returning from a note. Initial virtual list positioning and
note-return scroll use `blockForSourceOffset`, but the audio
engine still uses its normal source-aligned segment index. The first
layout notification for the same paragraph cannot rewrite the exact
bookmark to the nearby segment's start; genuine scrolling to another
paragraph or explicit audio playback clears that visual override.
No SQLite schema, remote request, narration text, or persisted
source anchor format changes.

A further authored test covers a wholly unspoken caption paragraph:
its internal source link must map to that caption, even though the only
TTS segment belongs to a later paragraph. This directly protects the
reader's link-navigation behavior without cloud synthesis.

The bookmark protection logic lives in the UI-independent
`EpubVisualSourceCheckpoint`, which preserves an exact offset on initial
same-paragraph list notifications, releases it on real navigation to a
different paragraph or playback, and never hydrates rich paragraph runs.
A new deterministic, unexecuted test covers preservation on a wholly
unspoken caption, true scroll invalidation, and explicit clear.

## Saving progress for non-spoken EPUB paragraphs (2026-10-25)

The read-along listener previously ignored visible paragraphs without
any TTS segment, and detected reading progress changes solely by the
speech segment index. That caused caption-only sections to be skipped in
saved reading position and long multi-paragraph speech segments to share
one coarse bookmark. The reader now tracks visible paragraph identity
independently of the nearest audio segment. It saves the **source offset
of the visible block**, even if no speech segment starts there; the audio
cursor continues to use its existing index. The visual checkpoint guard
continues to protect the original exact offset during initial restore.

`EpubVisualLayout.positionForVisibleBlock` supplies both coordinates.
A synthetic unspoken-caption regression compares eager/progressive
behavior and source offsets, ensuring the model materializes only the
visible blocks. Windows/Android execution remains outstanding.

## Hard visual splits protect common Unicode clusters (2026-10-25)

The eager and progressive EPUB paragraph renderers previously checked
only UTF-16 surrogate pairs at the maximum-block-length cutoff. Accents
formed with combining codepoints, ZWJ emoji (such as an astronaut),
skin-tone modifiers and paired flag indicators could be split across
visual blocks, despite the TTS chunker already protecting those sequences.

Both renderers now use the same pure bounded helper
`backtrackCommonGraphemeBoundary` from `speech_segment.dart`. Breaks
are backed up to a common-cluster boundary without moving source offsets,
expanding a block beyond `maxBlockChars`, changing markup/voice spans
or creating a second copy of the EPUB text. An exceptional cluster longer
than the configured block limit fails closed rather than rendering a
broken partial character. This is deliberately a **limited** Unicode
guard, not full UAX #29 grapheme-break compliance.

Added unexecuted eager-versus-progressive regressions for decomposed
acute accents, a ZWJ astronaut emoji, the Italian flag sequence,
skin-tone modifiers and an overlong combining sequence.

## Metadata-only visible reading checkpoint lookups (2026-10-25)

Scroll notifications on an EPUB can occur many times per second.
`positionForVisibleBlock` previously indexed a `ProgressiveEpubBlocks`
element to find its first source offset and TTS segment. That operation
silently hydrated all of the paragraph's rich runs and moved the LRU
even when the tile was offscreen or had no speech.

Progressive `EpubVisualLayout` now supplies a private metadata-only
callback backed by its existing immutable paragraph bounds. The visible
position (UTF-16 source offset plus nearest playable speech index)
is available without invoking the rich block builder. Exact note/TOC
navigation and cache behavior remain unchanged; eager layouts retain
the reference implementation.

The authored regressions assert zero materializations for deep positions
in a 12,000-paragraph EPUB and unspoken captions. Accessing an actual
visible tile still hydrates just that tile. Pending Flutter validation.
