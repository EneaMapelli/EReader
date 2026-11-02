# MP3 decoder Stop and temporary-file lifetime

2026-11-02 — `feature/m0-flutter-foundation` — draft PR #1

## Background

The OpenAI/cloud TTS backend plays cached or newly synthesized MP3 data
through `JustAudioMp3Output`, using private, temporary audio files. Its
physical native decoders operate separately from `ReaderPlayer`'s logical
source cursor. In particular, an interrupted `setFilePath` call can have
opened a native Windows audio handle **even when the Dart Future has not
completed**.

Before this correction the MP3 slot's `_load` used a `finally` clause
that deleted the temporary file as soon as a canceled native
`decoder.load()` returned. The queued Stop for the same decoder executes
**after** that load, so file deletion could precede physical
`decoder.stop()`. On Windows this may fail with a sharing violation and
retain an orphaned private audio file; it also violates native cleanup
ordering.

A related failure path tried to remove the MP3 even when a failed native
load was followed by an **unconfirmed/failed Stop**, potentially deleting
the source still held by the native player.

## Implemented lifecycle

- `JustAudioMp3Output.stop()` immediately changes its generation,
  invalidating old playback, synthesis-ready and warm-load callbacks.
- A canceled generation still holds the private MP3 via its
  decoder-specific `_Mp3Slot.file`. The ongoing `_load` does **not**
  unlink the file after returning from `setFilePath`.
- The queued `_stopSlot` waits for native load to complete, then awaits
  physical `decoder.stop()` and only afterward deletes the MP3.
- If native `decoder.load()` **fails**, its exception handler still
  attempts Stop immediately. It now deletes the file only when Stop was
  confirmed. If Stop also fails, `needsNativeStop` and `slot.file`
  remain intact for the next successful Stop or decoder disposal.
- The existing decoder-disposal path awaits the slot's serialized
  native operations, disposes physical decoders, and then retries private
  file cleanup. No persistent document, progress, cloud request or
  additional TTS synthesis is created.

This changes only the MP3 output's temporary-file lifecycle, not the
native OS speech-engine voice controls or local VITS/WAV decoding.

## Regression tests authored

Changes to `test/audio/mp3_preload_test.dart` now cover:

1. Cancellation during active decoder `setFilePath`: hold native load,
   initiate Stop, release load, hold decoder Stop, and ensure deletion
   remains blocked until the physical Stop completes.
2. The same sequence on a speculative warm/standby decoder while the
   active decoder stops independently. Warm audio must never start.
3. A failed load followed by failed native Stop: the private MP3 must
   remain available until the next successful Stop and then disappear.
4. Previously present tests remain relevant for dispose while loading,
   stale playback finalizers, duplicate Stop, bounded prebuffering,
   native Stop failures and deferred Windows-file-lock cleanup.

The tests have been committed but **not run**: Flutter SDK/native audio
plugins are unavailable in this environment. Actual file-lock behavior
must be verified on Windows, ideally with repeated Stop/Seek during a
slow decoder setFilePath call. Android audio-resource cleanup and offline
VITS remain separate regression checks. No GitHub Actions or Windows
build were launched; PR #1 stays draft pending validation.
