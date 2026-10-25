# EPUB reader frame sampling — local opt-in diagnostics

Increment: 2026-10-25. Development branch:
`feature/m0-flutter-foundation`.

## Goal and operation

EPUB opening timings cannot demonstrate scrolling responsiveness. The
existing `EPUB opening performance` sheet now offers **Sample frames for
12 seconds**. It closes the modal and registers a Flutter
`SchedulerBinding.addTimingsCallback` listener so the user can scroll
an actual book. The listener stops automatically after 12 seconds or
immediately on manual Stop, navigation/loading, app backgrounding or
reader disposal. Reopening the report shows numeric summary statistics.

The sampler retains at most the most recent 4,096 duration triples,
measured in microseconds: UI build, raster and end-to-end frame latency.
Nearest-rank 95th percentiles, maxima and counts above 16.7 ms
(a **60 Hz reference**, not a device refresh-rate measurement) are
calculated from those retained triples. The displayed numerator is the
retained sample size and the denominator is the total valid frames
received during the capture. Empty samples remain explicitly empty.

## Scope and caveats

- Frame timings are engine-level, not tagged per widget/paragraph.
  Other routes, overlays or media-control animations can influence a
  capture, so scroll with other activity minimized.
- Flutter may batch timing reports; the start/end boundaries are based
  on delivery, not exact presentation timestamps. Some pre-start or
  recently rendered frames can appear in a delayed batch, and late
  batches may be omitted.
- At refresh rates above 60 Hz the 16.7 ms reference is not the actual
  frame budget. P95 frame durations do **not** establish FPS or prove
  user-visible dropped frames. No peak resident memory is measured.
- Capturing is disabled by default and never persists or exports data.
  Only numeric durations and counts are held in a bounded in-memory
  buffer. Book text, link targets, local paths, cast identities, cloud
  provider keys and access credentials are never sampled or logged.
- The application retains its source-exact EPUB indices and does not
  change narration, TTS network permissions, position bookmarks or
  SQLite schema. Capture adds no background polling when inactive.

## Authored regression tests, unexecuted

- `test/features/epub_frame_sampler_test.dart`: empty/invalid
  measurement handling, exact nearest-rank results and 60 Hz counters,
  fixed-size ring overwrite.
- `test/features/epub_opening_performance_sheet_test.dart`: explicit
  start, bounded numeric summary display and stop action.

Flutter analyzer, full suite, real EPUB scrolling under Profile mode,
and Windows/Android native device verification remain **NOT_RUN**.
Use the existing `tool/run-all-tests.ps1` to publish results on the
same branch. Frame sampling is instrumentation, **not evidence yet** of
a performance improvement.
