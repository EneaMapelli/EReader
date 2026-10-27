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

## Mismatch-safe lookahead handoff (2026-10-27)

A changed speed or different next audible segment must never race a
still-running speculative synthesis on the same persistent native worker.
The audible `speak` method now waits for any prior lookahead (even if
its text or settings do not match) before invoking native inference.
Only an exact-match WAV is claimed; mismatched private WAVs are deleted
and the correct passage is then synthesized. Stop/Dispose generation
checks continue to suppress delayed playback. New tests cover a
completed wrong prediction and an in-flight wrong-rate prediction.
No Dart/Flutter tests or native builds were executed here.

## In-app, local-only performance counters (2026-10-27)

An experimental offline voice exposes a **read-only** expansion tile in
the reader settings. It displays, per engine instance: number of native
model loads, completed WAV syntheses, speculative generations and reused
WAVs, failures/cancellations, last/mean synthesis time, rolling P95
(last 64), last speak-to-decoder *handoff*, and the most recent sampled
**whole-process RSS**. No text, book title, file path, audio, voice ID
or key is stored or exported. There is no analytics SDK, HTTP or upload.

The handoff timestamp is recorded BEFORE calling the audio output
decoder. It is NOT first audible sample latency and does not measure
acoustic gaplessness. The RSS number is an OS snapshot of the complete
Flutter process, NOT peak RAM or bytes attributable to ONNX.
The running sample window is bounded (64 numbers); averages represent
only successfully completed native/model syntheses. Compare with a
real stopwatch/audio recording on Windows before claiming performance gains.

Tests verify counters, P95 bounds and copy-on-read snapshots, but have
not been executed in this GitHub-only editing environment.

### Interface linkage regression

The ReaderPlayer imports the diagnostics value type explicitly rather
than relying on Dart's non-transitive imports. An additional engine mock
test checks the counter is exposed through the speech provider interface.
The tests were authored but not executed in this editing environment.

## WAV decoder native-operation serialization (2026-10-27)

The previous WAV output adapter could call native Stop or Dispose while
`AudioPlayer.setFilePath` was still pending on the **same decoder**.
Windows can retain its temporary WAV handle in that situation. The
refactored `JustAudioWaveOutput` serializes native load, Stop and
Dispose against one physical decoder, but does NOT queue the duration of
audible playback: Stop can still interrupt an already-playing WAV.

Cancellation increments the output generation synchronously. Once a
pending file load finishes, an obsolete request cannot start audio.
After **normal** playback completion, explicit decoder Stop precedes
the engine's private WAV deletion. Native load failure also attempts
Stop before exposing the original failure. A stale playback finalizer
never stops a newer generation.

The injectable `WaveDecoder` contract allows independent tests for
slow load + Stop, slow load + Dispose, ordinary completion, rapid
Stop/replay and native load failure. All are authored, not executed.
If a native load itself hangs, Stop waits on the load and
ReaderPlayer's existing 8-second Stop guard deliberately blocks
unsafe re-entry; native preemption remains a device-level gate.

## Failed-Stop obligation (2026-10-27)

A partially failed `setFilePath` can leave a Windows decoder holding the
prior file. The WAV adapter now tracks a conservative native Stop
obligation from BEFORE each load until physical Stop succeeds. If a
native Stop fails, the obligation survives the error. A later Play
must retry Stop **before** loading a different WAV, and fails closed if
Stop is still unconfirmed. Disposal remains serialized behind outstanding
native operations. An extra synthetic regression exercises two failed
Stops followed by recovery, without using device audio.

## WAV lifetime while native Stop is pending (2026-10-27)

Even when the output generation is cancelled, the obsolete
`JustAudioWaveOutput.play` Future must not resolve merely because the
interrupted `setFilePath` or `AudioPlayer.play` returned. It now awaits
the queued native Stop/Dispose operation so that the owner engine's
finally block cannot try deleting its WAV ahead of the file handle
release. Delayed native Stop is still subject to ReaderPlayer's existing
Stop-confirmation timeout, which fails closed rather than overlapping
audio. Added synthetic tests where decoder Stop intentionally remains
pending after native load or playback reports completion.

## Bounded WAV cleanup after Windows file locks (2026-10-27)

The prior best-effort staging deletion silently forgot a private WAV
folder on `FileSystemException`. The VITS engine now uses
`OfflineWavCleanup`, a per-engine, in-memory queue of ONLY the exact
temporary directories created for completed local speech jobs.

