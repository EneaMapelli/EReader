# ER-034 — Optional offline book-body search (SQLite v26)

This is a first, deliberately bounded local full-text index. **It is
disabled by default** and is never built automatically at application
startup, after an import, or when the user opens a book.

## User workflow

In the library, choose the **Search inside books offline** button next to **Reading stats**. The sheet
contains a **Keep a searchable copy on this device** switch. Turning it On
creates a local FTS5 virtual table, but does not yet copy any book text.

Choose **Index next 10 books** to process a bounded group. The app shows
progress; **Cancel batch** stops between books. Continue manually until the
pending count reaches zero. Each processed book is recorded as indexed or
skipped so failed items are not retried in an endless loop. **Reset** clears
all indexed content and skip markers while retaining consent, enabling an
explicit fresh pass. Turning the switch **Off** asks for confirmation,
drops the FTS5 table, removes markers, and stops future indexing.

Search treats up to 8 Unicode word tokens (120 input characters maximum)
as literal AND terms. FTS query syntax typed by a user is **never passed
through as FTS operators**: text is split into bounded Unicode words,
wrapped in quoted tokens, and joined by AND. Search results are capped at
30 book hits, display a short snippet from the local content and let the
user open the book at a **validated original-source text position**.
For a multi-word query the destination is now the **shortest nearby
passage containing every distinct search term** (up to 320 UTF-16 code
units), regardless of term order. If all terms occur only far apart,
the conservative first complete word remains the fallback. Equal-width
passages resolve to the earliest. Repeated query words do not require
separate occurrences.

The offset is computed in **UTF-16 code units** from indexed canonical
text **only when a result is selected**: regular search keystrokes return
short FTS5 snippets without loading every matching book's full text.
The selected source offset and a bounded slice of surrounding source
(including the entire nearby multi-term passage) are checked against
freshly extracted text before opening. A match word left at the same
offset after nearby content has changed is **not** sufficient. This
context is transient, not written to the FTS database or logs.
Memory usage of this on-tap scan is bounded by the number of query terms,
rather than by the number of occurrences across the document.
TXT and EPUB land at the corresponding visual source/segment; EPUB
reuses source-exact paragraph highlights. PDF matches enter text mode
instead of treating the offset as a physical viewer page. If the text
changed or the offset is stale, the reader opens at the previously saved
progress and explains the fallback. Merely selecting a search result
does **not** save a new narration checkpoint or start TTS.

The initial implementation handles TXT, EPUB and PDFs with an existing
selectable text layer. It uses `PrototypeDocumentDecoder`, the same
reader-side extraction path. **No OCR**, scanned-PDF interpretation, online
indexer, embeddings, model/API calls, telemetry or cloud sync is involved.

## Limits and data boundaries

- Source files must be ordinary files, not symlinks, and at most **12 MiB**.
  Extracted content must be nonempty and at most **2 Mi UTF-16 code units**
  per book. Large or unreadable books are marked skipped for this pass.
- Total indexed source text is capped at **64 MiB of UTF-8 data** across
  the library. Once the budget is reached, additional books are marked
  skipped; reset and re-index to refresh. This is a source-text budget,
  not an exact upper bound for SQLite/FTS5 index or WAL disk usage.
- Each batch processes **at most 20 books** at the persistence API; the
  interface uses 10. A cancellation is cooperative **between** books; a
  long PDF decode already in progress cannot currently be interrupted.
- The parser copies extracted private book text into a **local SQLite
  FTS5 index**. This is much more sensitive than the older metadata-only
  search, so the separate explicit opt-in matters. It is *not encrypted*
  at the application level.
- Turning Off or Reset deletes rows/drops the table from the live database,
  but is **not cryptographic secure erase**. Deleted bytes may survive in
  filesystem, SQLite WAL or device backups. Explicitly exported private
  SQLite backup snapshots may contain indexed book text and are never
  altered or removed by an in-app clear command.
- Deleting a book also deletes its FTS rows before the original book row
  is removed. Foreign-key cascades clean up per-book indexing markers.
- Search results contain read-only text snippets and optional validated
  visual destinations. Opening one does not advance narration, invoke a
  voice/cloud provider, or write reading progress. Later explicit reading
  interactions follow normal reader bookmark rules.
- An older SQLite runtime without FTS5 must fail the explicit enabling
  action cleanly. It must not fail initial application startup or create
  a partial index without consent.

## Schema and restoration

SQLite **v26** adds `library_fulltext_settings` (single opt-in boolean),
`library_fulltext_jobs` (book ID, indexed/skipped bit), and
`library_fulltext_source_state` (only source file size and last-modified
timestamp, no text or original path). It **does not** create the virtual
FTS5 table on startup. Enabling creates
`library_fulltext_fts(book_id UNINDEXED, body)` explicitly.
Disabling drops the FTS table and clears job and source-state markers.

Backup inspection now accepts SQLite **v17 through v26**. The existing
explicit SQLite snapshot contains all currently active local data,
including an index if enabled, so exported backup storage can grow.
The portable **add-only** restore does not activate a destination index,
does not import search consent, and does not reconstruct indexed text
from the snapshot. Indexing there requires a separate user opt-in.

## Test status

Authored `test/data/library_full_text_index_test.dart` for default
off/no FTS table, explicit consent, real TXT search, query literal handling,
indexed and skipped counts, cancellation, reset, deleting a source book,
persistence and the v25→v26 migration. UI regression coverage in
`test/features/library_full_text_search_widget_test.dart` checks opt-in,
query, result opening, cancellation/reset affordances and deletion
confirmation. Native-free tests can inject a stub decoder for malformed
PDF/scanned-source paths.

