# Manual reading shelves — To read, Reading, Finished

Branch: `feature/m0-flutter-foundation` · 2026-10-29.

## User-visible behavior

Every book in the library can be assigned to a **manual reading shelf**:
**To read**, **Reading**, or **Finished**. The shelf is selected from
the small book-row menu; the saved choice also appears in each book’s
metadata subtitle.

- **All shelves** (default), To read, Reading and Finished are available
  in a dedicated library filter. The selected shelf combines via AND
  with search, format, favorites and opened/unopened activity.
- **Reading shelf** sort prioritizes Reading, then To read, then
  Finished. Ties are resolved by title and immutable book ID.
- **Clear filters** resets only the view controls, never the manual
  statuses or favorite stars.
- For small Android screens, the row exposes three compact actions:
  shelf, favorite and More. The More menu retains the earlier Edit
  book details and Remove book actions.

This **does not automatically change** when opening a book, when
reaching the end of the visual source, when TTS finishes or when using
the sleep timer. Marking Finished manually **does not seek, stop or
start TTS**, change a source anchor, or reset last-opened history.
Changing the status back to To read is always allowed. These shelves
describe an explicit user preference, **not** measured reading time,
book completeness or verified reading activity.

## Storage and migration

SQLite **v21** adds `books.reading_status` constrained to
`toRead`, `reading`, `finished`, default `toRead`. The v20→v21
migration is transactional. Existing books, including previously
starred or opened books, default to To read without changing their
other columns. `BookRecord.readingStatus` uses the same enum and
is preserved by `atOffset()`; JSON records from old installations
without this field use To read.

`LibraryStore.setBookReadingStatus` refuses missing book IDs and
updates only the shelf column.

## Local portable backup

Current standalone backups are SQLite **v21**. The book manifest
includes `readingStatus`, verified against the v21 SQLite
`reading_status` field. A mismatch or unknown status is refused
before any import. Restoring older SQLite **v17–v20** backups is still
supported: these lack a manual shelf and use the To read default.

The conservative restore imports the shelf **only for missing books**.
It never overwrites a local book's existing shelf, annotations, visual
PDF bookmarks, favorites, narration consent or source progress. No
remote service, account or paid API is used.

## Tests authored; device verification pending

- `test/data/library_reading_shelf_test.dart`: v21 migration from
  v20, persistence, explicit reversible states, JSON defaults, no TTS
  checkpoint changes.
- `test/domain/library_catalog_test.dart`: combined shelf search,
  favorites, format filters and deterministic reading-shelf sort.
- `test/features/library_catalog_widget_test.dart`: manual selection,
  shelf filter/Clear filters, explicit Finished and compact More menu.
- `test/data/library_backup_test.dart`: matching source manifest and
  SQLite shelf labels in an export.
- `test/data/library_backup_restore_test.dart`: v21 round-trip,
  local-state precedence, tamper rejection, v20 fallback and faithful
  v17–v19 fixture handling.

**No Flutter/Dart tests were executed in this environment**.
No Windows/Android builds or GitHub Actions were triggered.