- Deletion on normal completion is still immediate.
- Locked staging folders are retained for later deletion; a small
  bounded retry batch (4) runs before creating subsequent WAVs.
  Failed entries rotate so permanently locked files do not starve
  recoverable entries.
- After confirmed native Stop, at most 2 pending directories are retried;
  after decoder Dispose, up to 32 are retried. No cleanup ever occurs on
  an active WAV solely because its path happens to match a temp prefix.
- When 32 directories remain blocked, a new audible synthesis fails closed
  rather than creating unlimited private files. Speculative lookahead
  silently skips when capacity is exhausted.
- The numeric pending-folder count is visible in offline diagnostics.
  Source text, private paths, audio bytes and cleanup failures are not
  logged, persisted, sent externally or displayed.

Temporary paths are never scanned by name: only directories explicitly
handed to this helper after ownership has ended can be deleted.
Unexpected symlink/regular-file replacements are not traversed.
The queue lasts only for the current engine process; if Windows retains
files until AFTER app exit, on-next-launch stale cleanup remains a
separate, guarded feature (not claimed here). Native Windows host
tests must confirm file-lock behavior and actual cleanup success.

Added fake-lock, rotation, backpressure, concurrent-retry, isolation
and engine integration tests; authored, NOT EXECUTED.

## Crash-safe, lease-guarded private WAV recovery (2026-10-27)

Only new VITS synthesis directories use a versioned, **per-reader** temp
session under the system temp root. The session has an exact EReader
marker and a dedicated native **exclusive file lock** held for its
lifetime, including active/suspended syntheses. On initial VITS
activation, EReader runs a bounded scan of direct temp-root entries
(max 512 scanned, max 16 candidate sessions, max 64 WAV clips in each).
It must obtain the session's **non-blocking exclusive lease** before
considering any file for recovery: an active Windows process owns that
lock, so its WAVs are never removed by a second reader process.

Recovery is deliberately restricted to folders matching this version's
session prefix, its exact marker contents, regular lease file and only
regular `speech.wav` files inside known per-clip directory prefixes.
Unknown files, child directories and symlink replacements fail closed,
without recursive deletion. Deletions are only of exact allowlisted
files and their now-empty immediate parent directories. Native file
locks that still prevent deletion leave the marked directory for a
subsequent attempt. No private paths, content or metrics are uploaded.

Normal Dispose keeps the session's lease until its last native WAV
staging-owner finalizer has finished. After a confirmed cleanup it drops
the marker, closes the file lock and removes empty session metadata.
If Windows still holds a WAV, the marked directory remains recoverable.

**Compatibility:** legacy pre-v1 temporary WAV directories lack this
ownership/lease evidence, so they are NOT automatically deleted. A
file system cannot reliably prove the ownership of arbitrary unmarked
temp files. Windows native tests must still validate platform lock
semantics and process-crash recovery before treating this as qualified.

### Same-process lease safeguard

An additional in-memory registry protects live WAV session directories
inside the same Dart isolate/process, since some POSIX advisory record
lock implementations are process-scoped. OS-exclusive file locking still
protects separate processes; both checks must pass before recovery.
The registry contains only private staging directory paths and is never
exported, persisted, printed or uploaded.

## Interrupted metadata cleanup and concurrent scan hardening (2026-10-27)

A normal close may crash AFTER removing the marker but BEFORE removing
the empty lease-file metadata. The recovery pass now recognizes exactly
one exceptionally narrow unmarked layout: a version-prefixed directory
containing only its regular, EMPTY lease file. It obtains the same
exclusive OS lock, revalidates the layout, and removes that empty
metadata. **Unmarked WAV directories remain untouchable**, even when
they use familiar audio folder names. Unexpected files, non-empty
leases, symlinks and arbitrary directories are skipped.

A same-process candidate guard also prevents simultaneous recovery
passes from racing to unlock/delete the same directory. close() is
single-flight: concurrent dispose callers wait for its actual lock
release. Failure to enumerate individual temporary files is
best-effort cleanup rather than a reason to fail new VITS playback.
Five additional tests cover metadata interruption, unmarked WAV
preservation, unexpected files, concurrent scans and repeated close.
No Dart/Flutter test execution or native Windows builds occurred.
