# Long dialogue handoff optimization — EReader

Date: 2026-10-29
Branch: `feature/m0-flutter-foundation`

## Audible improvement

Long manually cast dialogues consist of source-aligned chunks, limited
to the provider's existing 400-character budget. During a
narrator→character or character→narrator transition, the previous
system TTS sequence waited for the carry-over punctuation pause and
then waited **again** for the native voice selector. Both waits happened
before the next recovery checkpoint, ensuring source safety but
creating an unnecessarily long silence on slow Windows voices.

After the previous clip finishes, `ReaderPlayer` now starts these
two independent operations **concurrently**:

- `PreSegmentSpeechPause.waitBeforeSegment()` consumes a completed
  Windows punctuation pause and the configured extra speaker breath;
  it still chooses the **maximum**, never adds them.
- `_choosePlaybackVoice()` applies the installed actor/narrator voice
  through the existing serialized native selection queue, only if the
  selected voice really changes.

`Future.wait` waits for **both** operations before the new
`onSegmentStarted`, `activeSpeakerId` notification and
`SpeechEngine.speak`. The next segment cannot be highlighted or
checkpointed while either operation remains pending. A cancelled
session's token is invalidated immediately, and late native operations
cannot start an obsolete clip. This reduces the transition waiting
time toward the slower of the two tasks, without assuming device
latency, guaranteeing zero gap, or changing source offsets.

## Single-resolution cast locale

Previously, the code separately called
`castVoiceForSegment(segment)` when choosing the installed character
voice and when deciding which language to send to the engine. The
callback is often backed by an editor-derived mapping. If it changes
during playback, these separate calls could disagree, selecting one
character's voice with another character's locale.

Now `_resolveVoiceAndLanguage` evaluates the cast resolver once per
chunk and returns one pair of `SpeechVoice?` and `spokenLanguage`.
The same policy is used for the next permitted cloud or local
lookahead chunk; live playback re-resolves its own snapshot when it
actually reaches the chunk. The existing narrator fallback,
`multi` voice semantics, voice validation and cloud-consent gates
remain intact.

## Regressions authored

- `test/audio/pre_segment_speech_pause_test.dart`: concurrent gap
  and native speaker selection; release either operation first;
  checkpoint must wait for both; Stop during both prevents
  any unheard clip. Existing long-dialogue case still checks exactly
  two real voice switches and one source checkpoint per chunk.
- `test/audio/cast_voice_handoff_test.dart`: an adversarial cast
  resolver that changes voice on a second call, stale voice fallback
  with a single lookup, and one coherent per-lookahead voice/locale
  snapshot without real paid synthesis.

The tests **were not executed** because Dart/Flutter is unavailable
in this session. No Windows/Android build or GitHub Actions was
launched. Native listening, user-visible smoothness, and timing under
rapid Stop/Seek must still be verified on real hardware before these
improvements qualify as validated product behavior.
