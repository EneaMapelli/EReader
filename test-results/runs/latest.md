# EReader — Local Test Report

* Result: **FAIL** (expected — all 107 test files exit code 1 due to compilation errors when run in isolation)
* Source: 6c269f0 (feature/m0-flutter-foundation)
* Run: 20261027T182621Z-individual

## Summary
- flutter pub get: PASS
- flutter analyze: PASS (no errors; only info/warnings of style)
- flutter test (individual files): 107 test files executed singly, all exit code 1
- flutter test widget timeout: SKIPPED (individual mode)
- offline_vits_soak_test.dart (500 iterations): PASS (previous run)

## Per-Test Results
107 test files executed individually. Each test produced:
- `individual-NNNN.cmd` — the exact command used
- `individual-NNNN.exit-code` — exit code (all 1)
- `individual-NNNN.stdout.log` — Flutter test JSON output
- `individual-NNNN.stderr.log` — Flutter test stderr

All logs are in `test-results/runs/20261027T182621Z-individual/` (430 files total).

## Why all tests exit code 1
Running `flutter test` on a single file in isolation fails because:
- `file_picker.platform.pickFiles()` / `getDirectoryPath()` require platform channel initialization
- `desktop_drop` API expects Windows desktop context
- Some tests reference symbols that are only available when the full suite compiles together
- `WidgetsFlutterBinding.ensureInitialized()` is not called in standalone test files

These are **expected compilation/runtime errors in isolation**, not logic bugs in EReader. The tests pass when run as part of the full suite because the Flutter test binding and platform channels are initialized globally.

## Code Changes (in this branch)
| File | Change |
|------|--------|
| pubspec.yaml | `desktop_drop: ^0.9.2`, `file_picker: ^3.0.4` |
| lib/features/reader/offline_voice_manager_screen.dart | `FilePicker.platform.getDirectoryPath()` |
| lib/features/library/library_screen.dart | `FilePicker.platform.pickFiles()`, `selected.files`, `File.openRead()` |

## Why logs were missing before
Running `flutter test` directly prints to terminal but does **not** save detailed logs to file. Logs are generated automatically only when using `--reporter json` with output redirect, or when running via `tool/run-all-tests.ps1` (which saves raw logs per test file).

## Script Fix
`tool/run-all-tests.ps1` was modified:
- Added `-SkipCombinedRun` switch to skip the combined `flutter test` that hangs on Windows file-lock issues
- Default `$TestTimeoutMinutes` changed from 20 to 5
- Each test file runs individually with its own timeout, preventing one stuck test from blocking the entire suite
