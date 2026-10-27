# M3 — one-ahead offline VITS WAV synthesis (2026-10-27)

## Why

Previously, every source segment began expensive native ONNX model synthesis
only AFTER the preceding WAV finished playing. On Windows this creates a
potentially long silent transition due to repeated model initialization.

## Implementation

- \`OfflineAheadSpeechEngine\` is a separate local-only interface. It has
  no HTTP, secrets, cloud consent, remote text upload or character billing.
- Once current VITS synthesis is complete, at most ONE next native WAV may
  be produced while the current clip is being played.
- ReaderPlayer chooses the next ACTUALLY audible segment; source-verified
  skipped footnotes do not consume a speculative synthesis slot.
- The WAV is accepted for playback only for the exact matching
  text/language/rate/pitch/installed pack voice.
- An already warmed WAV is reused (no redundant next synthesis).
- Pause/Stop/Seek/Dispose invalidate generation and cancel the native
  worker where possible. A late native/mock result cannot start speech.
- Every private WAV uses a temporary per-clip directory, cleaned after
  playback or invalidation. Windows decoder handle contention remains a
  known native constraint; the previous best-effort delete policy is kept.
- The reader has a session-only "Prepare next offline voice clip" toggle,
  ON by default for the manually selected experimental VITS provider.
  It can be disabled when CPU/RAM/battery use matters.

## Limits and acceptance

The engine still loads the ONNX model per job, with native worker startup.
The lookahead hides some of that work behind playback, but does NOT
implement a persistent model session, gapless audio, Android VITS support or
a quantified latency improvement. Real CPU, memory, model size, cancellation,
Windows WAV file handles and speech quality require host measurement.

Regressions authored for one-ahead reuse, Stop during/after preparation,
private file cleanup, and ReaderPlayer skip/disable behavior. NOT EXECUTED:
this GitHub editing session has no local Dart/Flutter native toolchain.
No Windows build and no GitHub Actions triggered.

## Native Stop priority

The Stop/Dispose operation invalidates speculative work immediately and
first awaits native output Stop/Dispose before attempting deletion of an
already prepared future WAV. Private-file cleanup must not hold up audible
Stop. If native worker cancellation is delayed, stale synthesis is still
generation-blocked from playing; device-level cancellation timing is an
outstanding acceptance gate.

## 2026-10-27 — resident ONNX isolate

The production VITS adapter now creates one `VitsPersistentSession` per
uninterrupted reading session: the worker initializes sherpa/ONNX once and
processes sequential speech/WAV requests through one native model.
This is complementary to the existing one-ahead local WAV warmup.

Stop, Seek, Pause and Dispose terminate that worker instead of retaining
native memory after the user stops listening. The next explicit Play
initializes a new model. A native worker error also invalidates the
session and surfaces a sanitized error; no book text or local paths are
included. Existing one-utterance jobs remain available for the isolated
qualification CLI and test-injected native workers.

New pure-Dart isolate tests exercise reuse, ordering, cancellation,
backpressure and engine wiring, but have NOT been executed. This is not
proof of Windows native ONNX correctness or a measured latency gain.

## Worker life-cycle and bounded resource use (2026-10-27)

The persistent model isolate now has distinct bounded deadlines:
**60 seconds to initialize**, **3 minutes per WAV request** (including
startup if still pending), and **3 minutes idle** after an initialized
model has no outstanding request. Idle retirement releases the ONNX
isolate after a finished book or a prolonged silent interval.
The native output may still be playing a previously rendered WAV:
idle retirement never interrupts that output or changes a bookmark.

Every accepted next request cancels the idle timer. A failed startup
or timed-out native generation invalidates the model and reports
a sanitized error rather than waiting indefinitely. The next normally
scheduled request after idle retirement creates a fresh model automatically.
Stop/Seek/Dispose remain immediate generation invalidations.

Synthetic timers/isolate regressions were written but not run. These
are *logical* timeouts; exact native FFI preemption, actual working-set
memory reclamation and perceived audio latency require Windows tests.
