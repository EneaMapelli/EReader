# Reviewed indirect character references

Increment: 2026-10-23. Source implemented in feature/m0-flutter-foundation.
Flutter analyze/tests and Windows/Android builds deliberately deferred by
project owner. No paid API requests or native integration claims.

## Why references are separate from speaking voices

A narrative sentence such as "she entered" referring to Mira does NOT mean
Mira is the voice narrating it. Source references are stored separately
from cast_spans, segment_cast and provider voice settings. Even reviewed
references never assign a spoken voice or alter existing speaker labels.

## Reader workflow

1. In Voice Cast > Review > Analyze selected chapter or page with AI, select
   Resolve references (the fourth task).
2. Select a bounded EPUB/PDF/TXT window and the known cast roster. Consent,
   secure analysis key, local attempted-input quota, saved-position spoiler
   boundary, optional earlier same-scope/previous-chapter context, source
   preview and individual Send confirmation all remain mandatory.
3. The fixed OpenAI Responses adapter uses its already strict JSON schema.
   Here exact_quote identifies an indirect title, pronoun or description;
   speaker_id means only the tentative EXISTING referenced identity, NOT
   the person who speaks the sentence. Unknown references use null.
4. The application verifies exact, unique book-source substring and UTF-16
   range, source SHA-256, selected cast ID, context evidence when provided,
   chosen scope and spoiler cutoff. Direct known names/aliases are excluded.
5. When the model gives two different characters for the same source span,
   the result is a single AMBIGUOUS pending candidate without a winner.
6. Review > Pronouns and indirect narrative references shows literal quote,
   type, suggested person, ambiguous state and whether the evidence is stale.
   The reviewer explicitly chooses a known character or rejects the item.
7. An approval revalidates the source and only creates a local narrative
   reference link. Nothing in narration, TTS, cast membership or alias tables
   changes. Rejection works even when the original source is stale.

## SQLite v13 and manual merges

The book-scoped narrative_references table stores local reference text,
start/end offsets, SHA-256, type, original and accepted cast IDs, confidence,
ambiguous flag, optional prior-context evidence and review status.
One source span can have only one record per book. Repeated LLM runs cannot
overwrite an accepted or rejected decision. Deleting a book cascades to
all such metadata.

The manual two-character merge now retargets both proposed and approved
reference IDs to the surviving identity before removing the duplicate.
The merge preview includes these references and their source hashes/states
in the optimistic concurrency fingerprint, preventing stale review.

## Local antecedent cues during manual review

Every pending reference now opens with an empty confirmed-person selection. The UI searches at most 900 UTF-16 characters strictly **before** that mention and within its scope for known character names/aliases and earlier manually accepted indirect links. Up to five fingerprint-verified, short excerpts are shown as competing cues (with distance), including explicit warnings when several people occur. No model call is made for these local hints, and nothing selects the speaker or narration voice automatically. Details: [Local Antecedent Cues](LOCAL_ANTECEDENT_CUES.md).
## Accuracy and limits

- A citation proves that text occurs; it does not establish the correct
  fictional referent. All model guesses remain human-reviewable.
- The local pronoun vs title/description category is a conservative UI
  heuristic, not a semantic or grammatical guarantee.
- Prior-chapter snippets inform context but cannot act as same-scope
  evidence_segment_index references.
- No full-book upload, hidden background inference, automatic family tree,
  cross-book data association, spoiler-free guarantee about model inference,
  or automatic character/voice reassignment is claimed.
- The local character budget is not a monetary API bill cap.

## Files and authored (unexecuted) tests

- lib/domain/narrative_reference.dart: source-verified review DTO.
- lib/llm/openai_reference_resolver.dart: separate coreference instruction
  and model parsing, using existing consent/key/strict Responses transport.
- lib/data/library_store.dart: schema v13 table, atomic review and
  character-merge reference updates.
- lib/features/reader/dialogue_analysis_screen.dart: fourth task.
- lib/features/reader/voice_cast_screen.dart: explicit reviewer UI.
- test/llm/openai_reference_resolver_test.dart: source, consent, context,
  ambiguous guess and anti-hallucination scenarios.
- test/data/narrative_reference_test.dart: migration, rollback, stale
  approval, status, cast-merge and playback-isolation scenarios.

Final production validation remains blocked on deferred Dart/Flutter toolchain
execution and Android/Windows real-device checks. PR #1 stays draft.


## Prior dialogue speakers are separate from referents

Confirmed speakers from at most 1,200 UTF-16 characters before an ambiguous mention now appear in a dedicated, verified conversation history alongside prior *character mentions*. Multiple preceding speakers and conflicting overlapping labels are called out; none determines the referent automatically. See [Conversation Speaker Context](CONVERSATION_SPEAKER_CONTEXT.md).
