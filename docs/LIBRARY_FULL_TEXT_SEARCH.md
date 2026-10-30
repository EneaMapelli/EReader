# ER-034 — Optional offline book-body search (SQLite v26)

This is a first, deliberately bounded local full-text index. **It is
disabled by default** and is never built automatically at application
startup, after an import, or when the user opens a book.

## User workflow

From the library toolbar choose **Search inside books offline**. The sheet
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
user open the book at its **previously saved reading position**. Jumping
to the precise matched source location is **not yet implemented**.

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
- No derived data is used to advance audio, voice characterization, reading
  bookmarks or user progress; the results are display-only snippets.
- An older SQLite runtime without FTS5 must fail the explicit enabling
  action cleanly. It must not fail initial application startup or create
  a partial index without consent.

## Schema and restoration

SQLite **v26** adds only `library_fulltext_settings` (single opt-in
boolean) and `library_fulltext_jobs` (book ID and indexed/skipped bit)
on migration. It **does not** create the virtual FTS5 table. Enabling
creates `library_fulltext_fts(book_id UNINDEXED, body)` explicitly.
Disabling drops that table and clears the index job markers.

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
