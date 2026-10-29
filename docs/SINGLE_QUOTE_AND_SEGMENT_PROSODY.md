# Windows free TTS — literary single quotes and cross-segment prosody

Updated: 2026-10-29. Branch: `feature/m0-flutter-foundation`.

## Why

EPUB dialogue often uses quotation marks which are **not** double curly or
`«…»`. The previous quote-region parser did not recognize `‘…’`,
`‹…›`, or German `„…“`. The Windows interpreted-punctuation profile also
forwarded some of these glyphs unmodified, so certain installed voices
could speak their literal symbol names.

A second issue occurs when a fully spoken quote ends in a punctuation mark
and its dialogue tag belongs to another source-accurate TTS segment.
Punctuation pauses were applied *only between phrases inside one segment*.
The final punctuation breath was lost when the next segment began.

## Changes

1. The **source-preserving** `splitQuotedSegmentsWithRegions` parser now
   recognizes `‘…’`, `‹…›`, `„…“` as additional primary quote styles.
   Apostrophes within words (for example `I’m`, `l’acqua`) do not
   close a curly-single quote. ASCII straight-single quote **speaker
   attribution is intentionally unsupported**: apostrophe ambiguity makes
   automatic speaker boundaries unsafe.
2. Nested different-style quotations remain in the **same outer quote
   group**. The app never invents a second character or voice for an
   embedded quotation; only a reviewed, accepted source-hashed cast label
   can activate a voice.
3. The Windows **System — interpreted punctuation** phrase planner
   filters standalone single curly/guillemet/ASCII quote marks and inserts
   a short speech-only breath around them. Word apostrophes stay intact.
4. `SystemSpeechEngine` carries the **final pause of a successfully
   completed segment** into the next actual speech segment. For example,
   `«Vieni!»` followed by `disse Anna.` retains the question/exclamation
   pause instead of concatenating the two calls. No trailing silent
   utterance is added at the end of the book.
5. Pause/Seek/Dispose invalidate and clear the carried delay. Explicit
   playback **after natural EOF** also clears it through the optional
   `SpeechSessionRestartAware` hook (no extra native Stop), so the previous
   book-ending punctuation cannot delay the first replayed sentence.

The existing **configurable 0–2000 ms voice-transition breath** remains
distinct from punctuation phrasing; both can contribute when an actual
narrator/character voice switch also coincides with terminal punctuation.
The UI lets the user turn the extra voice breath Off. Precise audio cadence
depends on real Windows voices and has not yet passed listening tests.

## Scope and guarantees

- The book source string, UTF-16 reading offsets, accepted cast spans,
  highlights and bookmarks are unchanged. Only speech planning changes.
- No guessed characters or automatic gender inference are introduced.
- No cloud request, paid prefetch, voice model download or API charge is
  introduced by these rules.
- Android's system native prosody, Windows `system-native`, local VITS and
  cloud audio inputs remain unchanged.
- This is not general Unicode quote parsing: ambiguous punctuation and
  malformed/nested same-style quotation still require manual cast review.

## Test coverage authored (not executed)

- `test/audio/windows_speech_punctuation_test.dart`: straight and
  typographic single quotes, contractions, nested quotes, carry
  consumption and Stop/empty-plan clearing.
- `test/domain/dialogue_segmenter_test.dart`: source-exact extra
  quotation styles, separate turns, lexical apostrophes and nested
  quote boundaries.
- `test/domain/single_quote_cast_continuity_test.dart`: accepted quote
  across many TTS chunks, no invented nested speakers.
- `test/audio/windows_punctuation_continuity_test.dart`: fake-engine
  end-to-end planning across quoted text and its dialogue tag, EOF
  restart, Seek/Stop boundary.

All files were committed, but **Flutter/Dart tests were not executed**
in the connected environment. The final Windows audio rhythm still
requires manual user testing with installed voices. No native build or
GitHub Actions were invoked.


## Follow-up: source-start alignment and non-additive speaker breath

The cross-segment punctuation carry described above is now consumed
**before the next segment's visual/recovery checkpoint**, using
`PreSegmentSpeechPause` on the system TTS adapter. A simultaneous
installed voice change uses `max(punctuation, voice-turn pause)`
rather than two serial waits. Stop/Seek/Dispose still cancel the
pending wait. Native voice selection also finishes before the new
highlight/checkpoint. See
[LONG_DIALOGUE_CHECKPOINT_ALIGNMENT.md](LONG_DIALOGUE_CHECKPOINT_ALIGNMENT.md).
