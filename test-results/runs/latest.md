# EReader — Local Test Report

* Result: **FAIL** (partial run, interrupted by timeout)
* Source: d08e6e4 (feature/m0-flutter-foundation)
* Run: 20261027T153000Z-ereader-local-run

* Cases: 626 passed, 45 failed/errors, 0 skipped

## Stages

| Stage | Result |
|---|---|
| flutter pub get | PASS |
| flutter analyze | INFO_ONLY (411 lint/info, no blocking errors) |
| flutter test (full suite) | PARTIAL_TIMEOUT — stopped at +626 -45 |
| audio-specific (wav_decoder_race, sherpa_vits_engine, sherpa_vits_session) | 39 passed, 6 failed |
| offline_vits_soak (500 iterations) | PASS |

## Audio Failures

| Test | Issue |
|---|---|
| sherpa_vits_engine: changed speed waits for unfinished speculative synthesis | assertion mismatch |
| sherpa_vits_engine: dispose during synthesis suppresses late playback | PathAccessException temp file lock |
| sherpa_vits_engine: invalid prepared WAV is discarded | assertion mismatch (empty list) |
| sherpa_vits_engine: one-ahead local synthesis | assertion mismatch (empty list) |
| sherpa_vits_engine: stop discards completed lookahead WAV | PathAssertion + path mismatch |
| sherpa_vits_session: two sequential WAVs | PathAccessException temp file lock |

## Soak Test

PASS — 500 iterations, 500 syntheses, 50 warmed WAV reuses, 0 unreleased WAV files.

## Notes

Full suite was interrupted by a 10-minute timeout on `offline_voice_manager_widget_test.dart` (Windows file lock on temp dir). Individual test files passed up to that point. Compilation errors exist in some test files (desktop_drop API mismatch, const StateError, missing offlineVoiceStatistics, PreparedCastSpeech) but do not affect the majority of the suite.
