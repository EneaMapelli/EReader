# Speaker annotations: exact spans and LLM review protocol

**Implementation date:** 2026-10-23. This is source code committed to the feature branch; it has not passed Flutter analysis, Windows/Android builds, native audio testing or executed unit tests. Compilation remains deferred until final integration by the project owner's request.

## Manual experience

In Voice Cast / Passages, select a passage and use the **assign selected part** action. A read-only text field accepts mouse or touch text selection. Assign the selected excerpt to an existing character or to Narrator/unknown. This creates a manual, locked label and does not rewrite the original passage.

Accepted labels include an id, owning book ID, UTF-16 start/end, SHA-256 of the exact original selected text, optional EPUB spine/PDF page/TXT anchor, chosen character ID (or unknown), origin, review status and manual lock state.

The reader rebuilds speech boundaries at approved source spans. A sentence with dialogue and narration can therefore use separate voices, with narrator fallback before/after the selected words. Changed or stale source text, invalid/missing anchors and unavailable voices revert to narrator. Invalid overlapping annotations are conservatively ignored.

## Structured suggestion schema

The schema parser accepts an object with schema_version=1, current book_id and proposals array. It enforces a 256 KiB input and maximum 300 suggestions by default. A proposal has:

- id: unique per imported response
- start/end: UTF-16 source offsets in the current extracted document
- source_sha256: SHA-256 of the exact UTF-8 source substring
- speaker_id: existing book character ID or null for unknown
- confidence: finite value in [0,1]; never treat as a calibrated probability

Example shape (hash placeholder intentionally invalid until computed):

    {
      "schema_version": 1,
      "book_id": "book-id",
      "proposals": [
        {
          "id": "chapter2-turn17",
          "start": 3482,
          "end": 3506,
          "source_sha256": "<actual SHA-256 of selected text>",
          "speaker_id": "existing-character-id",
          "confidence": 0.81
        }
      ]
    }

Parser validation rejects book/version mismatches, unknown speaker IDs, repeated proposal IDs, invalid hashes, changes to text extraction, positions outside the original document and half-emoji surrogate boundaries. Instructions embedded in book text and model output are untrusted data; they cannot invoke actions.

## Approval and precedence

- Importing JSON is a local operation and makes no model call or network request. Every imported suggestion starts in status proposed and is invisible to voice casting until approved.
- Users can approve or reject each suggestion in Review. Rejected suggestions retain audit history.
- A manually assigned span is accepted and locked immediately. A new manual assignment may replace overlapping previously approved machine suggestions, but may not silently overwrite another manual label.
- Accepting an LLM proposal that conflicts with an existing accepted span raises a review error and leaves the previous assignment unchanged. Future jobs must not bypass this approval interface.
- Explicit unknown/narrator ranges also override legacy whole-segment casting in that selected interval.
- No API credentials, prompt secrets, network requests or LLM analysis jobs are created by this feature.

## Persistence and compatibility

SQLite schema v7 adds cast_spans. Migration preserves preexisting SQLite v6 character roster, provider voice IDs, legacy whole-segment cast, source anchors, progress, reading bookmarks, cloud consent/usage, pronunciations and library metadata.

The source fingerprint/anchor is checked again at runtime; even after migration, obsolete attribution never silently migrates to a different character or book.

## Remaining limitations

The user currently selects a substring within a displayed segment. Cross-paragraph spans, precise multi-line selection inside the main reader, nested quotations, prosody, evidence highlighting and automated speaker attribution still need implementation. Future LLM analysis must require explicit scope/privacy authorization and separate cost controls; the current app merely parses/reviews externally prepared JSON.

## Tests authored, not executed

- test/domain/cast_span_test.dart: narrator/character partition, exact source offsets, surrogate safety, stale digest/anchors and overlapping ranges.
- test/domain/llm_cast_proposals_test.dart: schema, source hash, unknown speakers, confidence and untrusted input rejection.
- test/data/library_store_test.dart: v7 schema migration, pending-only LLM import, approved/manual precedence, persistence and no-overlap transactions.
