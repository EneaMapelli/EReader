# EPUB large-book performance — bounded layout and indexed navigation

Increment: 2026-10-24, branch `feature/m0-flutter-foundation`.

**All source and stress tests were authored and committed on GitHub.
No Flutter analyzer, test runner, Windows/Android builds, memory profiler
or device benchmarks have been executed.** Performance claims here are
algorithmic expectations, not measured speedups.

## Problems addressed

Previously, the source-aligned paragraph renderer would:

- copy the entire XHTML spine item's extracted text again before each
  paragraph-boundary regex scan, while also keeping the canonical source;
- eagerly construct a new substring for every spoken/unstyled/linked
  display run, including paragraphs that the user might never scroll to;
- clone **every** block a second time just to attach a handful of image
  and table previews;
- scan every saved auxiliary note for every internal note link;
- find the current chapter and initial speech index with linear scans;
- compute **both** SHA-256 context hashes at **every** possible position
  when recovering a changed v2 progress anchor.

For a long novel or compilation these unnecessary allocations and repeated
searches compound even though Flutter's visible paragraph list is lazy.

## Changes

1. `epubParagraphHardBoundaries` and
   `buildEpubVisualLayout` scan the original canonical
   `String` starting at a spine offset, ending the scan strictly at the
   current spine item's boundary. They do not create full-chapter
   intermediate strings, and do not include cross-item paragraph breaks.
2. `EpubVisualRun.fromSource` retains validated original UTF-16
   `start/end` plus the existing shared book `String` reference;
   `run.text` takes a substring **only on demand** (normally when the
   paragraph is actually built by the scrolling list). The existing
   `const EpubVisualRun(start,end,text,segment)` constructor remains
   supported for tests and standalone widgets. No duplicated source
   text is inserted into the narration stream.
3. Heading checks operate directly on source code units; title
   normalization is performed only when a matching publisher chapter
   heading exists. A Unicode whitespace-aware check preserves semantic
   headings without materializing all runs.
4. With no image/table overlays, `EpubVisualLayout` returns its
   first block list without cloning every block. When overlays exist,
   it replaces only affected paragraph objects, reusing their
   existing run lists and all unaffected blocks.
5. Auxiliary note target keys are put in a `Set<String>` so the
   link validator uses O(1)-average membership instead of an O(L × N)
   nested scan. Invalid or missing keys still fail closed; auxiliary
   notes still have no invented source/TTS offsets.
6. `chapterIndexForOffset` uses O(log N) binary search over ordered
   chapter starts; the reader uses the existing
   `speechSegmentIndexForOffset` binary search to restore an initial
   source position, including a verified end-of-book checkpoint.
7. `EpubAnchorContext.matches/relocate` hashes the context **before**
   the candidate position first. Only if that fingerprint matches does
   it hash the context **after** it. The same original v2 SHA-256
   byte format, source offsets and strict exactly-one-match relocation
   policy remain in force. This avoids unnecessary hashing for most
   invalid candidates, but a long ambiguous search can still be
   CPU-intensive and is bounded to the existing 160,000 UTF-16 units.

All changes are local to EPUB reading/presentation and source fingerprint
matching. TXT/PDF reading, cloud consent/budgets, speech providers, manual
character attribution, SQLite schema, audio behavior and license are
unchanged.

## Authored regression/stress tests, not executed

- `test/features/epub_visual_layout_test.dart`:
  source-backed lazy run, a synthetic **12,000 paragraph** EPUB with
  emoji/speech-index spot checks, adjacent spine paragraph regex
  boundary case, and **1,200 verified auxiliary note references**.
- `test/features/epub_chapter_navigation_test.dart`:
  source offset lookup against **20,000 chapters** and out-of-range
  offsets.
- `test/domain/epub_anchor_context_test.dart`:
  fixed **v2 SHA-256 digests** to prevent breaking progress and
  bookmark fingerprints by changing algorithm semantics.

These are deterministic functional fixtures, **not benchmark results**.
They must run in the final integration suite before any speedup or memory
usage claim can be made.

## Additional EPUB narration improvement (2026-10-24)

- `segmentSpeechRange(source, start:, end:)` splits a bounded global
  UTF-16 range **directly** in the canonical book string. Each result
  carries the original global start/end and extracts only the actual
  short spoken segment string. It respects punctuation, decimals,
  whitespace trimming, sentence limits and surrogate pairs.
- `segmentEpubSpine` no longer allocates a full
  `source.substring(range.start, range.end)` for every XHTML spine file
  and then adds offsets to local segments. This removes another eager
  whole-chapter text copy during EPUB opening, independently of visual
  paragraph rendering.
- Existing `segmentSpeech(source)` forwards to the new range routine,
  keeping TXT/PDF behavior and defaults. The
  `test/domain/speech_segment_test.dart` regressions compare the
  range-based segments to the historical locally sliced equivalent,
  reject half-emoji chapter boundaries and cover a synthetic
  16,000-sentence source. **Tests authored but not run.**

## Remaining bottlenecks / next steps

The app still decodes the EPUB, derives the canonical book source,
prepares speech segments and constructs block/run **metadata eagerly**
on open. It avoids most eager copies of run text, but does not yet
implement a paged-on-disk source index, stream the ZIP parser, or perform
progress relocation on a worker isolate.

Further work for very large EPUBs should profile memory and launch
latency on representative Android phones and Windows machines. If
measured limits justify it, use a bounded chapter metadata index and a
worker isolate for expensive parsing/relocation, while retaining exact
source UTF-16 indices and privacy-safe offline behavior. Continue to
defer the actual Flutter analyzer/tests/native builds until the
explicitly agreed final integration gate.

Related: [EPUB Paragraph Renderer](EPUB_PARAGRAPH_RENDERER.md),
[EPUB Progress Recovery](EPUB_PROGRESS_RECOVERY.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
