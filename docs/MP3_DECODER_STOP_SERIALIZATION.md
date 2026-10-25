# MP3 decoder Stop and cleanup serialization

Increment: 2026-10-25. Development branch:
`feature/m0-flutter-foundation`.

## Observed risk

The two-slot MP3 output formerly invalidated the playback generation but
immediately invoked `decoder.stop()` and deleted temporary audio files
on both decoders. If the idle warm decoder was still in
`setFilePath`, Stop and file deletion could overlap that asynchronous
native load. On Windows the file may remain locked; on either supported
platform a late native load could outlive an apparently completed Stop.
A rapid subsequent play could also race against that old cleanup.

## New ownership rules

- Each decoder slot has a single promise chain, `slot.loading`, covering
  native loads, end-of-clip finalizers and Stop/cleanup. New loads await the
  previous slot operation, so an old session cannot stop a new one on the
  same physical decoder.
- Each `_load` tracks `loadingInFlight` until the file write and native
  load settle. A generation change does not delete a file until its native
  loading callback has actually returned.
- `stop()` invalidates pending audio immediately, queues Stop/cleanup for
  both decoders and **awaits the active decoder's Stop**. If the standby
  decoder is in a pending load, its cleanup is deferred behind that load
  without blocking the active Stop; it never plays the warmed clip.
- If standby loading is already complete, Stop also awaits standby cleanup.
  `dispose()` waits for all deferred slot operations before disposing native
  decoders, and retries temporary-file cleanup after native disposal.
- A physically stuck native active decoder can still block its own
  `stop()`; the enclosing `ReaderPlayer` retains its existing native
  Stop deadline and fail-closed behavior. A physically stuck idle decoder
  can delay `dispose()`; it must not be freed while still loading.

No new network call, cloud permission, cache key or payable prefetch is
introduced. The existing *one clip ahead* consent policy remains unchanged.
A queued idle cleanup may outlive `stop()` until the native decoder load
resolves; therefore an instantly empty temporary directory is not claimed
for a deliberately hung idle decoder.

## Authored regression cases

`test/audio/mp3_preload_test.dart` now checks that no native Stop overlaps
a deliberately delayed warm `load()`, Stop waits for an actively loading
decoder before calling its native Stop, and disposal waits before releasing
a warm decoder. Existing reused-file, old-finalizer and speed-change
cases are retained.

**Not yet executed on Windows or Android:** the published current test
report remains `NOT_RUN`. Re-run `tool/run-all-tests.ps1` after pulling
the latest branch; native behavior additionally requires device validation.

## Deferred deletion and invalidated prebuffers (2026-10-25)

If the OS refuses private MP3 deletion with a `FileSystemException`, the
path now moves into an in-memory deferred-deletion set instead of being
lost when the decoder slot starts another clip. After disposing **both**
native players, the output retries the pending deletions. A limit of 64
previously locked files blocks new loads rather than allowing an
unbounded local-file buildup; files already in an active slot can add a
small constant to this bound. Persistent filesystem errors cannot be
magically overridden by Dart and still require OS cleanup.

Discarding a mismatched prebuffer now routes through the exact same
serialized per-decoder Stop and file cleanup used by normal playback,
and checks its generation before acting. A concurrent new prefetch
cannot acquire the slot while the discard is pending. Multiple callers
of `dispose()` now receive the same cleanup Future rather than
mistaking a started disposal for completed native teardown.

The MP3 deletion adapter is injectable exclusively for deterministic
filesystem-lock regression tests; production uses the ordinary private
file deletion API. New unexecuted tests cover failed deletion recovery,
failed warm-load followed by another warm-load, and concurrent disposal.
No changes to TTS network requests, user consent, or quotas. Current
Windows/Android build and test validation remains **NOT_RUN**.
