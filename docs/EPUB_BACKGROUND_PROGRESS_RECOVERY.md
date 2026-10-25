# EPUB background recovery of saved reading position

Increment: 2026-10-25, branch `feature/m0-flutter-foundation`.

## Purpose

Long EPUB chapters may require scanning up to 160,000 UTF-16 code units
to relocate a saved v2 fingerprint. Previously this synchronous scan ran
inside `ReaderScreen._load` on Flutter's UI isolate after the ZIP worker
had already returned, risking a stalled opening animation.

## Design

1. The reader obtains a persisted anchor and integer offset from SQLite
   before spawning the cancellable EPUB worker.
2. The worker decodes the archive, builds segments/boundaries, then calls
   the **unchanged** `resolveEpubReadingProgress` against the original
   canonical source while that source is already present in its isolate.
   The result travels alongside the prepared document via `Isolate.exit`.
   No extra whole-book isolate copy or new persistent storage is needed.
3. The reader re-reads the database checkpoint before using the result.
   An exact field-by-field comparison guards against an intervening save.
   If the checkpoint changed, the previously computed result is discarded
   and the conservative synchronous resolver is used only for that race.
4. Verified unique relocations continue to write a fresh source-relative
   v2 anchor, while `needsReview` never invents a seek or overwrites the
   saved progress. The existing non-autoplay warning is preserved.
5. Worker cancellation or widget disposal cancels the scan along with
   archive extraction. Independent EPUB tasks remain isolated.
6. A numeric-only `resumeRecoveryUs` metric is included only when a
   checkpoint was supplied. The reader performance sheet exposes this
   stage; no book excerpts, paths, or saved hashes appear there.

No change to TXT/PDF behavior, EPUB source offsets, voice casting,
SQLite schema, cloud permissions, budget checks or TTS selection.

## Validation and remaining limits

New authored, unexecuted fixtures in
`test/data/epub_reader_preflight_test.dart` verify exact v2 positions,
unique relocation on inserted paragraph boundaries, missing chapter
fail-closed recovery and legacy offset compatibility. The metric row is
covered by `test/features/epub_opening_performance_sheet_test.dart`.
All pre-existing pure resolver tests remain applicable.

Still to validate on the owner's Windows/Android machine: Flutter analyzer,
whole test suite, delayed/overlapping checkpoint writes while preflight is
running, cancellation during a long hash scan and real-book performance
using `tool/run-all-tests.ps1` plus device profiling. The fallback path
for a checkpoint changed during worker startup still runs on the UI
isolate, by design; it is the uncommon correctness-first case.
**No tests/builds were executed for this increment.**
