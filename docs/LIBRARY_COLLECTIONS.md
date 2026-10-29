# EReader — Custom book collections

**Implemented in source:** 2026-10-29, branch
`feature/m0-flutter-foundation`.

## Features

The library now supports **custom named collections** (for example,
"Research", "Books for a trip", or "Science fiction"). These are
categories, **not folders on the filesystem**: they never copy, rename
or move original EPUB/PDF/TXT files.

- The **Manage collections** toolbar action creates, renames and
  deletes collections, including empty ones. Delete requires
  confirmation and deletes only the category and its memberships.
- The **More → Book collections** action on a book opens a checklist
  of all categories. Books can belong to zero, one or many categories.
  Creating a category from this sheet also adds that book to it.
- A **Collection** dropdown allows selecting one category to filter the
  catalog; "All collections" is the initial selection. The filter
  combines with text search, file format, Favorites, manual reading
  status and opened/unopened activity. "Clear filters" resets the
  collection filter but never changes saved membership.
- Names are trimmed, validated (1–80 visible UTF-16 characters,
  no control characters), and unique case-insensitively in SQLite.
  Membership toggles are idempotent.

## Storage

SQLite **v22** adds `book_collections` (ID, unique name and created
time) and the many-to-many `book_collection_members` join table.
Foreign keys cascade membership cleanup when a book or collection is
deleted. Neither deletion removes a different book. Migration from
v21 is transactional; every existing library retains its previous
books, bookmarks, star flags, shelf statuses, progress offsets,
narration anchors and voice/cloud settings.

New internal store APIs include `collections`, `createCollection`,
`renameCollection`, `deleteCollection`, `listBookCollections`,
`collectionBookIds`, and `setBookCollection`.

## Portable backups

The export's **v22 standalone SQLite snapshot** includes both tables.
The manifest contains a top-level `collectionCatalog` with every
collection name (**including empty categories**) and a
`collections` list for each book. These lists are built from the
snapshot, rather than live mutable UI state.

The restore inspector validates every collection row, ID/name, every
membership foreign key, collection counts, and each book-level
manifest entry against the SQLite data. A mismatched manifest, extra
membership or corrupt collection ID is rejected before import.

Portable restore accepts **SQLite v17 through v22**. Older backups
without the new tables have an empty catalog. With user consent,
all missing collection names (including empty ones) are created.
Existing local collections with the same case-insensitive name retain
their local identity. Source-book memberships are copied **only when
that book is imported as a missing book**, never for books already
on the destination device.

The preview reports the number of new collections, and
**collections-only restore** is possible even when no new books need
importing. This is add-only: previously created categories or
successful earlier books may remain if a subsequent book import fails.

The backup is local and unencrypted. No API key, cloud consent or
native OS secret vault is restored.

## Authored regression tests (not run)

- `test/data/library_collections_test.dart`: SQLite v22 migration,
  naming, uniqueness, many-to-many membership, deletion cascade,
  restart and source progress independence.
- `test/domain/library_catalog_test.dart`: collection filter
  combination with query, Favorites, format and manual reading shelf.
- `test/features/library_collections_widget_test.dart`: create,
  rename, delete, membership toggles and library integration.
- `test/data/library_backup_test.dart`: complete snapshot and
  manifest catalog/memberships.
- `test/data/library_backup_restore_test.dart`: case-insensitive
  destination merge, multiple memberships, empty collection recovery,
  tampering rejection and v21 legacy compatibility.

**No tests or Windows/Android builds were run**, and no GitHub
Actions were dispatched. Native acceptance still requires
end-to-end checks on a physical Android device and Windows.
