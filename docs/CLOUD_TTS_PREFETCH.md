# Cloud TTS one-chunk lookahead: synthesis prebuffer, billing and safety

**2026-10-23 source increment — NOT compiled or run.** On-device Flutter, native Windows/Android and real provider audio tests remain deferred by owner instruction. PR #1 remains draft.

## Motivation and honest limits

EReader already coalesces adjacent chunks from one quoted turn with the same voice, up to 400 UTF-16 code units. Long quotations can still take multiple cloud-synthesis requests. Waiting for the next remote request after the current audio ends creates an avoidable network latency gap.

This increment adds **a single MP3 synthesis request ahead of playback** for the selected OpenAI cloud engine. It can overlap HTTP synthesis/cache writes for the next segment with playback of the current segment. It does **not** implement gapless MP3 playback, overlapping audio output, live streaming, crossfade, WAV stitching, local synthesis for the OS engine, phoneme alignment or guaranteed continuous prosody.

## Explicit session opt-in

- The Reader controls now show **Prebuffer one cloud audio chunk** only when OpenAI Speech is selected.
- The checkbox is **OFF by default** on every new reader session. Enabling cloud consent or choosing a paid provider does not enable speculative lookahead.
- The UI warns that preparing an *uncached* subsequent passage can transmit it to OpenAI and reserve billable character quota **before the reader reaches or hears it**, even if paused, skipped or closed. This additional cost falls under the existing per-book cloud consent/character budget; it is not an exact monetary charge cap.
- The app never prebuffers until the reader has actively pressed Play and the current cloud clip has completed synthesis and is ready to start audio output. If the current clip fails before playback, the next one is not requested.
- Disabling the checkbox stops **new** lookahead scheduling. A previously submitted/potentially billed request may finish and its audio can be reused when playback reaches it, avoiding a second synthesis charge. Pause/seek/stop invalidates the active generation and suppresses old audio playback; network requests already in flight may nevertheless be charged.

## Architecture

- `AheadOfTimeSpeechEngine` is an optional speech-engine capability. Native `SystemSpeechEngine` does not implement it, so system voices continue their existing serial speech path.
- `ReaderPlayer` schedules at most **one** immediately following chunk after calling the active cloud engine's speak method. It passes the original pronunciation-transformed TTS text and the resolved, available **next** character/narrator voice without altering the current output voice. Progress, source offsets and display are untouched.
- `OpenAiSpeechEngine` guards the future request with a current-audio-ready completion gate, a generation token, exact immutable next voice and the same per-book opt-in, secure API key, private MP3 cache, SHA-256 model/voice/text cache key, attempted-character reservation and 20 MiB response limit as normal synthesis.
- Only one prepared clip is retained. Normal speak for that exact voice/text consumes its pending result without a second HTTP call or quota reservation. A failed lookahead is reported when that next passage plays; it is **not** automatically retried at additional cost.
- The audio output remains serial through a single `JustAudioMp3Output`. Voice changes and narrator restoration still happen only when the resolved installed voice differs from the previous voice.
- Before playing even a completed prefetched clip, the engine checks book consent again, so revocation fails closed instead of silently skipping the passage.

## Test coverage (authored, not executed)

`test/audio/cloud_prefetch_test.dart` contains **seven** tests using a deferred HTTP fake, output gates, fake secure vault, private in-memory cache and mock quota access. They check no paid lookahead by default; only-after-active-audio-ready gating and single next request; immutable next-character voice; no automatic duplicate charge after an HTTP error; revocation between preparation and playback; suppression of stale clips on pause/seek; and no next request when initial rendering fails.

## Release caveats

Pre-rendering audio can move cost earlier in time and may leave paid clips unused after interruption. A local quota is not an exact financial cap. The MP3 output can now load the next private temporary file on a second, idle native decoder while the current clip plays, if cloud prebuffering is enabled. This can shorten the native file-loading delay, but separate clips, audio-focus transitions, codec padding and driver behavior can still create audible gaps. Native OS TTS speech engines cannot be safely pre-rendered through this abstraction. These behaviors must be measured on actual Windows and Android devices before changing the default or advertising gapless audiobook playback.

**Final integration remains pending:** Dart format/analyze/test; Windows/Android builds; mock race tests on a real runner; remote quota and consent UI smoke tests; actual multi-character audio handoff and pause/seeking timing.

## Local MP3 decoder warm-up

The same explicitly authorized, one-ahead cloud clip can now also be loaded into a second **idle native MP3 player** before it is heard, using the *already paid or cached bytes*. This does not reserve more quota or send any additional text to OpenAI. Playback remains one clip at a time. Pauses, seek and stop invalidate unused prepared audio, and files remain private temporary copies. Details and tests: [MP3 Decoder Preload](MP3_DECODER_PRELOAD.md). **Gapless audio is not yet demonstrated.**


## Navigation and settings session guards

Rapid overlapping source seeks and native voice selections now use session epochs and serialized Stop/voice operations. The last user navigation command wins; a paused reader cannot be resumed by an obsolete request. The current segment is restarted after speed/pitch/language edits are committed, invalidating old MP3 warm-up. Prebuffering remains explicitly session-optional and OFF by default. See [Playback Session Safety](PLAYBACK_SESSION_SAFETY.md). No extra cloud calls were added by these safeguards; already transmitted requests may still incur charges.

## 2026-10-26 — cached-only warmup, no paid prefetch required

The new `CachedAheadSpeechEngine` independently prepares an already cached
private MP3 on the second idle decoder. It is **ON by default** for OpenAI
Speech and can be disabled separately in Reader controls. A cache miss never
runs an API request, fetches credentials or reserves billable quota; only
ordinary explicitly played speech may do so. A live current-audio-ready gate,
generation invalidation and per-book consent still apply.

Paid synthesis prefetch remains **OFF by default**, with its unchanged
explicit opt-in and cost warning. Both paths now find the next **audible**
chunk beyond source-verified, user-skipped EPUB footnotes; no skipped note is
prefetched. The active decoder still emits clips serially. Neither mode
guarantees gapless playback. [Implementation and manual QA](CACHED_AUDIO_WARMUP.md).
Tests were authored but **not run**.
