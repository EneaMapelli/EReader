# Manual character identity merge — SQLite schema v12

Source implementation increment: 2026-10-23. **Flutter tests, analyzer and Windows/Android builds have not been executed**; final integration is deferred by owner instruction.

## User workflow

1. Open Voice Cast → Characters → **Merge duplicate characters**. The button is disabled until at least two local character identities exist in the book.
2. Choose the duplicate identity to **REMOVE**, then the identity to **KEEP**. Both must belong to the same imported book. They cannot have the same ID.
3. Inspect the non-mutating preview: source/target names and stable IDs, combined aliases (including the old source display name), counts of dependent dialogue tags, precise speaker spans, reviewed character candidates, pending/approved alias links, and provider voice assignments.
4. For every provider where both characters already have **different** voice profiles, explicitly choose source or target. There are no preselected winners. Where only the duplicate has a provider voice, its voice is retained on the kept character. Equal profiles need no decision.
5. Check the confirmation acknowledging the irreversible merge; then click **Confirm manual merge**. No text from the book leaves the device, no LLM API call occurs, and the original ebook file is never rewritten.
6. The operation runs in a single SQLite transaction. If any conflict, stale preview or database error occurs, the transaction is rolled back. The screen requires a fresh preview rather than trying again with outdated choices.
7. Return to the cast screen; the surviving character has its original stable ID, combined name/aliases, provider voice choices and all re-linked speaker attributions. The old duplicate is removed and a local merge audit record remains.

## Persistence semantics

SQLite schema **v12** adds `cast_merges` audit rows, recording old/kept IDs and display names, preview fingerprint, explicit voice decisions, affected record counts and UTC date. Audit history is book-scoped and deleted only when the book itself is deleted.

Before deleting the source identity, the transaction retargets:

- `segment_cast.character_id`: legacy whole-segment dialogue attribution
- `cast_spans.speaker_id`: precise accepted/pending source-aligned speaker annotations
- `character_candidates.created_character_id`: previously approved identity discoveries
- `alias_candidates.suggested_character_id`: pending original model proposal identities
- `alias_candidates.approved_character_id`: reviewed alias provenance
- `cast_voices`: provider-scoped assignments, with explicit human choice on differing profiles
- `cast_characters.aliases_json`: source display name plus all source aliases appended to the retained identity, deduplicated by normalized case/whitespace

Only then is the source character deleted. Its old voice rows cascade, but other references have already moved. Book IDs, source offsets, SHA-256 hashes, anchors, review decisions and the original book content stay unchanged.

The preview uses an optimistic SHA-256 fingerprint of the roster, provider profiles, dependent record counts and the identity/review/hash of every involved reference. A change between preview and confirmation invalidates the operation even if record counts remain the same. All decisions are validated inside the transaction.

## Hard safety limits

- No merge across different books; no self-merge.
- At most 50 resulting aliases, following CastCharacter's existing cap.
- Existing other characters' names and aliases are reserved; merging never steals a name from an unrelated third identity.
- Provider voice conflicts are **not** resolved automatically. Every conflicting provider requires a 'source' or 'target' selection; extra/missing/invalid choices abort.
- No automatic unification based only on LLM text, name similarity, pronouns or book evidence. Explicit human choice is mandatory.
- Historical references are retargeted to the kept ID; there is no automatic undo. The local audit is for provenance, not a reversible backup.
- Existing separate per-book LLM/cloud speech consent and quota accounting are untouched. No API key or audio cache credential is transferred.

## Tests authored but not executed

`test/data/cast_merge_test.dart`: preserve provider voices and speaker spans; pending/approved model pointers; SQLite foreign-key consistency; migration from v11; all-or-nothing rollback with unresolved provider conflict; same-book restriction; stale preview including same-count hash edits; alias cap.

Production checks still required: format, analyze and test on a real Flutter toolchain, native migration, Unicode/narration smoke tests, concurrent cast edits and Android/Windows UX. The PR must remain draft until these gates pass.