# Offline VITS / WAV: native Stop before file-release recovery

Updated 2026-11-02 · `feature/m0-flutter-foundation` · draft PR #1

## Why this change was necessary

The offline Sherpa VITS speech engine uses one private per-utterance WAV
folder and optional one-ahead synthesized WAV. A native decoder load
may open a Windows WAV file handle before a Dart Future completes.

Previously, `SherpaVitsSpeechEngine.stop()` released a **ready** next
WAV from the filesystem in its `finally` clause even when the
output driver's `stop()` failed. A failed decoder Stop does not prove
that its native file handle was released.

A related lifetime issue applied to an output `play()` exception and
to a canceled speculative `prepareNext()` that might have reached
native loading. The old finalizers could release the source WAV
without a confirmed stop/dispose.

## Implemented file ownership

- `_decoderHeldStaging` retains only paths to folders this engine
  explicitly created. It contains no audio bytes and does not access
  unrelated temporary directories.
- `stop()` immediately invalidates old synthesis/preload generations,
  as before. Only after `_output.stop()` returns successfully does it
  release previously held WAVs and a ready prepared WAV.
- Failed native Stop retains the ready speculative WAV; another
  successful Stop may release it safely. A failed output Play/handoff
  similarly holds the current utterance WAV until confirmed Stop.
- If the speculative decoder preload was attempted and then canceled
  or failed, its WAV remains held because a native handle may exist.
  A later successful Stop or decoder disposal releases it. A warm-up
  that was canceled before decoder loading can be removed immediately.
- Final `dispose()` releases held WAVs only when the output's native
  disposal succeeds. If native disposal fails, the engine still closes
  its OS lease but retains a **marked private WAV session** for guarded
  bounded recovery on a later application launch, rather than deleting
  a file potentially held by a failed decoder.
- Source segments, reading positions, paid APIs, the speech queue,
  book checkpoints and narrator preferences are unchanged.
  Local offline WAV synthesis is the only provider affected.

## Regression tests committed, not executed

`test/audio/sherpa_vits_engine_test.dart` now includes mocked native
failure/latency coverage for:
1. A ready one-ahead WAV after failed Stop, followed by successful
   Stop cleanup.
2. A warmup that completes its decoder-load Future only **after** the
   failed Stop. Its WAV must not be deleted or played.
3. Failed output Play, retaining an apparently open WAV until Stop.
4. Failed output Dispose, retaining the WAV inside a marked
   recovery-eligible session until another process can safely recover.

Earlier `wav_decoder_race_test.dart`, `offline_wav_cleanup_test.dart`
and VITS session tests remain required. The tests have only been
authored; no Flutter SDK or native Windows/Android runtime has run here.

## Manual acceptance

1. Start local VITS on a long EPUB, then repeatedly Pause/Play and
   skip chapters during active WAV playback and one-ahead warmup.
2. Abort during native WAV decoder load; confirm no later audio
   starts and private folders disappear only after Stop confirmation.
3. With a simulated decoder Stop failure, confirm no immediate
   deletion of the WAV that the decoder may still hold.
4. Close/reopen after an interrupted session and confirm the bounded
   marked-WAV recovery removes stale folders only when their OS lease
   is free; verify no other files under temp are touched.
5. Repeat on Windows with the WAV physically open through the decoder,
   and on Android with native audio focus. Measure whether frequent
   interruptions create temp-folder accumulation or audio overlap.
6. Verify old visual/audio cursor ownership, TTS speech generation,
   bookmarks and explicit Follow narration preference remain stable.

No GitHub Actions or Windows builds were started. PR #1 remains a
draft pending Flutter and native execution.
