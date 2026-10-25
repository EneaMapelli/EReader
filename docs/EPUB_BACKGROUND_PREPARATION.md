# EPUB background opening and large-spine navigation optimization

Increment: **25 October 2026** on
`feature/m0-flutter-foundation`.

**Code, test fixtures and documentation are committed to GitHub.
No Flutter analyzer, Dart/Flutter test runner, device benchmark or
Windows/Android release build has been executed here.** The repository's
latest local test report still reads `NOT_RUN`.

## Goal: responsive opening without modifying what gets narrated

EPUB decompression, XML/XHTML parsing, initial speech segmentation,
quote grouping and paragraph hard-boundary extraction were performed
in sequence by `ReaderScreen._load`, using significant CPU on Flutter's
UI isolate. This increment moves their **pure source-side portion**
into a background Dart isolate. Personal cast decisions, provider
preferences, consent, SQLite and audio-engine operations remain on
the existing reader side and are processed only after the source
has been returned.

### Reader preflight worker

`prepareEpubReader(localPath)` returns `EpubReaderPreflight`:

- `DocumentContent`: one canonical UTF-16 EPUB source, its ordered OPF
  ranges and source-verified local notes, styling, NAV/NCX, images,
  table previews, hyperlinks and import diagnostics;
- `List<QuotedSpeechChunk>`: initial speech segmentation and quote
  region groups, source-aligned to that exact document;
- `List<int> hardBoundaries`: the exact original paragraph boundaries,
  used to prevent coalescing speech across independent blocks.

The worker uses the existing `EpubTextExtractor`,
`segmentEpubSpine`, `splitQuotedSegmentsWithRegions` and
`epubParagraphHardBoundaries`. Their semantics were not rewritten.
`ReaderScreen` consumes this prepared result and then performs the
usual user-specific cast resolution, speech chunk coalescing, voice
initialization, progress recovery and progressive visual indexing.

The independent `PrototypeDocumentDecoder.read` entry point also
offloads EPUB extraction to an isolate. TXT and PDF read paths remain
unchanged.

**Memory and safety:** the worker reads the EPUB file directly,
instead of transferring an extra ZIP buffer from the UI isolate.
`readBoundedEpubFile` checks filesystem length before allocation and
actual byte count after the read, preserving the extractor's existing
100 MiB compressed ZIP ceiling. It does not relax uncompressed archive
entry quotas, note-size limits or external-resource restrictions.
The worker does not access Flutter widgets, speech providers, user
settings, SQLite, passwords, cloud endpoints or telemetry.

An `Isolate.run` execution still uses CPU and memory, and returning
the extracted model has a serialization/transfer cost. There is
currently **no user-facing cancellation or percentage progress
report**, and the EPUB is not streamed chapter by chapter from disk.
Those limitations remain open for device profiling and later work.

### Source-range and metadata indexing

- `buildProgressiveEpubVisualLayout` advances a monotonic speech
  segment cursor while scanning ordered paragraph boundaries, instead
  of performing a new O(log S) search for every indexed block.
  The same first-block ownership is retained for a single TTS segment
  that spans multiple visual paragraphs.
- `DocumentContent.anchorAt` now binary-searches ordered OPF spine
  range ends to construct EPUB progress/bookmark anchors in O(log N)
  rather than scanning every preceding chapter.
- `DocumentContent.offsetOf` uses a weakly associated per-document
  `idref → EpubSpineRange` lookup built on first use. Repeated legacy
  v1/v2 anchor restoration no longer requires an O(N) scan, and
  the index is garbage collectible with its owning document.
  Source-fingerprint validation remains mandatory.
- Locations on a synthetic two-newline separator continue to map to
  the **following** chapter, matching the old anchor semantics.
  A verified checkpoint at the end of the entire book still maps to
  the last chapter's end.

## Authored, unexecuted regressions

- `test/data/book_decoder_test.dart`: three EPUB isolate decode
  fixtures versus the direct extractor, malformed ZIP refusal and
  reopening the same book.
- `test/data/epub_reader_preflight_test.dart`: three worker-vs-direct
  equivalence fixtures for UTF-16 source offsets, quotes, hard
  paragraph boundaries, large chapters and invalid files.
- `test/data/epub_bounded_file_test.dart`: four tests for byte-exact
  reading, pre-allocation size rejection, non-overridable upper
  limits and missing local files.
- `test/features/epub_progressive_layout_test.dart`: one new parity
  fixture where speech segments cross many visual blocks.
- `test/data/reading_anchor_test.dart`: one large 15,000-chapter
  fixture covering binary anchor lookup, repeated ID restoration,
  synthetic separators and end-of-book progress.

**12 new cases were authored, not executed.** Before release, run
`flutter analyze`, all tests and Windows/Android integration checks.
Use [the single-branch local runner](../tool/run-all-tests.ps1) to
publish the results in `test-results/`, including failures.

## Profiling targets for final integration

For the same representative EPUB corpus and device hardware, compare
opening latency, UI frame jank, maximum resident memory, memory
retained after scrolling 10,000 paragraphs, and CPU use on
initial speech preparation. Do not extrapolate measured improvements
from algorithmic complexity alone.

Related documents:
[Large EPUB Performance](EPUB_LARGE_BOOK_PERFORMANCE.md),
[Progressive Visual Layout](EPUB_PROGRESSIVE_LAYOUT.md),
[Progress Recovery](EPUB_PROGRESS_RECOVERY.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
