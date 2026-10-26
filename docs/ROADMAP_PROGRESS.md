# EReader — Progress against approved 2026-10-22 roadmap

**Reviewed:** 2026-10-26. **Implementation baseline:** commit
`5fce63b2513685cfd576804083d0cff6fef004ff` on
`feature/m0-flutter-foundation`.

These percentages are *engineering judgments*, not measured test pass rates.
They describe feature/code coverage against the original milestone exit
criteria, taking unresolved integration into account. Equal-weight average
for M0–M6 is approximately **54%**; estimated practical release readiness is
much lower (**roughly 25–35%**) because native and acceptance gates are open.
No release or completed milestone is claimed.

| Original milestone | Estimated implementation | Evidence already in repository | Key unmet exit criteria |
|---|---:|---|---|
| M0 Foundation and POCs | 60% | Flutter modules, SQLite migrations, EPUB/PDF/system TTS source, bootstrap scripts and test runner | Native `android/` and `windows/` generated projects are not tracked; sherpa-onnx, native platform POCs, licensing/ABI results |
| M1 Reader MVP | 75% | SQLite book library and dedup, EPUB2/3 extraction and reading, PDF page view, TXT, anchors, headings/TOC, bookmarks, search, new library title search/sort/format controls | 20-book real corpus, Windows and Android renderer smoke tests, fuller CSS and accurate PDF reading order, author/series/cover metadata |
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
