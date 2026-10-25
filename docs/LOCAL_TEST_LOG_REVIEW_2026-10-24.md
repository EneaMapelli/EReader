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

## Audio safety fix — 2026-10-25

A real bug was identified in `ReaderPlayer._stopCurrent`: it published
`isPlaying=false` to listeners **before** incrementing the pending native
Stop count. For direct Pause (not a seek), subscribers saw transient
`isSettledIdle=true` and could clear SQLite crash recovery markers or
release Android audio focus while the previous utterance still played.
The ordering was corrected: pending Stop is recorded before the first
notification, and settled idle is signaled only on successful actual
Stop completion.

`ReaderPlayer._voiceFor` also returned null whenever a character voice
was missing from the installed provider catalog, even if a narrator
fallback was available. It now selects the cast voice if installed,
otherwise the configured or default **installed narrator** voice.
Source speech text and offsets are unchanged.

A historical media-handler test expected focus release and settled
idle after native Stop threw an exception. That contradicted the
fail-closed, unconfirmed-stop safety policy and the other native Stop
tests: it now asserts that focus remains until explicit reader teardown
and remote Play stays blocked. Added a synchronous listener test for
the pause-notification race.

These source and test fixes are authored, **not yet executed** against
the updated Windows/Android application. Re-run all affected tests.
