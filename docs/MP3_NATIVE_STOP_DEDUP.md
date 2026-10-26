# M2 — Native MP3 Stop de-duplication and partial-load recovery

_Date: 2026-10-26. Implementation authored on GitHub; tests and real-device audio not yet executed._

## Why this matters

Every cold MP3 playback previously called native `Mp3Decoder.stop()`
before `setFilePath()`, even if the decoder had **never started playing**,
or a previous clip finalizer had **already awaited and confirmed** Stop.
This adds an avoidable native round trip during successive audio clips,
particularly when there is no warm standby MP3 in the private cache.

The output still calls Stop **after** actual clip completion and before the
same decoder is reused. This increment never plays two clips concurrently,
removes the end-of-clip Stop, or permits a new load while an old Stop is
unconfirmed.

## Implementation

- `_Mp3Slot.needsNativeStop` starts false only for a newly constructed
  decoder. It is set true **before** awaiting native `load` (which may
  partially open a file even if it throws).
- `_load` serializes behind every previous operation on that physical
  decoder. It calls Stop only when the flag remains true; it clears the
  flag **only after** Stop confirms success. Reusing a previously finalized
  decoder therefore avoids the old second native Stop.
- Natural `play` completion retains a mandatory serial Stop, then clears
  the flag before private working MP3 cleanup. The next MP3 cannot reuse
  that decoder until this finalizer resolves.
- If native `load` throws, Stop is attempted **before** deleting the
  working file. If Stop fails too, the flag remains true and the next
  load/explicit Stop must retry. Windows file locks still use the existing
  deferred-deletion behavior.
- Explicit Stop, Seek, Pause and Dispose retain session generation checks,
  cleanup barriers and conservative stop semantics. A stalled native
  decoder blocks reuse of that decoder; an unrelated warmed decoder cannot
  be made audible before prior clip playback completes.
- The existing two-slot MP3 buffer, per-book consent, paid vs cached-only
  prefetch controls, SHA-256 cache keys and TTS character accounting are
  unchanged.

This is a latency optimization for unnecessary native control calls, **not**
a claim of gapless playback or better audio focus compatibility.

## Manual Windows/Android acceptance

1. Run `tool/run-all-tests.ps1` locally. Target
   `test/audio/mp3_preload_test.dart` in particular; the added fake-decoder
   cases confirm exactly one Stop per successful clip, no initial Stop on
   a fresh decoder, and no duplicate Stop on a clean subsequent load.
2. Simulate a native load failure and a load failure followed by Stop
   failure. Verify retries do not reuse an unconfirmed native handle and
   that temporary files are removed or deferred safely.
3. Replay a cached multi-speaker book with the free **cached MP3 warmup**
   enabled/disabled. Compare human-perceived pauses at ~20 transitions
   and at chapter boundaries, alongside a sequence of cold cache misses.
4. Repeat rapid Pause/Play, Seek, speed/voice changes, sleep timer, native
   background/lockscreen and headset interruptions. Validate narrator voice
   restoration, no audible overlap, and no Windows stale MP3 handles.
5. Capture device timings, decoder and audio-focus errors only after actual
   native runs; neither performance percentages nor latency reduction in
   milliseconds can be asserted from unexecuted mock tests.

## Newly authored regression coverage

Extended `test/audio/mp3_preload_test.dart` to check initial/cold/warm
Stop counts, partial native load recovery, failed Stop retention, and a
deliberately delayed native Stop barrier. All other source/offset,
cache-consent, quota and player lifecycle tests remain applicable.

**Release gate:** No Flutter SDK/native Windows/Android toolchains in this
repository editing environment; no test execution, formatter, analyzer,
native audio capture or timing measurement occurred here.
