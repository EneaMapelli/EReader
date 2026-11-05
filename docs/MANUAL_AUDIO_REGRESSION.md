# Manual audio regression verification — Windows and Android-host Flutter

Status: **prepared, not executed**. The development branch is
`feature/m0-flutter-foundation`, currently reviewed through PR #1.
No workflow is triggered by a push, PR, schedule, or this document.

## Why run this

Numerous source-level fixes now guard native TTS Stop, retired-engine
Dispose, Android audio focus, delayed cloud consent and media controls.
Their regression tests are **authored but not yet verified at the current
branch HEAD**. A previous, older Windows suite cannot be used as proof
these new changes pass.

## Manual GitHub Actions entry point

Use **Actions → EReader manual cross-platform verification → Run workflow**.
Select the `feature/m0-flutter-foundation` branch in the workflow-run
branch selector so the modified workflow definition is used.
Set `git_ref` to the exact 40-character commit SHA being verified.
Choose `scope`:

- `audio` (default): focused host-level regression tests on Ubuntu
  (Android project generated, no APK built) and Windows 2022
  (Windows project generated, no desktop binary built).
- `full`: the full Flutter test suite on both runners plus Android
  debug APK and Windows desktop debug build, as before.

If the web UI displays an old input schema from the default branch,
select the feature branch first. A GitHub CLI equivalent, when the
GitHub account has permission to dispatch Actions, is:

```sh
gh workflow run manual-verify.yml \
  --ref feature/m0-flutter-foundation \
  -f git_ref=REPLACE_WITH_40_CHARACTER_COMMIT_SHA \
  -f scope=audio
```

This command is for **manual use**, not a command run by the assistant.
Never use the moving branch head as evidence for a previous workflow run;
record the exact checked-out SHA from the run.

## What the audio scope actually covers

The same five Flutter test files run under **both** host operating
systems, not on an Android phone:

1. `test/audio/native_stop_timeout_test.dart`
2. `test/audio/reader_media_handler_test.dart`
3. `test/audio/narration_recovery_binding_test.dart`
4. `test/audio/rapid_playback_navigation_test.dart`
5. `test/audio/segment_completion_barrier_test.dart`

Each runner also performs `flutter pub get`, an **advisory,
non-mutating** `dart format --output=none --set-exit-if-changed lib test`
check, and `flutter analyze`. The analyzer executes even if tests fail,
so an assertion/compilation error does not suppress analyzer evidence.
The historical repository-wide formatting backlog is reported but does
not block tests; it does not reformat tested source. Test or analyzer
failures are **hard failures** of the job.

The `audio` scope deliberately skips native APK/Windows compilation and
does not prove real device audio behavior. No raw logs, book content,
database or secrets should be committed to the repository.

## Acceptance / escalation

1. Both jobs must pass all selected tests **and** the analyzer at the
   exact same SHA. Record run URL, SHA, per-job result and any failing
   test file/name without sensitive fixture payloads.
2. If the targeted suite fails, fix the source or test and run again
   against the new SHA. A previous green run does not validate later edits.
3. Only then run `scope=full` and diagnose the complete test suite,
   Android build and Windows build independently.
4. Separately test on **real Android hardware**: headphones/noisy events,
   incoming call, lock-screen Pause/Play/Skip, rapid book replacement,
   TTS Stop with delayed native callback, sleep timer, close/reopen and
   no automatic resume after interruption.
5. Separately test Windows actual voice playback, focus/release behavior
   and app close/reopen. Host-level Flutter mocks cannot prove native TTS.
6. Keep PR #1 as draft until build/device evidence and release gates
   genuinely pass.

Known limitation: Flutter/Dart SDK and network access are unavailable
in the assistant's local environment, and this GitHub integration has
no workflow-dispatch action. Therefore no test result or device-level
qualification is asserted simply because this workflow exists.
