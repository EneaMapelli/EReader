# M2 — Local-only cached cloud MP3 warmup (2026-10-26)

## Purpose and default

An OpenAI Speech book can use its **already rendered private MP3 cache** to
prepare a subsequent decoder while the current clip plays. This is separate
from the older paid, one-ahead synthesis prefetch:

| Action | Default | HTTPS/character reservation | Audio output |
| --- | --- | --- | --- |
| Warm next cached MP3 | **ON** | **None** for the warmup; cache miss does nothing | Local idle decoder loads, does not play |
| Synthesize next missing MP3 | **OFF** | May reserve and send the next passage; needs per-book consent | Local idle decoder loads the returned bytes |
| Normal playback on cache miss | On explicit Play | Uses ordinary per-book quota/consent | Plays serially when the segment is reached |

The user can disable cache-only decoder warmup with
**Warm already cached cloud audio** in the reader. No persistent setting,
database migration or new permission is introduced. Audio produced by earlier
cloud narration remains private; disabling warmup does not erase cache files.

## Implementation

- `CachedAheadSpeechEngine` is separate from
  `AheadOfTimeSpeechEngine`, so implementation can never silently fall back
  from cache-only warmup to speculative paid synthesis.
- `OpenAiSpeechEngine.prepareCachedSpeech` requires a successful current
  audio-ready gate, a live generation, current book consent, and the exact
  SHA-256 model/voice/text cache key. It queries only `SpeechAudioCache.read`.
  **On a miss it returns without key access, quota reserve or HTTP.**
- A cache hit retains the original `Uint8List` identity for
  `JustAudioMp3Output.prepareNext` and subsequent `play`, allowing the
  same warmed decoder to be consumed with no reload. Native warm failure
  returns the SAME cached bytes to the ordinary cold playback path.
- `ReaderPlayer` finds the next *audible* source segment rather than blindly
  preparing index+1. It bypasses arbitrarily many consecutive source-verified
  EPUB footnote chunks when the user has opted into skipping them. At most
  **one** subsequent audible chunk is prepared per active segment. No skipped
  note is submitted to either cached or paid lookahead.
- The existing paid prefetch feature remains separate, session-only,
  default OFF. If enabled, it has priority for that one next audible chunk.
  A note skipped in narration does not itself trigger any cloud request.
- Stop/seek/dispose invalidate active and future audio generations.
  A delayed private cache read cannot install a stale warmed clip after
  cancellation, and the decoder's existing per-slot native operation
  serialization remains unchanged.

### Limits

- Private cached audio must already exist for the **exact** selected model,
  character voice and original pronunciation-transformed text. Speech rate
  is applied locally at playback and matches the warmed decoder speed.
- Re-reading a missing cache entry is slightly more disk I/O; it does not
  imply an extra cloud synthesis or a lower provider fee.
- A user-approved paid prefetch can still incur quota for the next **audible**
  chunk if it is not cached, even if the reader later pauses.
- Cached speech still requires the book's cloud-playback consent at playback.
  Revoking consent blocks it, even if the MP3 is on disk.
- No native audio timing measurements, gapless playback, cache hit-rate
  measurements or cross-device audio validation are claimed.

## Regression tests authored (not executed)

The extended `test/audio/cloud_prefetch_test.dart` exercises cache hits,
cache misses, disabled cache warming, character-voice cache keys, speed,
multiple skipped notes, paid prefetch of the next audible chunk,
revocation, and Stop racing a pending cache read. Existing MP3 native decoder
race tests remain in `test/audio/mp3_preload_test.dart`.

## Manual validation — Windows and Android

1. Run `tool/run-all-tests.ps1` locally and review results.
2. Select OpenAI Speech and authorize the book explicitly. Read a few short
   segments to populate its private cache and pause.
3. Replay them with **Warm already cached cloud audio** ON and paid cloud
   prefetch OFF. Confirm that only the CURRENT uncached passage can trigger
   HTTP and billed characters; replayed passages should be cache hits.
4. Toggle cache warmup OFF to compare clip transition timings. Repeat with
   narrator + at least two manually assigned characters, different speeds
   and a verified skipped EPUB footnote.
5. Exercise Pause, rapid Seek, Stop, background audio focus loss and consent
   revocation. Verify no overlapping playback, stale cached clip or orphan
   temporary MP3 files.
6. Independently enable paid prefetch in a separate small-budget test and
   verify its fee warning still applies. Do not conflate this with cache-only
   preparation.

**Status:** committed source/docs/unit tests; Flutter analyzer, unit tests,
native Windows/Android builds and real audio measurement have NOT run in this
GitHub editing session. PR remains draft.
