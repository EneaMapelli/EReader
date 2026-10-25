# Complex dialogue turns — paged human review

Source increment on 2026-10-23 for EReader, branch
feature/m0-flutter-foundation. Flutter analyzer/tests and Windows/Android
builds are **not executed**, as requested by the project owner until final
integration.

## Reader workflow

Voice Cast > **Dialogues** already includes a bounded diagnostic report.
The new **Open detailed dialogue turn editor** action opens a separate,
paged, source-exact review interface. The reader can choose an EPUB spine
chapter, PDF page or TXT source range and move through windows of up to
12,000 UTF-16 code units. A maximum of 100 potential turns are shown in
one window; when the cap is hit, Next continues after the last displayed
turn instead of silently skipping unexamined text.

The review parser recognizes quoted passages using guillemets, typographic
curly double quotes and ASCII double quotes, and line-start en/em dashes.
These are **syntactic hints** only: the app does not infer who speaks.
An unfinished opening quote or an item cut by a window boundary is
marked open/truncated, not automatically considered an invalid book.
Dialogue ending in an em/en dash, ellipsis or three periods is explicitly
flagged as interrupted.

Each identified turn preserves source UTF-16 offsets and the *verbatim*
original substring. The interface displays the exact labels covering
individual subspans:

- **confirmed:** one source-verified human-approved speaker ID;
- **narrator:** the user has explicitly locked narrator/unknown;
- **unknown:** no accepted source-aligned voice label;
- **conflict:** accepted labels disagree about this subspan.

The display also flags partially labeled turns, multiple confirmed
speakers inside one quotation and overlapping contradictory attributions.
It never alternates character voices just because two turns are adjacent,
nor continues a voice into a new quote without explicit approval.

## Manual labeling

For a complete, fully UNLABELED turn, the reader can choose
**Label this turn manually** and select a character or the narrator.
The dialog never preselects a speaker, and the source text is shown before
confirmation. Once confirmed, the existing LibraryStore saveManualCastSpan
transaction enforces the original excerpt hash, book-scoped identity and
overlap constraints, and creates an accepted, user-locked precise cast span
with a source anchor. Existing human locks cannot be silently replaced.
For partially labeled, conflicting or open/truncated turns, the inline
action is disabled; the existing Passages selection editor remains the
place to correct exact subspans.

The manual narrator option uses an empty selection value (not a character
ID), preventing collisions with any valid cast identity. There is no
remote request, LLM cost, new database migration, or automatic rewriting
of the book. Audible changes come only from the reader's explicit
persisted cast assignment and the existing playback engine.

## Implementation

- lib/domain/dialogue_turn_review.dart — deterministic local bounded parser,
  conservative punctuation interruption flags, accepted-source attribution
  intersection, explicit narrator vs unknown, overlapping speaker conflict,
  immutable turn/source-offset data.
- lib/features/reader/dialogue_turn_review_screen.dart — chapter/page chooser,
  12k-source windows with next/previous navigation, status and span previews,
  explicit whole-turn manual assignment for fully unknown complete turns.
- lib/features/reader/voice_cast_screen.dart — route from the existing
  Dialogues tab, alongside its previously available quick checks.
- test/domain/dialogue_turn_review_test.dart — **14 authored, unexecuted**
  tests for quoting styles, dash-line dialogue, interruptions, unfinished
  excerpts, partial labels, consecutive different voices, contradictions,
  explicit narrator, SHA-256, pending-source exclusion, reading anchors,
  emoji/UTF-16, bounded windows and truncation.
- test/data/dialogue_turn_review_store_test.dart — **3 authored, unexecuted**
  SQLite integration tests: accepted label persistence and original book
  unchanged; refusal to override a locked overlapping source label; and
  refusal to label a forged/stale quote.

## Known limitations

Quoting punctuation is culture/author-dependent. Nested quotation marks,
apostrophes, dialogue without explicit delimiters, multiline dash passages,
a review window that begins *inside* an already-open quotation, and source
extraction changes can require manual correction; such situations must not
cause automatic cast propagation. A dash at the start of a line is treated
as a candidate turn, not proof of speech. Source labels can span multiple
turns; the review UI will reflect that coverage but must not assume a
new speaker switch without explicit confirmation.

The older diagnostics tab remains available for a broader issue summary;
the detailed editor adds paging, character-by-character label visibility,
dash-line recognition and a safe manual whole-turn action.

**Verification status:** only source-code and targeted structural readback
checks were performed. No Flutter SDK compilation, tests, native builds or
on-device voice playback checks. Draft PR #1 remains open.
