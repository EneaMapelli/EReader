# EReader — Local Test Report

* Result: **FAIL** (partial run — timeout on one widget test, pre-existing audio race)
* Source: 9392c6a (feature/m0-flutter-foundation)
* Run: 20261027T170000Z-ereader-local-run

## Summary
- flutter pub get: PASS
- flutter analyze: PASS (no errors; only info/warnings of style)
- flutter test test/audio/: 44 passed, 1 failed
- flutter test test/features/offline_voice_manager_widget_test.dart: TIMEOUT after 10 minutes
- flutter test tool/offline_vits_soak_test.dart (500 iterations): PASS

## Audio Test Failure

| Test | Issue |
|------|-------|
| sherpa_vits_engine_test.dart: changed speed waits for unfinished speculative synthesis | `Bad state: Future already completed` + `PathAccessException` on Windows temp file deletion (errno 32). Pre-existing race condition, unrelated to the `desktop_drop`/`file_picker` alignment. |

## Code Changes

| File | Change |
|------|--------|
| pubspec.yaml | `desktop_drop: ^0.9.2`, `file_picker: ^3.0.4` |
| lib/features/reader/offline_voice_manager_screen.dart | `FilePicker.platform.getDirectoryPath()` (removed `dialogTitle` no longer supported in file_picker 3.x) |
| lib/features/library/library_screen.dart | `FilePicker.platform.pickFiles()`, `selected.files` access, `File(item.path!).openRead()` instead of removed `readAsByteStream`, `FilePicker.platform.getDirectoryPath()` |

## Notes

The timeout on `offline_voice_manager_widget_test.dart` is a known Windows temp file lock issue (`PathAccessException` errno 32), not a logic failure in EReader. The single audio test failure is the same pre-existing race condition observed in previous runs.
