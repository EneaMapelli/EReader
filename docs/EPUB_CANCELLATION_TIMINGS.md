# Cancellable EPUB preparation and local performance measurements

Increment: 25 October 2026. Branch:
`feature/m0-flutter-foundation`.

**Implementation committed; no Flutter analyzer, Dart unit/widget suite,
Android or Windows compilation, or actual device performance profile run
by this assistant.** The automatic PC report still needs to be published
in `test-results/latest.json`.

## Cancellation / stale load safety

`startEpubReaderPreflight(localPath)` now returns a
`CancellableEpubPreflight` handle synchronously. Unlike the previous
one-shot `Isolate.run`, it owns a dedicated `Isolate.spawn` instance,
an isolate-to-main result port, and a one-shot completion Future.
Calling `cancel()`:

- marks the task terminal, completes its Future with
  `EpubPreflightCancelled`, and closes the response port;
- kills the running worker immediately with `Isolate.immediate`;
- handles cancellation **even before the spawn Future resolves**:
  an isolate whose spawn completes after cancellation is killed;
- is idempotent; canceled results can never update the opened reader;
- does not start/stop any provider, cloud request or voice playback.

The helper `prepareEpubReader(path)` remains available as a
backward-compatible one-shot Future for callers not using cancellation.

The `ReaderScreen` maintains a monotonically increasing load epoch.
On a reload it cancels the previous preflight; on widget disposal it
cancels the worker and invalidates pending operations. After every
await (EPUB extraction, voice list/configuration and checkpoint save)
a stale generation returns without replacing the active player.
Provisional `ReaderPlayer` and `NarrationRecoveryBinding` instances
are disposed on failed/stale loads; only the successfully installed
player is retained. An old asynchronous load cannot overwrite a
newer user's preferences, active narration or source position.

The worker catches errors and sends fixed machine-readable categories
for corrupt/unsafe EPUB input and missing files. It deliberately does
not forward raw exception text, filenames, book contents, private
device paths, tokens or provider credentials. The worker has no SQLite,
native speech, Flutter widget, or network access. On success,
`Isolate.exit` transfers ownership of the extracted result to the
reader, avoiding the usual deep copy of a large model.

**Scope:** this is active cancellation of the *EPUB background
preflight worker*. If a foreground, already-entered synchronous cast
preparation is running, Flutter cannot interrupt that synchronous
function until it yields; it will not install a stale result after a
new load can run. Other independent PDF/TXT decoding operations are
not newly cancellable.

## Stage measurements (local-only)

The worker records monotonic `Stopwatch.elapsedMicroseconds` for:

| Stage | Definition |
|---|---|
| Read ZIP bytes | Local file size/byte read, including 100 MiB check |
| Extract XHTML source | Safe ZIP extraction, OPF/NAV/NCX, content, metadata |
| Initial speech segments | Source-aligned spine segmentation |
| Dialogue regions | Source-verified quotation grouping |
| Paragraph boundaries | Paragraph hard-boundary scanning |
| Worker preparation total | From worker entry to final model ready |

The reader additionally records the main-isolate time spent on
cast and progressive layout preparation, voice/reader setup, and
end-to-end wall-clock time from the start of the `_load` attempt
until its reader state is ready. An epoch-guarded post-frame callback
also records the **first completed reader frame** after the book opens.
These durations are **not CPU times or FPS**; inter-isolate transfer,
scheduling and UI operations may make their totals differ from simple sums.

The `EPUB opening performance` speedometer button in the reader
opens a passive, local modal with durations (milliseconds), ZIP byte
count, Unicode source code units, spine item count and initial speech
segment count. Only numeric, fixed-schema data is displayed.
Nothing is stored in SQLite, uploaded to GitHub, exported via
telemetry or sent to a cloud API. The button is available only for
successfully opened EPUBs.

The first completed reader frame is now timed as well, but **peak
resident memory, frame-rate and per-paragraph scroll jank are not
measured yet**.
Measure them during final Windows/Android profiling rather than
claiming performance improvements from these durations.

## Tests authored but unexecuted

- `test/data/epub_reader_preflight_test.dart` adds three cases
  verifying the nonnegative, numeric stage report; immediate
  cancellation / double-cancellation before spawn completion; and
  isolation between two simultaneous preflights.
- `test/features/epub_opening_performance_sheet_test.dart` adds two
  widget cases checking numeric rows, scrollable report content,
  close interaction and zero-duration handling.
- The previously authored worker-vs-direct EPUB test cases remain in
  place for source/quote/boundary equivalence, invalid files and
  multiple spine items. The active reader path still uses their
  established canonical source and original voice attribution APIs.

Before release run the local Windows runner with the complete
Flutter analyzer/test suite, and manually close/reopen an EPUB during
preflight on Windows and Android. Test overlapping reloads,
large ZIPs, out-of-memory/slow devices and errors during voice
provider initialization; verify there are no orphaned speech
sessions or isolates. Run on-device profiling separately.

See [Background EPUB Preparation](EPUB_BACKGROUND_PREPARATION.md),
[Implementation Status](IMPLEMENTATION_STATUS.md) and
[Windows Test Runner](../test-results/README.md).
