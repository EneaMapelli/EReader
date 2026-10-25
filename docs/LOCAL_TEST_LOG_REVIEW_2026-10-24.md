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

## Recovery disposal and rapid navigation follow-up — 2026-10-25

- The prior individual navigation timeout in `direct Play supersedes a
  blocked seek` was traced to a test which finished only the restarted
  first utterance but awaited `ReaderPlayer.play()` for the entire
  three-segment book. The fixture now finishes and verifies each of
  the three spoken positions, without weakening latest-wins navigation.
- The earlier `binding can only attach once` timeout had the same fixture
  deadlock: `await player.play()` was invoked with an unfinished mock
  engine. It now begins the session, pauses explicitly, then awaits it.
- Production `NarrationRecoveryBinding.dispose()` previously removed the
  crash checkpoint as long as `nativeStopUnconfirmed` was false. This was
  unsafe when the reader was closed during **active narration** or pending
  navigation even before native Stop had been requested. It now clears the
  marker **only** if the player is already confirmed `isSettledIdle`, with
  a regression test for unmount while audio is still live.
- No existing failure count is marked fixed: these test and production
  changes need a fresh execution on the current branch. The historical
  baseline and `NOT_RUN` current published status remain unchanged.

## EPUB source integrity and narrative cue corrections — 2026-10-25

- HTML5 error recovery promoted a malformed `<h1>` from `<head>` into
  the parsed XHTML body. Head content is now removed in the common
  preprocessing stage BEFORE DOM parsing; structural metadata, styles and
  spoken text therefore continue using identical normalization and offsets.
  The chapter-title parser also uses that safe preprocessing.
- The historical oversized-note fixture compared against 500 words with
  a trailing space, although spine extraction intentionally trims terminal
  whitespace. Updated to assert all words survive, not that trailing
  whitespace is preserved.
- The EPUB visual layout fixture expected a display paragraph to start on
  a whitespace character. Corrected the assertion to skip the leading
  space while retaining source-aligned speech and hard spine boundaries.
- The historical LLM context fixture was written with a literal backslash
  followed by `n`; the implementation returns the intended newline.
- Narrative antecedent cues now sort by newest matched END offset and
  prefer the full overlapping alias when end offsets are identical.
  This fixes the canonical-name substring winning over `Captain Mira`;
  added a newer-name regression so a later independent mention still wins.

The EPUB and cue changes are source and test edits only. No updated
Flutter execution result exists: the published status remains NOT_RUN.

## Cross-chunk narrator attribution follow-up — 2026-10-25

- Two historical failures in `test/domain/cross_chunk_cast_test.dart` came
  from expecting the final individual `SpeechSegment` to contain an
  entire narrator sentence. The deterministic bounded TTS chunker may
  validly split it at words (the observed final chunk was `replied.`).
  The suite now verifies the whole original narrator tail across its
  source-aligned chunks, with no lost non-whitespace text and **no
  inherited character voice** after a closed quote.
- Added a separate unexecuted regression for two approved speakers on
  successive dialogue turns with unlabelled narrator passages before
  and after the second turn; it checks source offsets and two distinct
  voice mappings. Source casting/coalescing runtime behavior is
  unchanged, because the observed failures were incorrect test
  expectations, not proof of a TTS attribution defect.
- Current published suite still reads **NOT_RUN**. The previous Windows
  errors and the new assertions require a current local rerun.