**Dart/Flutter tests and native Windows/Android builds have NOT been
executed in this increment**. No GitHub Actions run was started.

## Explicit incremental refresh for new or modified books

Newly imported books have no job marker, so they appear in the pending
count and can be indexed in the next explicitly requested batch.
Existing indexed/skipped books are not re-extracted on every refresh.

Use **Check changed books** to asynchronously compare the saved file size
and modified timestamp against the currently managed local files. If either
changes, the old FTS content is deleted, the old job/fingerprint is removed,
and that book becomes pending for the next **Index next 10 books** operation.
This check never extracts book contents or starts a TTS/cloud session.
A cancelled check may be repeated without affecting unchanged books.

This intentionally detects normal file modifications, not adversarial
changes that keep both file size and modification timestamp identical.
An index can remain stale until the user checks, which is why opening
a result independently verifies its expected source text. Indexing and
changed-book checking are mutually exclusive operations; cancel is
cooperative between files.

## Navigation and incremental regression coverage

- `test/domain/library_full_text_jump_test.dart`: source-offset validity,
  Unicode word boundaries, and protection against stale text.
- `test/data/library_full_text_index_test.dart`: stored search destinations,
  modified-file invalidation, pending batches and cooperative cancellation.
- `test/features/library_full_text_search_widget_test.dart`: forwarding the
  selected UTF-16 destination and manually checking/re-indexing changed files.

The implementation and tests are committed, but **no Flutter analyzer,
Dart tests, native builds or GitHub Actions were executed**.

## Proximity-ranking regression coverage

Added domain scenarios for the shortest multiword passage, reversed word
order, deterministic ties, duplicate words, far-apart fallback and UTF-16
surrogate pairs. Source-context tests invalidate an otherwise-identical
word after an adjacent passage changes. Integration coverage uses a real
indexed TXT file to verify the closest cluster and the subsequent purge of
stale indexed text. All locator scans remain deferred until a result is
selected; queries do not materialize full book bodies.

## All words, Any word and Exact phrase query modes

The search sheet now supports three local lexical modes. **All words**
remains the default, backward-compatible behavior.

- **All words** uses separately quoted Unicode terms joined with `AND`.
  Every term must appear in a book. Opening it favors the shortest
  local cluster of terms or a clearly identified distant-term fallback.
- **Any word** uses quoted, parameterized terms joined with `OR`.
  A book qualifies if **at least one** term occurs. SQLite FTS5's rank
  orders results by lexical relevance; ties break consistently by title
  and book ID. Opening a hit chooses the earliest actual matching
  whole word, even if the first query term is absent. Alternative
  passages show at most six source-ordered matches, grouping nearby
  occurrences without falsely claiming all terms were present.
- **Exact phrase** builds one quoted FTS5 phrase. Words must appear
  consecutively and in the specified order. SQLite's `unicode61`
  tokenizer treats punctuation as a separator, so matching can cross
  commas or sentence boundaries. Phrase matching is **token adjacency**,
  not verbatim punctuation or semantic similarity.

All three modes accept at most **eight terms / 120 query characters**.
User-entered FTS5 syntax is never passed through: only sanitized literal
Unicode tokens are quoted into the internal expression. Queries remain
parameterized; source text and index contents stay offline. Opening a
result goes through the existing UTF-16 source-offset and context
verification in the reader, without changing the saved progress or
auto-starting TTS. Indexing consent, storage and budgets are unchanged.

These are **lexical modes**, not model/embedding-based semantic search;
synonyms or related concepts with no shared words are not inferred.

Domain, SQLite and widget regressions now cover OR syntax, books matched
by only the second term, bounded previews, source navigation, and the
All words/Any word/Exact phrase selectors. Tests were authored, but
**not executed** here (Dart/Flutter SDK unavailable); no Windows/Android
builds or GitHub Actions were started.

## Alternative passages within a matching book

Each indexed book result now has a **Show matching passages** action. Opening
it loads only that book's indexed text and searches for alternative source
locations on a worker isolate. Normal typing and the main search list
continue using short SQLite FTS5 snippets without scanning the full texts
of all results.

- Up to **six** passage previews are shown by default (API maximum ten).
  Each preview consists of a bounded, local-only text excerpt and a
  source-exact UTF-16 destination. They are **not** stored as bookmarks.
- For multiple terms, each candidate contains **all distinct words** within
  320 UTF-16 code units. Candidates are ordered by shortest interval,
  breaking equal-width ties by original book order. Nearby overlapping
  candidate windows are collapsed so the same paragraph does not appear
  repeatedly.
- For one term, separate matching occurrences remain available.
  If all terms of a multiword search occur only far apart in the book,
  the list displays a single clearly identified **first-term fallback**
  instead of fabricating a passage containing all the terms.
- Selecting any preview passes a transient source jump to the existing
  reader. The reader again validates the exact matched text and its bounded
  surrounding context against a newly decoded document; stale results
  fall back to saved progress without auto-starting TTS.
- The preview scanner retains only the most recent occurrence per query
  word and a fixed-size list of candidates. The file and index budgets
  remain unchanged. A brief secondary memory copy is made when sending
  the selected book text to the worker isolate.

This is **lexical proximity ranking**, not embedding-based or semantic
search. Searching for synonyms or meanings that do not share query words
is still outside ER-034's implemented scope.

Regression tests: `test/domain/library_full_text_passages_test.dart`
covers ranking, de-duplication, single-word alternatives, distant fallback,
UTF-16 boundaries and limits. The SQLite and widget regression suites
also check selection and opening of an alternative passage.

The tests were **authored but not executed** here: Dart/Flutter SDK is
unavailable. No Windows/Android builds or GitHub Actions were started.
