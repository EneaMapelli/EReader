# Race-safe persisted speech preferences

Date: 2026-10-29
Branch: `feature/m0-flutter-foundation`

## Problem

`ReaderPlayer.applyPreferences()` was invoked by the reader during initial
book setup and when choosing **Use global defaults**. It called
`SpeechEngine.chooseVoice` **directly**, while playback and the explicit
voice picker already serialize native voice operations through
`_pendingVoiceChange`.

This creates a race when a user changes books/defaults during a slow
native `chooseVoice` call. The older callback can complete last and
leave the OS TTS adapter with a voice that does not match the displayed
preferences. Another hazard was a pending auto-resuming Seek that could
restart narration after restoring paused preferences.

## Implementation

- Validate provider and settings before touching playback.
- Increment the existing navigation generation; cancel auto-resume intent.
- If currently playing, stop its audio before changing the provider's
  voice. Always await an in-progress native Stop barrier; never
  configure while a Stop is unconfirmed.
- Join the same `_pendingVoiceChange` queue as narrator/character handoffs
  and explicit picker selections.
- After queued work finishes, only the **newest, non-disposed** settings
  request may call `chooseVoice`.
- Once the winning voice operation returns successfully, commit the
  requested `SpeechPreferences` fields to `ReaderPlayer` and notify the
  UI. On failure, invalidate the native voice cache and propagate the
  error while retaining the previously displayed rate/locale/voice.
- A stale native completion invalidates the cached key so that any later
  playback explicitly reapplies its chosen voice.
- Applying preferences while paused stays paused; interruption leaves the
  source segment position unchanged. No source hash, character label,
  checkpoint, cloud request or TTS cache key is rewritten.

The existing default-voice fallback is unchanged. Directly selecting a
system default when **no explicit installed voice** is requested is not
implemented by this change because some platform TTS backends do not
provide a reliable cross-platform reset-to-default method.

## Regression cases authored

`test/audio/rapid_playback_navigation_test.dart` adds:

1. A slow manual voice selection superseded by a saved per-book profile.
2. Two overlapping saved profiles: only the newest settings commit.
3. Applying preferences during active speech stops the current clip
   without automatically resuming it.
4. Applying preferences while an auto-resuming Seek awaits native Stop
   cancels that Seek without changing source position.
5. An invalid provider is rejected before mutating playback state.
6. A rejected native voice selection preserves the old preferences and
   allows a subsequent explicit successful retry.

In addition, the dialogue-pause constructor initialization was corrected
to use a regular named parameter instead of an invalid
`this.dialogueTurnPause` formal aimed at a getter; three dialogue tests
were made non-`const` when using the computed length of a source string.

**No tests were executed** in this tool environment; no native builds or
GitHub Actions were triggered. A Windows/Android run is still needed to
validate actual engine behavior and race timing.
