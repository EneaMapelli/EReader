# EReader — Progress against approved 2026-10-22 roadmap

**Reviewed:** 2026-10-26. **Current branch:** `feature/m0-flutter-foundation` (PR #1 draft).

These percentages are *engineering judgments*, not measured test pass rates.
They describe feature/code coverage against the original milestone exit
criteria, taking unresolved integration into account. Equal-weight average
for M0–M6 is approximately **55%**; estimated practical release readiness is
much lower (**roughly 25–35%**) because native and acceptance gates are open.
No release or completed milestone is claimed.

| Original milestone | Estimated implementation | Evidence already in repository | Key unmet exit criteria |
|---|---:|---|---|
| M0 Foundation and POCs | 60% | Flutter modules, SQLite migrations, EPUB/PDF/system TTS source, bootstrap scripts and test runner | Native `android/` and `windows/` generated projects are not tracked; sherpa-onnx, native platform POCs, licensing/ABI results |
| M1 Reader MVP | 78% | SQLite book library and dedup, EPUB2/3/PDF/TXT, anchors/TOC/bookmarks/search, user-editable title/author/series/language via SQLite v17 and catalog sort/filter | 20-book real corpus, Windows and Android smoke tests, EPUB OPF auto metadata/cover extraction, fuller CSS and PDF reading order |
| M2 Free TTS and read-along | 70% | OS speech adapter, voice controls, text/audio checkpoints, source highlight and scrolling, segment navigation, sleep timer, media session source, interruption guards | Real Android lock-screen, phone-call/audio-focus and Windows key tests; guaranteed chapter-long playback and accurate engine timing |
| M3 Offline neural and cloud | 35% | Secure cloud keys/consent/cache; guarded sherpa VITS worker and manifest-verified assets; local voice status/removal screen | No native ONNX voice qualification, guided model installer or authenticated catalog, no Realtime/second provider, live-cloud validation or monetary ceiling |
| M4 Manual multivoice cast | 75% | Character identities, manual and locked cast spans, voice profiles, quote segmentation, no-speaker fallback, review/editor UI | 3+ character/native audio listening gate, richer segmentation and prosody, speaker performance verification |
| M5 LLM-assisted review | 55% | Opt-in bounded OpenAI analysis, proposals for speakers/characters/aliases, context and spoiler cap, evidence checks, identity reconciliation and review UI | No offline LLM, chapter/full-book screening pipeline with cost ceiling, annotated gold corpus, calibrated precision/recall and large-book validation |
| M6 Release and polish | 10% | Docs, local Windows run harness and manual CI workflow; a number of EPUB performance/robustness tests | Native Windows/Android packaging and signing, accessibility audit, benchmarks, privacy/licensing inventory, release candidate |

### Verification evidence, not an estimate

- Latest published and normalized Windows run:
  `20261025T201001Z-7c89dfc8-a63603` (source `7c89dfc8`).
  **641 passed, 0 failed assertions, 7 errors, 76 discovered test files**;
  overall FAIL. Pub-get and Dart/Flutter version checks succeed.
- Analyzer: **zero errors**, ten source/test warnings, plus informational
  lints; nonzero analyzer exit code remains until warnings/info are resolved.
  Formatting fails for 147 existing Dart files (`dart format` not applied).
- Six source-search widget cases share a Flutter intrinsic-size crash:
  `AlertDialog` measures a lazy result ListView that has no intrinsic width.
  The search dialog now supplies a finite parent width before layout.
- The remaining EPUB worker preflight test failed while Windows held a
  temporary EPUB file (sharing violation 32) during teardown. Its fixture
  cleanup now retries transient Windows locks a bounded number of times.
- Ten nonblocking analyzer warnings have been addressed, and only sanitized
  summaries/results of the newest run remain in the current branch.
  Raw per-command logs were mistakenly committed in a prior commit and
  are excluded from the current tree; `.gitignore` now prevents accidental
  restaging. Removing them from the current tree does not erase older Git
  history.
- **All remedial commits postdate that run**. No updated platform test suite
  has verified these changes; do not count them as passing or declare a
  native Windows/Android milestone completed.

### Highest-impact next steps

1. Execute `tool/run-all-tests.ps1` on the current branch HEAD, publish
   sanitized results, then repair remaining analyzer/test errors.
2. Generate and verify the real Windows and Android project folders and
   smoke-test import, read, close/reopen, no-network system TTS, background
   controls and PDF text-layer handling on devices.
3. Finish M0/M3 offline neural TTS proof of concept and model/license
   inventory, and migrate the transitory OpenAI Speech path to a supported
   Realtime adapter; evaluate a second provider under capability flags.
4. Curate at least 10 representative legal narrative samples for M4/M5
   speaker attribution metrics and golden source-fidelity comparisons.
5. Complete M6 packaging/signing, accessibility, performance/power and
   distribution/license/privacy gates.

**Scope note:** Proposed ER-017–ER-034 extensions (OCR, OPDS, audiobook
export/import, sync, contextual AI, massive-library indexing) are not
included as completed features by merely having been designed in the roadmap.

### Progress note — 2026-10-26

- Added a guarded **offline model manager** reachable from the speech
  settings screen. It lists and verifies installed packs, marks damaged
  entries and supports user-confirmed removal of an individual pack; neural
  synthesis remains unavailable until a licensed model and Windows/Android
  acceptance tests exist. M3 estimate rises cautiously to **35%**; overall
  M0–M6 remains approximately **54%** with equal milestone weighting.
- Latest executed Windows run still reports 641 pass and 7 errors at older
  commit `7c89dfc8`. The search dialog intrinsic-width fix, Windows
  temporary-handle cleanup, warning reductions and this new model manager
  are not yet validated by a new run.

### Progress note — guided import (2026-10-26)

- The new guarded M3 model manager now supports **local Windows VITS
  folder import** after reviewing the manifest, size and declared license,
  with explicit affirmative approval before SHA-256 checked installation.
  A local PowerShell manifest-preparation helper computes checksums for
  previously obtained ONNX/phonemizer resources. No model downloading or
  automatic cloud requests were added.
- This does not authenticate a publisher's checksums or grant usage
  rights. The neural engine remains hidden from user-facing TTS selection
  pending real-model audio tests, Android SAF handling, licensing review
  and native device qualification.
- The previous M3 feature-coverage estimate remains **35%** pending
  passing integration evidence; overall M0–M6 estimate is unchanged.
- The most recent executed Windows report still shows 641 successful tests
  and 7 errors at older source `7c89dfc8`; the new import UI and tests
  have not been run. The 147 previously unformatted files remain a
  separate unresolved check until the formatter utility is executed.

### Progress note — model qualification instrumentation (2026-10-26)

- A new opt-in local neural benchmark now measures actual VITS-produced
  WAV properties, inference wall time, real-time factor and RSS snapshots,
  with two preset phrases per locale and a separate optional Stop probe.
  It accepts either installed verified packs or a source folder that is
  hash-checked into private temporary storage. It can optionally upload a
  whitelisted numeric result; no native result currently exists.
- See [OFFLINE_TTS_QUALIFICATION.md](OFFLINE_TTS_QUALIFICATION.md)
  for Windows commands, limitations and mandatory native acceptance gates.
  **M3 remains 35% estimated** rather than increasing based only on a
  benchmark that has not run; overall M0–M6 remains ~54% feature coverage.
- Most recent executed Windows suite is still `7c89dfc8`: 641 passed,
  no assertion failures, 7 errors, plus 147 unformatted source files.
  Do not count the post-run search/EPUB/M3 changes as validated.

### Progress note — catalog metadata (2026-10-26)

- Completed an additional **M1 product feature**: manually editing
  title, author, series and language in the library; searching and ordering
  by author/series; preserving book hash identity, progress, cast, consent
  and bookmarks through transactional SQLite migration **v17**.
  Optional metadata survives dedup/reimport and restart. Locale is
  intentionally library metadata and does **not** silently change the
  user's configured speech provider or voice.
- Updated M1 estimated feature coverage from 75% to **78%** and the
  equal-weight M0–M6 estimate from ~54% to **~55%**. These are qualitative
  judgments, NOT executed-native acceptance percentages.
- Full point-by-point original plan and approved extensions:
  [ROADMAP_DETAILED_PROGRESS.md](ROADMAP_DETAILED_PROGRESS.md).
- No new Windows test result exists beyond `7c89dfc8`: 641 passes,
  0 assertion failures, 7 error outcomes. The new SQLite migration,
  metadata editor and search changes have not been locally compiled here.

### Progress note — optional real-book corpus coverage (2026-10-26)

- M0/M1 now have an opt-in real EPUB/PDF regression harness for the user's
  local `example/` folder. It covers actual import, decode, reader source
  positions, persisted SQLite progress and native PDF opening, with optional
  EPUB background narration-source consistency checks.
- The tests do not require remote books or auto-publish filenames/results;
  all detailed reports and files stay outside Git. See
  [EXAMPLE_CORPUS_TESTS.md](EXAMPLE_CORPUS_TESTS.md).
- Existing M0/M1 feature percentages remain **60% / 78%**, and overall
  milestone coverage remains **~55%** until real corpus and native client
  results demonstrate what works and what needs repair.
