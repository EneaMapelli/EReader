# Previous Windows execution — filtered follow-up (2026-10-24)

This is a historical, **non-green** execution from source commit
`061bde76`, not a test run of the current development HEAD. Do not
advertise the current build as passing based on these results.

The user's locally generated individual-case JSON was inspected after a
later manual merge inadvertently tracked raw `.local-test-results` files.
Only aggregate, path-free data is preserved in this document.

| Individual-case outcome | Count |
|---|---:|
| Successful | 434 |
| Assertion failures | 23 |
| Errors | 8 |
| **Reported cases** | **465** |

Error categories in the sanitized historical failures summary: 23
assertion failures, 2 timeouts and 6 compile/runtime errors. The earlier
full-suite attempt was blocked by a missing `SpeechSegment` import in
`test/features/epub_chapter_navigation_test.dart` and malformed syntax
in `lib/llm/openai_dialogue_analyzer.dart`; both are already fixed in
subsequent commits. The historical formatter additionally found three
malformed named-parameter method signatures in
`lib/features/reader/voice_cast_screen.dart`; corrected in the same
increment as this report.

The assertion failures also span cloud prefetch, MP3 decoder handoff,
narration recovery, native Stop/media focus, speaker attribution,
EPUB navigation/extraction, and LLM planning. They **have not** been
resolved or revalidated and must not be marked green. The checker's
formatting/lint findings also remain open.

To protect local paths and unrestricted stdout/stderr, the accidentally
tracked `.local-test-results/` subtree is removed from the current
Git branch tree. This **does not delete the old data from Git history**,
other clones, or hosting caches; a history rewrite and credential/log
sensitivity review are separate explicit tasks. The user's local logs
remain on their machine unless separately removed.

The public, filtered `test-results/latest.json` still says
`NOT_RUN`; rerun `tool/run-all-tests.ps1` on the up-to-date branch
to publish current results through the intended sanitized workflow.
No Flutter analyzer, native build or test execution was performed in
this development environment for these fixes.

## Incremental test follow-up — 2026-10-25

The historical cloud-prefetch failures were inspected at their actual
assertions. Both expected exactly **two** HTTP requests after Beta
playback began, although the approved one-chunk-ahead design
legitimately requests Gamma at that point. Updated the two fixtures to
require exactly one render each of Alpha, Beta and Gamma, verify the
narrator/character/narrator voice order, and prove Gamma is not played
before Beta finishes. This is a **test expectation correction**, not
permission for additional speculative requests.

All eight recorded MP3 preload failures in that prior run reported the
shared `until` helper's "Expected audio operation did not occur";
that helper yielded to the microtask/event queue only 80 times and
never waited meaningfully for Windows filesystem flush. Changed it to
bounded wall-clock polling (5 seconds, 10 ms intervals). This
distinguishes genuinely stuck audio/file I/O from CPU scheduling
variability. It does **not** prove MP3 cleanup or playback correctness;
the tests must be rerun.

No production audio code was modified in this follow-up. Prior
failures are **not declared resolved** until the updated local suite
confirms them. Other historical failures remain untriaged.
