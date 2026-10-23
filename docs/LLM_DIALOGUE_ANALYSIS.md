# Optional chapter-scoped LLM dialogue analysis

Implemented in source on 2026-10-23, with actual compilation and device tests intentionally deferred to the final integration phase.

## User flow

1. Add characters and aliases in Voice Cast. Unknown or additional characters cannot be created by model output.
2. Open Voice Cast → Review → Analyze selected chapter or page with AI.
3. Select an EPUB spine chapter, PDF page or bounded TXT range, choose the model, and specify whether to enforce the **saved reading progress spoiler cutoff** (enabled by default). Explicitly disable that cutoff only when intentionally analyzing further into the chosen scope; no later scope is added.
4. Select **only characters already known at that point** in the story (none selected by default), including their names/aliases. Optionally include 400 or 900 characters of earlier context *from within the same scope*, never text after the target or outside the scope. Separately save an OpenAI analysis API key in device secure storage. This is a different secure key namespace from OpenAI Speech.
5. Explicitly grant per-book analysis permission and a maximum input-character budget. The dialog discloses that **the chosen passage and known character names/aliases** will leave the device, and that API billing may apply.
6. Click Preview and analyse selected excerpt. Review the **exact target passage, earlier context, selected character names and spoiler ceiling** and confirm **Send only this excerpt**. Opening the screen, choosing a model, saving a key or granting permission never sends text.
7. The request uses OpenAI Responses with store=false and a strict JSON Schema, through a fixed HTTPS endpoint and no redirects. The model returns candidate segment indices and verbatim substrings, not authoritative source offsets.
8. The application locally checks segment identity, unique excerpt matching, valid UTF-16 boundaries, original source content and selected already-known character IDs; it computes the source SHA-256 itself. The model may optionally cite an evidence_segment_index + evidence_quote in a *preceding context* segment; the app validates that excerpt and stores only its original source offset and hash. Unknown/ambiguous/unmatched suggestions are rejected, not guessed.
9. Candidates are saved exclusively as pending SQLite v7 cast spans. The user must individually approve or reject them in Review. Locked manual labels are never silently replaced.
10. Use Skip to next window for a longer chapter; the app never automatically analyzes other windows or chapters.

## Architecture

- lib/domain/llm_analysis_consent.dart — separate privacy authorization and input-character accounting.
- lib/data/library_store.dart — SQLite schema v9 (analysis consent in v8, backward-only evidence in v9): llm_analysis_consent, separate from schema v5 cloud_speech_consent and independent usage counters. Every attempted request debits input characters **before** HTTP in one SQLite transaction.
- lib/llm/dialogue_analysis_plan.dart — maps a user-chosen chapter/page to at most 4,200 target text characters per window and at most 80 segments; up to 900 previous-context characters inside the same scope (explicitly chosen), limited character roster, and a hard spoiler cutoff (saved reading progress by default). Rejected stale or unaligned offsets cannot leave device as active tags.
- lib/llm/openai_dialogue_analyzer.dart — optional paid adapter with gpt-5.4-mini or gpt-5.4-nano, structured Responses output and no tools, max 256 KiB response, bounded timeouts, refusal/incomplete detection. API key namespace openai-analysis.
- lib/features/reader/dialogue_analysis_screen.dart — separate credential, privacy/usage and request-preview controls.
- lib/features/reader/voice_cast_screen.dart — entry point from Review tab; imported results remain pending.

No entire-book request, background batch, embeddings upload, character-invention action or automatic voice approval is implemented.

## Financial and privacy boundaries

A local input-character quota is **not a maximum bill in euros**, token counter, API account-level budget or output-token quota. Provider output tokens, repeated retries and other clients can incur separate charges. Conservative attempted-input quota is retained on errors and after revocation. The user can reauthorize a higher limit, but cannot reset consumed input by toggling consent.

Responses with store=false requests no response storage through the API parameter; this should not be interpreted as a promise of zero provider-side security/abuse retention. Cloud providers still process any explicitly sent passage according to applicable terms. A passage may contain copyrighted material; users must comply with their content and provider rights.

Provider error-body contents are ignored; HTTP requests prohibit redirects so headers do not leak across hosts. Credentials stay in flutter_secure_storage, never SQLite, logs, filenames or the output proposal JSON. The model sees only the explicitly previewed target text, optional preceding context and **user-selected** already-known character names/aliases, not other chapters or private library data. Future character identities are not sent unless deliberately selected. The system instruction explicitly treats source text as untrusted; strict JSON schema and local validation prevent model-generated instructions from becoming operations.

## Safety and accuracy

- The model may guess the wrong speaker. Confidence is an uncalibrated heuristic, not proof. A validated earlier-context evidence citation is helpful for human review, but does not establish correctness by itself.
- No new identities are invented; only known cast IDs or null narrator can be returned.
- The model returns a local segment_index and an exact_quote that must appear **once** within the specified segment. Offsets and SHA-256 are derived on-device. This avoids trusting model-calculated UTF-16 indices.
- Before review, no proposed voice is played. Approved spans still undergo source-fingerprint validation when preparing audio.
- Reader-progress boundaries prevent sending any text later than the saved position unless the user explicitly disables the cap. They do NOT prevent a model from drawing inferences from already visible excerpts, selected character names or optional earlier context. Current snippets are extracted-text segments; nested dialogue, subtle pronouns, cross-chapter mentions and named-character discovery are not solved.
- No cloud LLM call was made during authoring, no API key was used, and no monetary spending was incurred by this work.

## Test plan and unexecuted fixtures

- test/llm/dialogue_analysis_plan_test.dart — EPUB/TXT bounds, saved-position spoiler cutoff, previous-only context, exact excerpt/evidence and speaker validation, ambiguous duplicate quotes.
- test/llm/openai_dialogue_analyzer_test.dart — denied by default, separate API key required, budget debited before request, strict Responses schema and scope-limited data with HTTP mock.
- test/data/library_store_test.dart — SQLite v7→v8 consent, v8→v9 evidence migrations, stored proof/hash revalidation, independent TTS/analysis consent and quota persistence.

The Flutter analyzer, Dart tests, Windows and Android builds and optional live API smoke tests remain required at final integration. The draft PR must not be merged or advertised as production-ready beforehand.

## References

- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/reference/resources/responses/methods/create
- https://developers.openai.com/api/docs/models/gpt-5.4-mini
