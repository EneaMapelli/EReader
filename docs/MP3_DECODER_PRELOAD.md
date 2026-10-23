# MP3 warm decoding on Android and Windows

**EReader source increment — 23 October 2026.** Implemented on `feature/m0-flutter-foundation` but **not yet compiled, run or listened to on devices**. This is an opt-in extension of the previous cloud synthesis lookahead; native system TTS is unchanged.

## What changes

Cloud synthesis lookahead can retrieve the next OpenAI MP3 while the current voice is playing. Until now, the next clip still had to be written to a private temporary file and handed to a native `just_audio` decoder at the moment of playback. That load/decode step can add latency.

`JustAudioMp3Output` now keeps **two reusable `AudioPlayer` instances**, one for current serial playback and one for loading the next already-synthesized MP3. The standby player calls `setFilePath` and `setSpeed` ahead of time. Once the current clip completes, the next `play` reuses the loaded idle player without repeating file preparation. It does **not** start playback on the standby player before its turn.

Only the immediately following clip can occupy the standby slot; different future clips are ignored until that slot is consumed or invalidated. A changed playback speed or unexpected clip discards the stale warm slot, clears its temporary file and allows later warm-ups.

## Exact activation and charging boundary

- The existing **Prebuffer one cloud audio chunk** checkbox is explicitly OFF for each reader session; merely selecting OpenAI, opening a book or enabling cloud permission does not prebuffer.
- The already-consented OpenAI Speech engine synthesizes the next text only after the current audio is ready, respecting book consent, private key, quota and its one-future-clip limit. When and only when those MP3 bytes exist, the new optional `PreloadableSynthesizedAudioOutput` interface may warm the secondary **local decoder**.
- Decoder preloading sends **no additional network request** and reserves **zero additional OpenAI characters**. The prior optional speculative cloud synthesis can still cost money for unheard text; its separate upfront disclosure remains intact.
- Cached MP3 bytes or newly synthesized bytes may be warmed. An MP3 decoder preparation failure is nonfatal: playback uses the same downloaded/cached bytes via a normal cold load rather than sending a new cloud request.
- The original source text, UTF-16 offsets, narrator/character identity, read-along position and sequential order do not change.

## Lifetime and cleanup

- Original MP3 bytes remain under the private cache behavior. Decoder working copies use uniquely named `.mp3` files in the platform-provided temporary directory, never a public Music folder.
- Stop, seek, pause and dispose invalidate prepared work through the engine/output generation token, stop the active/standby decoders and attempt to erase their private files. A platform file-lock deletion failure is retained for retry after the handle is released.
- The current decoder releases its file handle after a clip ends and before removing its working file. A decoder still loading when Stop occurs is not allowed to start a stale clip.
- Changing speed, voice or text before consuming a prepared clip cannot reuse an incompatible warm decoder. No separate thread or native audio buffer is left playing after the reader stops.

## Why this is not a gapless guarantee

`just_audio` 0.10.x supports sequential audio sources and platform-dependent playlist transitions, and the installed Windows backend offers playlist support. EReader deliberately **does not claim gapless audio** here: it uses separately awaited clips for per-segment read-along and progress, and actual output switching, MP3 encoder padding, buffering and audio-focus interactions may still create audible gaps. A decoder can be loaded without guaranteeing all PCM frames are decoded in advance. Achieving truly gapless dialogue would require a carefully aligned audio playlist/stream, synchronized segment boundary events and real-device measurements.

## Source implementation and tests (written, not run)

- `lib/audio/mp3_playback.dart`: optional `PreloadableSynthesizedAudioOutput`; two reusable `Mp3Decoder` backends with local standby load, private temporary MP3 file handling, source/speed matching, serialization, stop/dispose invalidation and testable factory injection.
- `lib/audio/openai_speech_engine.dart`: after one ahead cloud synthesis succeeds, optional decoder warm-up of the **same** bytes and next-voice playback speed; a native warm-up error cannot trigger another paid synthesis.
- `test/audio/mp3_preload_test.dart`: **8 unexecuted tests** for idle standby preparation, single replay without reloading, no prefetch before Play, one bounded standby, speed mismatch recovery, Stop/dispose cleanup, in-flight-load cancellation and invalid clip validation.
- `test/audio/cloud_prefetch_test.dart`: existing **7 unexecuted mocked cloud integration tests**, extended with an assertion that the prepared cloud MP3 is handed to the decoder warm-up capability. HTTP and audio output remain mocked; no paid network call is made by tests.

## Deferred release gates

Run Dart formatter/analyzer and all Flutter tests, native Windows and Android builds, and manual/audio-driver tests for switching time, app backgrounding, read-along synchronization, revocation, unexpected interruptions, Windows file locks and stale temporary files. Do not advertise zero-gap output without measured evidence.