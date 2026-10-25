# EReader — Progress against approved 2026-10-22 roadmap

**Reviewed:** 2026-10-25. **Implementation baseline:** commit
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
| M3 Offline neural and cloud | 30% | Secure key storage, explicit book-level OpenAI Speech consent and character quota, MP3 cache, cloud audio prefetch | No sherpa-onnx/model manager, no current Realtime engine/second cloud adapter, live-cloud verification or account-level currency spending ceiling |
| M4 Manual multivoice cast | 75% | Character identities, manual and locked cast spans, voice profiles, quote segmentation, no-speaker fallback, review/editor UI | 3+ character/native audio listening gate, richer segmentation and prosody, speaker performance verification |
| M5 LLM-assisted review | 55% | Opt-in bounded OpenAI analysis, proposals for speakers/characters/aliases, context and spoiler cap, evidence checks, identity reconciliation and review UI | No offline LLM, chapter/full-book screening pipeline with cost ceiling, annotated gold corpus, calibrated precision/recall and large-book validation |
| M6 Release and polish | 10% | Docs, local Windows run harness and manual CI workflow; a number of EPUB performance/robustness tests | Native Windows/Android packaging and signing, accessibility audit, benchmarks, privacy/licensing inventory, release candidate |

### Verification evidence, not an estimate

- Last *published* Windows run: `20261025T165839Z-946fc7b9-dc2652`,
  source `946fc7b9dae008bbe92e89248921bad6430f7a50`, **589 successful,
  0 assertion failures, 5 error outcomes, 67 test files**; overall FAIL.
- This report predates the file-picker migration, reader compile fix,
  bounded EPUB search viewport, stream-only Android document import, and
  library catalog controls. It does not prove those changes pass.
- The current repository contains 70 `*_test.dart` files, including new
  tests that have not run in that published report.
- No local Dart/Flutter toolchain is available in the GitHub-connected
  editing environment. Native platform projects `android/` and `windows/`
  are still absent from the tracked source tree.

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
