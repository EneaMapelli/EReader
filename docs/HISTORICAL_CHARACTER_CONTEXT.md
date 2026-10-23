# Opt-in character continuity across earlier chapters

Implemented in source on **2026-10-23** in branch `feature/m0-flutter-foundation`; no Flutter analyzer, test or Windows/Android builds have been run at the owner's request.

## What changes for the reader

In **Voice Cast → Review → Analyze selected chapter or page with AI**, select the already-known characters and choose an EPUB spine chapter, PDF page or TXT text range. The new **Include known names from earlier chapters** option is **OFF by default**. When enabled, EReader locally finds a few literal mentions of these selected characters in earlier source scopes. The final confirmation displays the exact excerpts from earlier chapters **before** any remote request. The previously separate target excerpt and optional 0/400/900-character *same-scope* context remain unchanged.

Historical excerpts can help the model recognize a character from the earlier part of a story. They are **context only**, not evidence usable for approval and not eligible targets for voice casting, alias creation or character discovery. All such LLM outputs still pass the exact target-source validation and must be individually reviewed before affecting the cast.

## Data boundaries

- A local-only scanner looks at at most **six** completed earlier source scopes, each limited to its last **50,000 UTF-16 code units**. It never reads later chapters to discover candidate snippets.
- The generated request includes at most **five** historical mentions total, **two per explicitly selected character**, **550 characters of historical excerpt text** in aggregate, and **130 characters per excerpt**.
- Only existing manually approved cast IDs, names and aliases explicitly included in the analysis roster may appear in historical context. New, pending or future-only candidate identities are excluded unless the user first separately approves their addition to the cast.
- A matched name/alias must be an exact, complete case-insensitive Unicode word-boundary match. It cannot match the middle of another name (for example, `Mira` inside `Amira`).
- Each excerpt carries original chapter range, excerpt and mention UTF-16 positions, and a local SHA-256 of the original excerpt. Surrogate-pair boundaries are checked to avoid breaking emoji.
- Validations check that the source scope has fully ended **before** the target scope starts, and that historical excerpts remain inside the chosen story-position spoiler ceiling. Missing, out-of-book, duplicate, unknown-cast and oversized references are rejected before any model request.
- The HTTP request contains only `historical_mentions` with the previous source-scope identifier, the selected cast ID, the matched name and the exact excerpt; it never includes a full-chapter index or unseen novel text automatically.
- The existing consent (off by default), dedicated API key, per-request explicit confirmation and attempted-input-character quota cover **all** extra context. The counted JSON payload grows when history is enabled; this is not a euro spending cap.
- When the toggle is off, historical data is absent from the request (the `historical_mentions` array is empty). No background indexing, recurring analysis, full-book LLM upload, inferred family tree or automatic character merge is created.

## Source implementation

- `lib/llm/historical_character_mention.dart` — immutable source-grounded earlier-chapter reference and validation against an explicitly selected cast roster and spoiler ceiling.
- `lib/llm/historical_character_concordance.dart` — bounded previous-scope name/alias search with Unicode word boundaries and SHA-256 excerpt fingerprints.
- `lib/llm/dialogue_analysis_plan.dart` — optional historical mentions in immutable request window, kept separate from same-scope evidence-bearing passages and target narration segments.
- `lib/llm/openai_dialogue_analyzer.dart` — validates reference count, scope ordering, source fingerprint, known-cast membership and character quota; includes optional structured `historical_mentions` in the same Responses request. The other two model tasks use the same request guard.
- `lib/features/reader/dialogue_analysis_screen.dart` — opt-in switch, visible mention count and verbatim prior-chapter snippets in the per-request confirmation dialog.

## Safety boundaries and limitations

- Matching a name does **not** prove that two mentions refer to the same fictional person. A family title, reused name or misleading narrator may be ambiguous. All speaker, alias and identity changes remain separate reviewed decisions.
- "Spoiler-safe" here means **source position bounded**, not knowledge of which paragraphs a human has truly read. Skipping earlier chapters can still expose their text if the user explicitly enables history. Disable the option for books with nonlinear reading order.
- Previous-chapter excerpts are not eligible `evidence_segment_index` citations. Only explicitly provided preceding `context_segments` within the target scope support source-grounded model evidence.
- The scanner does not infer undocumented aliases, resolve pronouns, upload all earlier chapters, cache a profile across devices, or generate biographies. These are future features requiring separate review.
- EPUB/PDF extracted text offsets depend on the current source extraction. If extraction changes, source fingerprints must be revalidated.

## Regression tests authored (not executed)

`test/llm/historical_character_concordance_test.dart` covers earlier-only scopes, unknown cast default, Unicode boundaries, case-insensitive whole-name detection, bounded multi-chapter scan, request payload and quota changes, invalid future-scope injection and the exclusion of historical snippets from source dialogue target indices.

**Release gate:** run Dart analyzer and tests, then native Windows/Android checks and real consent/request UX tests during final integration. The GitHub PR remains in draft.