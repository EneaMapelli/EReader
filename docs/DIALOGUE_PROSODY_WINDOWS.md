# M2/M4 — Dialogue punctuation and short voice-turn breaths

Date: **2026-10-29**. Branch: `feature/m0-flutter-foundation`.

## What changed

Windows **System — interpreted punctuation** narration now treats standalone
double/curly/guillemet quotation marks as short speech phrase boundaries,
instead of joining a quote directly to surrounding dialogue tags.

Examples of the *audio-only* phrase plan:

| Source (unchanged in book) | Spoken phrases | Pauses between |
| --- | --- | --- |
| `«Vieni» disse Elena.` | `Vieni` / `disse Elena` | 140 ms |
| `“Vieni!” disse Elena.` | `Vieni` / `disse Elena` | 420 ms (not 420 + 140) |
| `Disse "seguimi" e si mosse.` | `Disse` / `seguimi` / `e si mosse` | 140 ms each |
| `— Buongiorno, Èlia.\n— Vieni qui… per favore!` | Four spoken spans | Comma / sentence / ellipsis pauses |

A quotation mark does **not** become a spoken symbol. Ordinary decimal
numbers, times, titles and word apostrophes retain their special handling.
Parentheses and brackets continue to separate words without introducing
a new speaker pause. An exclamation/question/full stop immediately before
a closing quote retains its original, longer pause: pauses are not added
together. The `system-native` A/B variant intentionally remains unchanged,
and neural/cloud text is left untouched.

## Pauses at actual character turns

Source segmentation may place a quoted sentence and its dialogue tag in
separate `SpeechSegment` objects. A phrase's terminal punctuation pause
does not cross that boundary because it belongs to a separate speech call.

The real reader now opts in to a **110 ms** cancellable breath on installed
OS/system TTS, only when all these conditions hold:

1. The previous source segment finished speaking normally.
2. The *actually audible* speaker changes (including actor → narrator).
3. The newly resolved **installed** speech voice is also different.

There is **no additional breath** between consecutive narrator sentences,
two characters using the same installed voice, a missing/stale character
voice falling back to the narrator, or cloud/offline-neural engines.
A skipped EPUB footnote does not erase the previous audible speaker.
The default `ReaderPlayer` API remains `Duration.zero`; the 110 ms
policy is explicitly selected by the reader screen only for
`system` and `system-native`.

The pause runs **before** the source start checkpoint for the new segment.
Pause/Seek/Dispose cancel the pending timer immediately and invalidate its
playback session. The next unheard segment is not checkpointed, spoken or
sent to a provider after cancellation. Source text, highlights, cast labels,
reading anchors and progress remain unchanged.

## Regression coverage and limits

- `test/audio/windows_speech_punctuation_test.dart`: four new source
  examples, including unpunctuated quotes, closing punctuation and
  dialogue dashes.
- `test/audio/dialogue_turn_breath_test.dart`: seven cases with injected
  fake TTS: narrator → character → narrator, mid-breath Stop, Seek and
  Dispose, identical voice across two speaker IDs, non-system provider
  gating, skipped notes.

The source and test files have been committed; **Flutter/Dart test execution
and real-platform audio listening were not performed in this session**.
No Windows/Android native build or GitHub Actions were started.

Naturalness is perceptual, not established by source-level checks. In a
future user-requested Windows/Android test, compare the two system modes
with the same Italian excerpt, evaluate actual voice switches,
contractions/apostrophes, pause rhythm, Stop/Seek under load and whether
110 ms feels too short or long. Some third-party voices may still vocalize
symbols despite phrase filtering. Cloud and neural engines have their own
prosody and should not reuse these punctuation transformations blindly.
