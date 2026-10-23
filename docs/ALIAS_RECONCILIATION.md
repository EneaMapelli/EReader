# Alias reconciliation and identity review

Source implementation increment: 2026-10-23. Saved on feature/m0-flutter-foundation; Flutter tests and native Windows/Android builds have **not** been executed (owner requested final integration later).

## Reader workflow

1. In Voice Cast, curate real characters, assigning stable per-book IDs. Names and aliases can also be managed manually.
2. Open Voice Cast > Review > Analyze selected chapter or page with AI, and choose **Reconcile aliases** (third task alongside Assign speakers and Find characters).
3. Select only the already-known characters whose names/aliases may be transmitted. No character identities are sent by default. Select the EPUB chapter, PDF page or TXT scope, enforce saved-reading-progress cutoff (on by default) and optionally select up to 900 characters of earlier same-scope context.
4. Give per-book LLM analysis consent and provide an analysis API key. Review the precise passage, previous context, character names and aliases, scope and local input-character reservation. Only clicking **Send only this excerpt** issues a Responses API call. Alias reconciliation uses the same separate consent and quota as dialogue and character analysis. The quota is NOT a euro spending limit.
5. The LLM returns strict JSON proposals with segment_index and an exact alias text quote from the TARGET passage, speaker_id belonging to the user-selected existing cast, optional earlier-context evidence indices/text, and uncalibrated confidence.
6. The client checks that the alias appears exactly once in the cited segment, is source-aligned (UTF-16), does not go beyond the spoiler ceiling, does not collide with known cast names/aliases, and that any cited evidence is exact and earlier. The app derives source offsets and SHA-256 hashes on-device. When the same alias is proposed for more than one character in one response, the mapping is discarded as ambiguous.
7. All proposals enter **pending** SQLite records. The model never changes character names, aliases, dialogue tags or voices.
8. In Voice Cast > Review, the user sees the literal alias, suggested identity, supporting earlier quote (if present), confidence, and integrity status. They can reject it or choose/confirm the intended existing character in a dialog before attaching the alias.
9. Approval checks source/evidence again and rejects name collisions with *any* other character. The SQLite transaction appends the alias only to that character, records the review decision, and leaves speaker labels and provider voice selections untouched. Stale suggestions can still be rejected, not approved.

## Implementation

- lib/domain/alias_candidate.dart: immutable proposed alias and exact source/evidence guards.
- lib/llm/openai_alias_reconciler.dart: dedicated source-grounded task using the existing OpenAI Responses strict JSON transport, consent, secure key, request boundary and budget.
- lib/data/library_store.dart: SQLite **schema v11** (alias_candidates), transactional insert and approval, normalized collision checks for manual CastCharacter saves as well.
- lib/features/reader/dialogue_analysis_screen.dart: third opt-in task and explicit passage preview; existing privacy limit remains in force.
- lib/features/reader/voice_cast_screen.dart: preview, reviewer character selection, explicit accept/reject and stale guard.
- test/domain/alias_candidate_test.dart, test/llm/openai_alias_reconciler_test.dart and test/data/library_store_test.dart: proposed static/hash assertions, mocked consent/HTTP, ambiguous alias cancellation, duplicate rejection, cross-book isolation, evidence checks and schema v10->v11 migration.

## Limitations

- Literal quote and source provenance establish that the alias occurred, NOT that it refers to the suggested person. A title can belong to multiple people. This is why ambiguous references are dropped and individual manual approval is mandatory.
- The system does not automatically merge two existing cast identities: that could silently invalidate source anchors or provider-specific voice assignments.
- Cross-chapter coreference, pronoun resolution, role/organization/place disambiguation, linguistic stemming and multilingual alias equivalence still need richer review.
- Saved-position caps limit transmitted source text but cannot guarantee a model will never infer plot details from allowed text.
- All tests are **authored, not executed**. No real API keys, network calls, paid usage or device integration was run in this increment.