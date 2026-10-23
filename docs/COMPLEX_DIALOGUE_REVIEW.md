# Local diagnostics for complex multi-speaker dialogue

Increment 2026-10-23. Added to feature/m0-flutter-foundation; Flutter
analysis/tests and native Windows/Android compilation remain deferred
by owner instruction. Code is NOT yet release-validated.

## Reader workflow

Voice Cast now has four tabs: Characters, Passages, **Dialogues**, Review.
Dialogues is a completely offline diagnostic editor, not an LLM task.
Choose one extracted EPUB spine chapter, PDF page or TXT section.
The inspector walks the selected original text and lists supported
quoted speech passages with original UTF-16 positions, current approved
speaker coverage and conservative flags:

- unmatched opening delimiter in a fully inspected section
- quote extending over a paragraph break
- speech ending in an em dash, en dash or ellipsis
- rapidly adjacent quoted turns, where speaker changes are possible
- missing or only partially covered speaker labels
- contradictory approved speaker labels on the same quoted passage
- an explicit narrator/unknown speaker override
- passage hitting the bounded local inspection limit (NOT automatically
  called a missing closing delimiter)

The reader can select **Review and assign exact selected words** beside
any passage. This opens the preexisting read-only text-selection editor
and requires a manual speaker choice and selected substring before a
source-hashed, user-locked attribution is saved. Reviewing a passage
does not apply a guessed speaker, rewrite the original book, reassign
other dialogue or require a cloud API request.

## Source and safety limits

- The parser recognizes «…», “…” and ASCII "…" pairs. It intentionally
  does not infer speakers, speech meaning, nested quote ownership or
  a specific person from dialogue order.
- Diagnostic output is limited to the first **24,000 UTF-16 code units**
  within the chosen scope and at most **140** quoted turns. Longer scopes
  are flagged as partially scanned; the reader can still use Passages
  for precise manual corrections outside the scanned area.
- Each passage is an unmodified substring of the source. UTF-16
  surrogate boundaries are respected; quote and narrator text are not
  concatenated or altered.
- Only accepted, human-locked precise source spans and exact verified
  original legacy manual segments are considered as prior attribution.
  Pending LLM suggestions, stale source hashes, missing anchors,
  book-foreign identities and out-of-scope labels are excluded.
- Full quote coverage uses a union of overlapping source ranges, not a
  naive sum that could accidentally imply complete coverage. Labels with
  different speakers (including explicit unknown) are flagged as
  conflicting instead of selecting any winner.
- Manual attribution covering only some of a quote is not upgraded to
  complete. An attribution covering the entire text selects that one
  known speaker for *display*; it was already approved separately.
- Adjacent turns are flagged for review but NEVER presumed to alternate
  narrators or share a voice.
- Unterminated quotes at a bounded scan cutoff are labeled
  **scan boundary**, distinct from a genuinely unclosed quote at the
  end of a fully inspected chapter/page.
- The scanner does not read book text outside the chosen scope to
  analyze quotes or compute prior label hashes. It is ephemeral and
  writes nothing to the database.
- This is a conservative tool. Text using unconventional dialogue
  typography, quotations within quotations, screenplay dialogue, or
  paragraph-spanning quotation conventions may require manual review.

## Source files

- lib/domain/dialogue_turn_inspector.dart: bounded original-text
  parser, coverage union, interruption and incomplete-turn flags.
- lib/features/reader/voice_cast_screen.dart: new Dialogues tab,
  chapter/page selector, per-turn explanations, source-exact manual
  correction action.
- test/domain/dialogue_turn_inspector_test.dart: 16 authored but
  **unexecuted** tests for adjacent speakers, incomplete/unfinished
  and multiline quotes, dash/ellipsis interruptions, partial labels,
  contiguous same-person coverage, conflicts, explicit narrator,
  pending/stale labels, exact legacy segment hashes, Unicode emoji,
  scan-boundary handling, scoped privacy limits and ASCII quotes.

## Remaining integration

Run Dart format/analyze and Flutter tests, then verify manual selection,
narration voice switching, EPUB/PDF/TXT extraction and native Windows/
Android scrolling on actual devices at final integration. CI stays
manual-only and PR #1 stays draft until these gates pass.
