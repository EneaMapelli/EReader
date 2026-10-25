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
