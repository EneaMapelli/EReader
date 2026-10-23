# Local antecedent cues for reviewing indirect character references

Implemented as source increment on 2026-10-23. Flutter/Dart analysis, tests and native Windows/Android builds are not yet executed, by owner agreement.

## Reader interaction

When a reviewer opens an **indirect narrative reference** in Voice Cast > Review, EReader now performs a strictly **local** look-behind to show exact, earlier mentions of the book's already-curated characters. The review dialog starts with **no identity selected**, including when the model nominated one.

The dialog presents the original reference, any validated model evidence, a few nearby *potential antecedents*, and an explicit character selector. Each cue includes the known character's display name, the exact earlier passage, its distance from the reference, and one of two provenance types: **explicit existing name or alias** or **previously manually accepted narrative reference**. A nearby cue is a reading aid, never a conclusion. When two different people appear nearby, the UI explicitly warns of multiple plausible people.

Readers may select a person by choosing a displayed cue or by selecting another existing character from the dropdown. **Save reviewed reference** remains a separate manual action. Reject still works with stale sources. No cast characters, speaker assignments, TTS voices, aliases or book text are changed by finding or displaying these cues.

## Exact safety boundary

- Scans up to **900 UTF-16 code units before** the questioned reference, within its current selected chapter/page/TXT scope. It does not read later text or cross the previous scope boundary.
- Looks only for exact, case-insensitive **whole-word** occurrences of manually managed character names or existing aliases. A name embedded in another word, such as Mira inside Amira, is excluded.
- May reuse only **previously accepted** source-matching narrative links from the same book. Pending, rejected, stale and cross-book records are ignored.
- Keeps at most **five** cues, one most-recent cue per identity, with excerpts of at most **160 characters**. Multiple different identities remain visible as competing possibilities.
- Original source and excerpt UTF-16 spans are checked for surrogate splitting, including emoji. Excerpt SHA-256 fingerprints allow assertions that each displayed cue still matches the book.
- Unknown/repeated cast IDs and cast entries from another book are refused.
- Sorting by recency is only a presentation convenience. The software never uses proximity or model confidence to accept a referent or select a speaking voice.
- Cue extraction has **no cloud traffic, no LLM token cost, no external indexing service**, and requires no SQLite migration. It uses the saved book text, current local cast and previously reviewed narrative links.

## Implementation and tests

- `lib/llm/narrative_antecedent_finder.dart` implements bounded exact-match name/alias search and optional previously accepted reference chains.
- `lib/features/reader/voice_cast_screen.dart` renders a scrollable, source-grounded cue preview with no preselected referent.
- `test/llm/narrative_antecedent_finder_test.dart` contains eleven authored but unexecuted tests for competing antecedents, recency, aliases, whole-word boundaries, no-forward/no-cross-chapter search, long inputs, accepted-only reference chains, stale-hash rejection, emoji and wrong-book identities.
- `test/data/narrative_reference_test.dart` now additionally checks that reviewed reference cues remain tied to the surviving character after a manual duplicate-identity merge.

## Known limitations

A nearby name does **not** prove the identity of a pronoun, title or description. Cases involving quoted dialogue, misleading narrators, multiple people with the same role, unreliable narrative chronology, split chapters or changed extraction may still be ambiguous. The current approach does not perform syntactic parsing or create automatic character biographies. If no cue is found, the reviewer can still choose a known identity or reject the suggestion.

Tests and native integration are still pending. PR #1 remains draft.
