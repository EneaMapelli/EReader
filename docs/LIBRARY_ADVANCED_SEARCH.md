# ER-034 — Offline advanced library metadata search (2026-10-30)

This increment extends the existing **Search library** field. The library
still searches *only stored catalog metadata*: title, author and series.
There is no book-body extraction, full-text index, upload, cloud provider,
telemetry, migration or change to the currently selected reading position.

## Search syntax

| Input | Meaning |
| --- | --- |
| `atlas` | Case-insensitive substring in any of title, author or series |
| `atlas writer` | Both terms must match; they can occur in different fields |
| `"space opera"` | One contiguous phrase within one catalog field |
| `title:atlas` | Only the title |
| `author:"Ada Writer"` | Author contains the exact phrase |
| `series:"North Star" title:atlas` | AND of independent field-qualified terms |

- Unqualified terms search any of the three fields. All terms combine with
  logical **AND**; not OR. Existing single-word queries keep their behavior.
- Prefixes `title:`, `author:` and `series:` are case-insensitive. Other
  prefixes (for example `publisher:`) are **literal query text**, not SQL.
- Quotes group phrases with spaces. An unmatched quote or an empty term
  yields a visible search error and **no matches**, not a broad match.
- For predictable performance and memory use, a query is limited to 256
  UTF-16 code units and 16 terms. Invalid inputs are shown in the TextField
  using `errorText`. The search-help button explains syntax and scope.
- The source `BookRecord` objects and SQLite tables are not altered by
  searching. Existing format, manual shelf, favorites and collection filters
  still combine with the advanced query.

## Boundaries

This is metadata-only search, not ER-034's proposed SQLite FTS5 index over
EPUB/PDF/TXT bodies. Search results are not guaranteed to normalize diacritics
(`e` versus `é`), stemming or word morphology. A search phrase is a
literal contiguous substring after lowercasing, not a token-boundary or
semantic embedding search. The entire search remains local to the device.

## Verification

Authored pure Dart/domain tests in
`test/domain/library_search_query_test.dart` cover legacy substrings,
cross-field AND, quoted phrases, field prefixes, Unicode, malformed input,
bounds and immutable parsed terms. UI tests in
`test/features/library_catalog_widget_test.dart` cover user input,
combination with filters, help and clearing invalid searches.

**Flutter analyzer and tests were not executed in this increment.**
No Windows or Android build was triggered and GitHub Actions were not run.
