# ER-033 — Local reading statistics (first increment)

Implemented on `feature/m0-flutter-foundation` as a read-only **Reading stats**
panel in the library. It reads all books irrespective of active search,
collection, format, favorite or shelf filters.

- Total catalog titles; manually selected To read / Reading / Finished
  counts and proportion marked Finished.
- Imported catalog formats (EPUB, PDF, TXT), starred favorites, distinct books
  opened at least once, and distinct books whose **last** opening timestamp
  was within the preceding 168 hours.
- Up to five most recently opened titles (latest opening first). Future
  timestamps caused by device clock skew are excluded from recent activity.
- Empty libraries produce zero percentages without division errors.

All figures are derived from existing `books` metadata in SQLite v22. No
schema migration, book text extraction, cloud calls, listener, tracking
permissions or narration/consent changes are required. The dashboard is
read-only and does not change the user's shelf selections.

**Interpretation:** Finished and Reading are *manual* shelf labels. The
single `last_opened_at` timestamp per book cannot measure actual sessions,
minutes, page counts, lifetime opening frequency, daily streaks or goal
completion. These remain a separate ER-033 increment requiring deliberate
activity event design and privacy/retention choices. Do not equate the
last-seven-days count with session counts.

Authored but **not executed** tests:
`test/domain/library_reading_statistics_test.dart` and
`test/features/library_reading_statistics_widget_test.dart`, covering empty
library, counts, inclusive 168-hour boundary, future timestamps, immutable
source, five-title cap and view-filter independence. Windows/Android builds
and GitHub Actions were not started.

## Second increment — 2026-10-30

The additional implementation in [READING_ACTIVITY_TRACKING.md](READING_ACTIVITY_TRACKING.md)
introduces optional local timing as separate daily aggregates (SQLite v23),
a seven-day visual/TTS dashboard, and an editable daily goal. This does not
change the meaning of the original manual shelf and last-opened counts above.
It is a bounded heuristic (recent gestures for visual reading; active
player intent for TTS), not biometric attention detection or exact acoustic
duration. Tests are authored but not run.
