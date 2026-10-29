# Source checkpoint alignment and merged speaker/punctuation pauses

Date: **2026-10-29**. Branch: `feature/m0-flutter-foundation`.

## Observed integration gap

The prior Windows interpreted-punctuation adapter remembered a finished
sentence's final punctuation pause, but waited for it **inside** the next
`SystemSpeechEngine.speak()`. `ReaderPlayer` had already called
`onSegmentStarted()` at that point, persisting the next reading offset and
advancing the visual highlight **before** the next text was audible.
On an actor/narrator voice change, the player also waited separately for
the configured extra pause, leading to two consecutive delays.

Previously, the new segment's checkpoint could also be written while
`chooseVoice` was still awaiting its native platform response.

## Fix

A small optional **`PreSegmentSpeechPause`** engine contract now
lets `ReaderPlayer` wait *before* a new source checkpoint.

For `SystemSpeechEngine` only:

- If Windows interpreted-punctuation mode has a completed preceding
  clause, `WindowsSpeechPauseCarry.takeForTurn()` consumes its terminal
  punctuation pause **exactly once**.
- If the cast changes **both the confirmed speaker and the installed
  voice**, the reader requests the configured 0–2000 ms speaker breath.
- The actual wait is **max(punctuation, voice turn)**, never the sum.
- For Windows native-punctuation comparison and Android system TTS,
  no punctuation tail is introduced: only the optional voice-turn pause
  applies when a genuine cast voice change happens.
- Every wait is cancellable by Stop/Seek/Dispose before the new
  `onSegmentStarted` callback or TTS synthesis.
- A native character/narrator `chooseVoice()` now also completes
  **before** the checkpoint and highlight. A superseded delayed selection
  cannot checkpoint or speak an abandoned segment.
- For callers invoking `SystemSpeechEngine.speak()` directly outside
  `ReaderPlayer`, the existing punctuation-tail fallback still works.
  `SpeechSessionRestartAware` continues clearing stale carry on
  explicit replay after natural EOF.

The text, UTF-16 offsets, approved cast regions, EPUB note filters,
visual layout blocks, bookmarks and next-audible recovery policy are
unchanged. No per-word highlight/timing claim is introduced: an active
highlight still covers a full source-aligned TTS segment. Native
platform calls can introduce some residual latency after the checkpoint,
so word-perfect alignment is outside this milestone.

## Long dialogue safety and performance

Coalescing still caps an attributed quote to each provider's **400-character**
chunk policy by default; it does **not** merge whole chapters, span
paragraph/note boundaries or send previously unread cloud text.
Within an approved long quote, the same installed actor voice is reused
across contiguous chunks without requesting redundant voice changes
or extra turn pauses. A real speaker+voice change at the two edges
still receives exactly one merged pause per edge.

## Regression cases authored

- `test/audio/pre_segment_speech_pause_test.dart` (six tests):
  ordered pre-speech gap / native voice selection / checkpoint / speak,
  Stop during a delayed gap, Stop during voice selection, skipped notes,
  same voice across differing labels, and a long approved character
  quote with one checkpoint and completion for each source-aligned chunk.
- `test/audio/windows_speech_punctuation_test.dart`: two additional
  pure carry tests for max-vs-additive gaps and cleared/cancelled tail.

The tests were **written, not executed**: this connected environment does
not include Flutter/Dart. Native speaker timing, voice catalogs and
listening quality remain acceptance gates. No Windows/Android build,
GitHub Actions or paid cloud TTS call was launched.

## Manual acceptance when builds are explicitly requested

Read a multi-paragraph dialogue using two installed Windows voices,
with both plain quotes and exclamation marks at voice changes.
Verify that source highlights do not jump to the next line during a
preceding punctuation pause, that Stop/Seek while a voice switches
cannot commit unheard text, and that actor→narrator restores the
original voice exactly once. Compare `system` interpreted-punctuation
mode with the `system-native` A/B mode, and repeat with Android
system TTS if relevant.

## Follow-up: overlap the native speaker switch with its silent breath

The earlier sequential flow (**wait for silence**, then **choose native
voice**) is optimized: both start after the previous spoken segment has
finished, and the next `onSegmentStarted` checkpoint is made only
after **both** operations have succeeded. This limits transition
latency to the slower operation rather than their sum, without
compromising interruption safety. A Stop/Seek invalidates the
playback token; the old choice is still serialized with subsequent
voice changes. [Details](LONG_DIALOGUE_HANDOFF_OPTIMIZATION.md).
