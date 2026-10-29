# M4 — Voice/language handoffs for character dialogue

Date: 29 October 2026 · branch `feature/m0-flutter-foundation`

## Behavior

EReader already stores source-accurate, user-approved speaker spans and
provider-scoped character voice assignments. The ReaderPlayer now treats the
resolved **installed voice** as the source of pronunciation locale only when
it was explicitly assigned to that character. Example:

| Source turn | Selected installed voice | Language passed to speech |
| --- | --- | --- |
| Italian narrator | Narrator IT | Book language: `it-IT` |
| English dialogue | Actor EN (`en-US`) | `en-US` |
| Spanish dialogue | Actor ES (`es-ES`) | `es-ES` |
| Back to narrator | Narrator IT | Book language: `it-IT` |

This changes *audio synthesis inputs only*. Source text and UTF-16 offsets,
bookmarks, highlights, accepted cast annotations, checkpoint semantics,
database settings and voice preferences stay the same.

If an assigned character voice was removed from the installed provider
catalog, EReader already falls back to the narrator voice and now also
retains the book language. Provider-wide `multi` voices, including OpenAI
Speech voices, retain the book language instead of forwarding an invalid
`multi` language identifier.

The next **audible** cloud or offline lookahead chunk receives the language
that will be used at playback time, alongside its next resolved voice.
Paid speculative lookahead remains *disabled by default* and this change
does not request cloud speech or alter consent/quota policies.

## Race protection

Asynchronous native calls to `chooseVoice` caused by narrator/character
handoffs share one serialized sequence with explicit narrator selections.
When a Play is superseded by Pause, Seek or another voice selection, a late
`chooseVoice` completion cannot mark the old choice as valid for the next
session. That next session waits for the old native voice operation to settle,
then reapplies the correct installed voice before speaking. No new audio may
be synthesized until the previous Stop gate and voice selection are resolved.

This is not native sample-accurate gapless speech and does not introduce
post-synthesis character pitch changes or automatic gender inference.

## Acceptance

Added `test/audio/cast_voice_handoff_test.dart`, covering:

- Narrator → English character → Italian narrator recovery
- Two character languages (English/Spanish) in a single Italian book
- Uninstalled/stale character voice fallback and book locale
- Provider-wide `multi` voice behavior
- Opt-in next cloud prefetch voice/language snapshot with an entirely fake
  engine (no billing or real requests)
- Delayed character voice change superseded by Seek; verifies one native
  voice-selection operation at a time and no stray spoken dialogue

**Tests authored, not executed** in this GitHub-connected session.
Real Windows/Android TTS engines may differ in how they handle switching
language+voice; test with actual installed multilingual voices and repeated
Play/Pause/Seek. No GitHub Actions or native builds were invoked.
