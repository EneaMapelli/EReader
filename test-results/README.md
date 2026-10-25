# EReader — Windows test reports on ONE branch

Run tests on a Windows workstation and publish their **sanitized outcomes**
to `feature/m0-flutter-foundation`. No additional Git branch, worktree, PR
or automated cloud test runner is required.

## First run

Open **PowerShell** in your local EReader checkout:

```powershell
git switch feature/m0-flutter-foundation
git pull --ff-only origin feature/m0-flutter-foundation
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1
```

The command uses your existing `git`, `dart`, `flutter` and
**GitHub push credentials**. It does not ask for or store a token.
Windows PowerShell 5.1 or newer, Flutter/Dart and Git on `PATH`
are required. Keep the tracked working tree **clean before starting**
or publishing will be refused (tests may still run).

## What runs

1. `flutter --version` and `dart --version`.
2. `flutter pub get` (omit with `-SkipPubGet`).
3. Non-mutating `dart format --output=none --set-exit-if-changed lib test`
   (omit with `-SkipFormat`).
4. `flutter analyze --no-pub`.
5. `flutter test --reporter json --no-pub` for the entire test suite.
   If this fails or times out, run **every** `test/**/*_test.dart`
   individually to identify failures and isolate suites that cannot
   load. The runner continues after errors, including compiler errors
   and file timeouts. The full suite and each isolated file default to
   a 20-minute limit; override both with `-TestTimeoutMinutes 30`.

**No APK, Windows executable, Android device or release build is
performed by this script.** Those are separate integration gates.

## Files written

```text
.local-test-results/              # PRIVATE; ignored by Git
  <UTC-run-id>/
    flutter-analyze.stdout.log
    flutter-analyze.stderr.log
    flutter-test-all.stdout.log
    flutter-test-all.stderr.log
    individual-0001.stdout.log    # if the full suite fails
    ...
    summary.json
    cases.json
    failures.json
    latest.md

test-results/                     # SANITIZED; tracked on same branch
  README.md
  latest.md
  latest.json
  latest-cases.json
  latest-failures.json
  runs/
    <UTC-run-id>.md
    <UTC-run-id>.json
    <UTC-run-id>-cases.json
    <UTC-run-id>-failures.json
```

The `latest.json` contains the **tested source commit SHA**, UTC
timestamps, overall PASS/FAIL, full command status and exit codes,
counts of passed/failed/error/skipped tests, test files discovered,
the per-file fallback runs, and safe compiler location
(`lib/...`/`test/...`, line, column) metadata. The cases file
includes the outcome of **every reported test**; the failures file
contains individual failed/incomplete cases and fixed error classes.

The published analyzer summary filters/token-redacts diagnostics.
Raw terminal logs, sensitive Expected/Actual values, full exception
bodies, user-home paths and book excerpts stay **local only**.
Review the sanitized output before pushing if your tests use dynamically
generated test names containing confidential data.

After a successful run the script stages **only its report paths**,
commits `test(results): Windows ...` and pushes them to the same
`feature/m0-flutter-foundation` branch. There is no force push.
Reports are published even if tests FAIL, so their results can
be used to fix the code.

If another developer pushes while tests are running, Git may reject a
non-fast-forward push. The reports remain on the local PC and the
local report commit remains in your checkout. Before re-running,
integrate concurrent changes using ordinary Git commands; the script
will never perform a potentially destructive automatic rebase.

## Options

```powershell
# Record locally only; no commit/push
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1 -NoPublish

# Use already fetched dependencies and skip the formatting check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1 -SkipPubGet -SkipFormat

# Extend per-file/Flutter command timeouts
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1 -TestTimeoutMinutes 45 -ToolTimeoutMinutes 30
```

Exit code **0** means all executed stages/tests passed and any requested
push succeeded (or publishing was deliberately disabled).
Exit code **1** means a test or check failed. Exit code **2** means
the checks passed but Git publishing failed.

## Reading results from ChatGPT

After the local run and a successful push, just write **`Procedi`**.
The assistant can read these files from the same connected private
GitHub repository without accessing your PC filesystem:

- [Latest run overview](latest.md)
- [Latest structured overview](latest.json)
- [All latest test outcomes](latest-cases.json)
- [All latest failures](latest-failures.json)

Use these files as authoritative *local* execution evidence. Do not
claim a green build based only on source code or newly authored tests.

## Publish an already completed local run without retesting

If a prior test execution completed but its report was not pushed
(for example, the checkout was dirty, `-NoPublish` was used, or another
commit moved the branch), **do not run all tests again only to upload
the report**. All sanitized report inputs were already written under
`.local-test-results/<run-id>/` by the test runner.

Pull the latest branch first, keeping the tracked worktree clean, then:

```powershell
git switch feature/m0-flutter-foundation
git pull --ff-only origin feature/m0-flutter-foundation
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\publish-local-test-report.ps1 -RunId 20261025T092418Z-0ff39187-2aa89e
```

Omit `-RunId` to publish the most recent completed local run.
The helper reads **only** the four existing sanitized files
`summary.json`, `cases.json`, `failures.json`, `latest.md`.
It checks source SHA ancestry, branch, report totals and path safety.
It never reads or uploads raw test stdout/stderr, books, credentials or
unsanitized local logs; it never reruns Flutter nor force-pushes Git.
It writes the same `test-results/latest-*` and immutable
`test-results/runs/<id>*` files as the original runner. If a push is
rejected, the report remains committed only locally.

This command is particularly useful for the 2026-10-25 run
`20261025T092418Z-0ff39187-2aa89e` documented separately in
`docs/LOCAL_EXECUTION_REPORT.md`: its summary is on GitHub, but the
current structured failure/case files are not yet published.
