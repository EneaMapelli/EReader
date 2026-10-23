# Character discovery — human-reviewed candidate roster

Implementation increment: 2026-10-23. Source code committed but not compiled or tested on native devices; builds and Flutter test execution remain deferred by project owner.

## Workflow

1. Open Voice Cast > Review > Analyze selected chapter or page with AI.
2. Switch Analysis task to **Find characters**. The same EPUB chapter/PDF page/TXT scope, saved-position spoiler ceiling (on by default), optional previous context and explicit per-request source preview remain in force.
3. An existing character roster is **not required** for discovery. Existing characters/aliases are transmitted only when the user explicitly selects them as already-known; no cast identities are sent by default.
4. Configure the separate analysis API key and explicitly grant per-book LLM analysis permission. Selecting Find characters does not trigger an API call. The user must confirm **Send only this excerpt** for each window; attempted input characters count toward the existing analysis quota, not toward TTS quota.
5. OpenAI Responses uses the existing strict JSON format: segment_index, exact_quote, speaker_id=null, evidence_segment_index=null, evidence_quote=null, confidence. In this task, exact_quote must be the character name literally present in the selected target segment, once. No inferred, invented or context-only names are accepted.
6. The device computes the actual original UTF-16 mention offsets and SHA-256. Missing/ambiguous/stale or future-source names are rejected. Existing roster names/aliases and repeated suggestions are filtered.
7. SQLite schema v10 stores pending CharacterCandidate rows separately from cast_characters and cast_spans. **Import does not add a person, assign a voice or attribute any dialogue.**
8. In Voice Cast > Review, the reader sees each proposed name, the uncalibrated model confidence and whether the source mention is still exact. They can reject it or explicitly approve a new cast identity (optionally correcting the display name).
9. The approval action checks source integrity and collisions with existing character names/aliases, then creates the cast character and changes the proposal status in **one SQLite transaction**. On rejection, the proposal is archived without creating anything. Existing characters and their voice assignments remain untouched.

## Safety properties

- Cloud access remains off by default, and the authorization is per book. No background scans, future chapter previews or automatic browsing are added.
- Model output is untrusted; it can suggest source strings only, not execute instructions, choose an ID or edit the database directly.
- Existing/ambiguous names are intentionally treated conservatively. For two genuinely different people with identical names, the user can curate the cast manually rather than allowing automatic duplication.
- Discovery only spots literal named mentions. It does **not** prove that a mention is a fictional person rather than a location, book, historical figure or organization. Human review remains mandatory.
- Approving a candidate does not assign a speaking voice, an alias, gender, personality or any dialogue. Those remain explicit manual or separately reviewed operations.
- The same analysis consent and input-character ceiling apply to both AI tasks. Character ceilings are not monetary billing caps; provider output may generate additional token charges.
- Review of stale proposals can reject them, but cannot approve them. Deleting the source book cascades to its discovery history.
- The API key stays in device secure storage (openai-analysis namespace). No model calls, token costs or uploaded book content were involved in implementing this increment.

## Code and migration

- lib/domain/character_candidate.dart: source-accurate candidate, normalized-name collision helper and status enum.
- lib/llm/openai_character_discoverer.dart: existing bounded Responses transport, permission guard, quota reservation, strict model instruction and exact-mention parser.
- lib/features/reader/dialogue_analysis_screen.dart: mode switch in the existing consent/preview flow.
- lib/features/reader/voice_cast_screen.dart: proposed identity review, name correction, duplicate warning, explicit approval/rejection.
- lib/data/library_store.dart: SQLite v9 -> v10 migration, candidate insertion, atomic approval and rejection.

## Tests authored, not executed

- test/domain/character_candidate_test.dart: source hashes, collision normalization and validation.
- test/llm/openai_character_discoverer_test.dart: default-deny consent, missing key, exact mention, duplicate/name hallucination rejection, scope and quota.
- test/data/library_store_test.dart: import leaves cast unchanged, approval adds one person with no voice, rejection, duplicate alias checks, book isolation and v9->v10 migration.

## Remaining work

Semantic role disambiguation, separate organizations/locations, alias reconciliation, evidence ranking, optional offline NER and actual Flutter Windows/Android runtime tests. Until final integration, code is unverified and PR #1 must stay draft.

## Distinguishing an alias from a new identity

A recognized name is not necessarily a new person. After discovery, **Reconcile aliases** may separately propose that a literal nickname or title belongs to an already-known character. It is not applied until a reviewer confirms the link; no existing people or voices are merged. Existing book-scoped names and aliases are checked for collisions. See [Alias Reconciliation](ALIAS_RECONCILIATION.md).
