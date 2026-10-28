# M1 — library opening history filters

**Branch:** `feature/m0-flutter-foundation` · **Date:** 2026-10-28.

## What changed

The main library offers a new **Recently opened** sort, plus three mutually
exclusive **All activity**, **Opened**, and **Never opened** filters. The
selection combines with the existing title/author/series search and EPUB/PDF/TXT
format chips. **Clear filters** resets activity, format, search and sort.

These are **opening history** states, not audiobook progress, reading-duration
statistics, or "finished" flags: simply opening a reader records the existing
SQLite `last_opened_at` timestamp. A book never opened in this installation
remains **Never opened**, even if an imported backup carries a source progress
position. An opened book remains **Opened** even if its progress offset is zero.

**Recently opened** puts the latest-opened book first; never-opened books follow
in import order. Equal dates use deterministic title/ID fallbacks. Neither
sorting nor filtering modifies progress, timestamps, source anchors or consent.

## Storage and privacy

No new SQLite table or migration. Activity uses the existing v14 field and
is read by `LibraryStore._fromRow` into a read-only `BookRecord.lastOpenedAt`.
This field is intentionally excluded from `BookRecord.toJson`, so generic
JSON export and imported backup records do not copy reading-activity history.
No cloud requests, local-file scanning, audio or LLM action is needed to filter.

## Authored tests — pending execution

- `test/domain/library_catalog_test.dart`: correct recent sorting,
  deterministic ties, opened/unopened intersection with search and format.
- `test/data/recent_book_resume_test.dart`: persisted per-book activity after
  SQLite close/reopen; no narration cursor update.
- `test/features/library_catalog_widget_test.dart`: activity chips,
  visibility, sort ordering and **Clear filters** recovery.

Run with the existing local Windows test harness during the requested
integration phase. Do **not** equate source-level checks with a passing Flutter
run or with Windows/Android acceptance.
