# Library favorites — quick book organization

Implemented in `feature/m0-flutter-foundation` on 2026-10-29.

## Visible reader experience

The library list now shows an explicit star button for every book.
Tapping it marks or unmarks the title as a **favorite**, without
opening the book or advancing narration. The favorite flag is stored
immediately, remains after restarting EReader and is reversible.

The existing format, opened/unopened and text search filters gain a
**Favorites** filter chip. Selecting it combines the constraints
(logical AND), rather than replacing title search or format selection.
The sort menu also adds **Favorites first**; starred titles sort by
case-insensitive title, followed by unstarred ones in that order.
Clear filters clears only search, filter and sort controls, **not**
the persistent favorite flags. Default library order is unchanged.

Favorite is an explicit user selection: it does not mean a book was
completed, is currently being read or has any positive listening time.

## Local storage

SQLite **v20** adds `books.is_favorite INTEGER NOT NULL DEFAULT 0`
with a `CHECK (is_favorite IN (0, 1))` constraint. The upgrade from
v19 is a transaction; all older book rows default to unstarred. The
field is surfaced as `BookRecord.isFavorite` (default false),
preserved by `atOffset()` and included in new local JSON, with
missing values in legacy JSON defaulting to false.

The `setBookFavorite` store API rejects unknown books. It updates
only the favorite column. It never modifies text progress, chapter
anchors, explicit opened timestamps, TTS/LLM profiles, cloud consent
or imported file hashes.

## Portable library backups

New backups include the favorite state in **both** the standalone v20
SQLite snapshot and manifest book entry. The inspector verifies that
the manifest boolean agrees with the database value, refusing an
inconsistent or malformed backup before importing.

Import compatibility remains **SQLite v17–v20**. Older backups lack
the column and restore their books as unstarred. As with existing
bookmarks and PDF pages, favorites are restored only for books
actually missing from the destination library. A known local book
is never overwritten or re-starred by a backup.

No automatic network transfer, paid API calls or secret material
are involved.

## Test coverage authored, not executed

- `test/data/library_favorites_test.dart`: fresh v20 schema, migration
  from v19, restart, independently tagged books, deletion, source
  position and legacy JSON.
- `test/domain/library_catalog_test.dart`: combine favorite filters
  with format/search/activity and deterministic favorite-first sort.
- `test/features/library_catalog_widget_test.dart`: star button,
  Favorites chip, Clear filters, sorting and unstar behavior.
- `test/data/library_backup_test.dart`: manifest/SQLite favorite
  values agree.
- `test/data/library_backup_restore_test.dart`: v20 favorite
  round-trip; local preference precedence; manifest tampering
  refusal; legacy v19 unstarred fallback.

Flutter/Dart is not available in the connected editing environment.
These test cases have **not** been executed. No Windows/Android
build or GitHub Action has been launched. Real device UI, focus,
tap-target and backup behavior remain acceptance requirements.
