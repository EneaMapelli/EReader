# Configurable dialogue turn pause — free system TTS

Date: 2026-10-29
Branch: `feature/m0-flutter-foundation`.

## User-facing behavior

Inside a book, open the reader's voice controls. With either free
`system` or Windows `system-native` selected, **Dialogue pause** appears
beside the speed and pitch settings.

- **Off (0 ms)** disables the extra transition breath.
- **110 ms** remains the default for the existing experience.
- The slider covers 0–2000 ms; changes affect **future** transitions without
  restarting or skipping the currently speaking sentence.
- The choice is saved for this book, using the existing serialized
  `SpeechPreferences` value in SQLite. **Save as global default** saves
  the current value for other books without their own override.
- **Use global defaults for this book** deletes the per-book override and
  restores the global pause immediately after the current TTS is stopped.

A turn pause occurs **only** after an actually finished segment when the
speaker changes **and** the resolved installed voice changes. Multiple
characters using the same installed voice do not pay this latency, and
normal narrator sentence boundaries are unaffected. Stop/Seek/Dispose
cancel an in-progress breath before any new recovery checkpoint.

Cloud speech and experimental local neural speech never receive this pause.
No AI request, API charge, model download or native build is triggered by
the new setting.

## Persistence compatibility

`SpeechPreferences.toJson()` adds optional
`dialogueTurnPauseMs` to the existing JSON version 1. No SQLite migration
or change to existing voice IDs is needed. Version-1 settings written before
this feature, without the new property, read as 110 ms. Invalid types
(fractional, string, boolean), negative durations and durations longer than
2000 ms are rejected rather than silently truncated.

The in-memory `ReaderPlayer` defaults to a zero breath when directly
constructed by low-level clients, as before. The real reader explicitly
initializes its pause from persisted `SpeechPreferences`. Its setter
reconfigures the subsequent transition timer, not the audio already playing.

## Regression checks written (not executed)

- `test/domain/speech_preferences_test.dart`: JSON round-trip, old profile
  default, `copyWith` preserving or turning off the setting, malformed
  payloads and range checks.
- `test/audio/dialogue_turn_breath_test.dart`: setting Off while narrating,
  switching to a nonzero future pause, invalid/microsecond values, plus
  existing Stop/Seek/Dispose and narrator/cast transition cases.
- `test/data/dialogue_pause_preferences_store_test.dart`: global and
  per-book precedence, clearing per-book override, reopen persistence.

These are authored regression cases, **not verified Flutter test passes**.
The connected environment does not have Dart/Flutter installed. Native
Windows/Android speaker switching and perceptual timing remain acceptance
gates; no GitHub Actions or platform builds were launched.
