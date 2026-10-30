# ER-033 — Local timed reading and TTS aggregates (2026-10-30)

This extends the read-only library statistics dashboard with **actual local
sampled activity time** and an editable daily goal (default 20 minutes,
0 disables it). It does not use any cloud API or track book text.

## Counting contract

- SQLite v23 stores seconds in a unique `(book_id, local_day, mode)` row;
  modes are `visual` and `tts`. No event timeline or prose is saved.
- One `ReaderActivityTracker` belongs to an open reader route. It uses a
  monotonic stopwatch and samples every 15 seconds. Each sample is capped
  at 30 seconds to avoid crediting hours when the app was suspended.
- Audio has exclusive priority while `ReaderPlayer.isPlaying`. Android
  background playback can count only while the current MediaSession owns
  this player. Windows and non-owned background sessions are not counted.
  Player intent can include short buffer/startup times, so this is an
  **estimate of TTS playback activity**, not guaranteed audible duration.
- Visual time starts only after a reader gesture, while the reader route
  is current, and expires after three minutes without interaction. It is
  not actual eye tracking. Reader visibility alone is insufficient.
- Pausing, navigating, switching a voice, returning to foreground,
  disposing the route and entering the background cause a flush of the
  previous mode. No double counting for simultaneous listening/reading.
- The local calendar key is `YYYY-MM-DD`. Time-zone changes and activity
  crossing midnight within a sample can make up to one sample fall into
  the ending date's bucket. Background operating-system suspension can
  undercount activity. This conservative policy is intentional.

## Goal and dashboard

The library's **Reading stats** sheet now shows seven-day visual/TTS
minutes, a 0–240-minute goal selector (preset values), daily totals,
per-day completion bars and the number of days meeting the goal.
The goal is defined over **visual + TTS seconds together**, so TTS use
also advances it; the modes remain separately visible. Initial data is
zero; no attempt is made to reconstruct past sessions from `last_opened_at`.

## Privacy, portability, verification

Daily aggregates and goals remain in local SQLite. Export's SQLite snapshot
includes them, but the add-only restore intentionally does **not** import
activity history or goals to avoid silently merging personal time data.
Backup preview accepts schema v17–v24 after adding the local opt-out.
Deleting a book deletes its activity rows by foreign-key cascade.
There is no automatic cloud analytics or API spend.

Authored tests cover aggregate persistence, migration, deletion, idle /
bounded-time sampling, input limits, and goal edits. They are **not executed**
in this development session. No Windows/Android builds or GitHub Actions.

## Per-book activity drilldown (2026-10-30, next increment)

- The **Reading stats** sheet shows up to ten books with measured activity
  during the seven latest local calendar days, sorted by combined timed
  reading + timed TTS, descending. Equal totals sort by title (case-insensitive)
  and then immutable book ID. Books with no activity during that period are
  omitted from this leaderboard; it is not a ranking of reading completion.
- Selecting a book opens a **read-only detail sheet** with separate visual/TTS
  durations for the week and for all recorded history, followed by seven
  local daily rows. Small durations remain visible in seconds rather than
  being silently rounded down to zero minutes.
- `mostActiveReadingBooks` runs one bounded, aggregated JOIN query against
  SQLite; limits are 1–50, UI uses 10. Details use a single-book parameterized
  query, not a loop across a large catalog. There is no content extraction,
  upload, cloud spend, tracking of actual page turns or additional schema
  migration for per-book queries (the later opt-out is schema v24).
- `weeklyReadingActivity(bookId: ...)` validates the book and scopes its
  daily rows. `bookReadingLifetimeTotals` accounts for dates outside the
  current week but never invents activity before tracking was introduced.
  Deleted books have no lingering rows because of the v23 foreign key.
- The **daily goal is global** across all books. A book's weekly breakdown
  deliberately does not imply it has its own goal. Activity is a conservative
  approximation, subject to sampling and device lifecycle limitations.

Additional authored tests check isolation between books, recent-week cutoff,
stable tie ordering, size limits, historical totals, rename persistence,
reopen, cascade deletion, second-level duration formatting and a widget
navigation drilldown. Tests, analyzer and native builds remain **unexecuted**
in this session per owner instruction; do not mark them passing.

## Delete local activity and inactivity accuracy (2026-10-30)

The statistics sheet now contains **Clear all timed activity**, and a
book's detailed sheet has **Clear timed activity for this book**. Both
actions present a confirmation dialog with Cancel as the safe path.
Deleting history affects only daily activity aggregates: not books,
bookmarks, source offsets, manual shelves, voice choices, subscriptions,
consents, collections or the separately stored daily goal.

- Per-book deletion uses a parameterized SQLite DELETE scoped to the
  selected immutable book ID. History for other books is untouched.
- Global deletion removes every daily aggregate row, even for books
  hidden by filters and days older than the weekly display.
- Each deletion is idempotent and returns the number of affected aggregate
  **rows**, not the number of individual reading sessions.
- The global leaderboard refreshes when a book detail sheet closes.
- Deletion affects the **active database**. Older exported private backups
  containing a SQLite snapshot are **not** overwritten or deleted. The
  OS/SQLite filesystem may retain recoverable deleted bytes; this action
  is not a cryptographic secure erase.
- **Activity measurement continues for new reading/TTS time** after
  deletion unless the separate persistent tracking preference is Off.

The recorder now snapshots the remaining visual-reading idle budget at
the **start** of each monotonic timer interval. The accumulator clips
elapsed visual time to both the normal 30-second sample limit and that
remaining budget, so a timer callback delayed past the three-minute idle
deadline cannot credit the entire trailing sample. TTS samples remain
separately bounded by 30 seconds and do not use the visual idle deadline.
A suspended process can still cause *undercounting*, and the visual
gesture-based heuristic is not proof that the user actually read.

Regression tests were authored for per-book/global deletion, unrelated
book isolation, preservation of progress/goal, idempotence, cancel/
confirm UI paths, history refresh and mid-sample idle deadline. These
tests were **not executed** in this iteration, and no Windows/Android
build or GitHub Actions was started.

## Persistent local tracking switch (SQLite v24)

The library's **Reading stats** sheet now has a **Track reading and TTS time**
switch, enabled by default on fresh installs and on upgrades to keep existing
behavior. Turning it Off persists a `tracking_enabled = 0` bit in the
existing `reading_activity_settings` singleton row, with a transactional
v23→v24 migration. The same value survives app restarts. Opting out:

- Prevents the reader from constructing its activity timer on the next open.
- Also prevents activity storage at the `LibraryStore.recordReadingActivity`
  boundary, including late callbacks and programmatic writes. Any running
  tracker checks the preference and drops its fractional elapsed remainder.
- Does **not** pause TTS, alter the open book, delete existing history or
  change the daily goal. Existing history remains visible in weekly and
  per-book dashboards, even while tracking is disabled.
- Re-enabling tracks only **new** activity; previously disabled time is
  not reconstructed. The app does not backfill from book-open timestamps.
- Is a purely local preference, with no platform permission or networking.
  The explicit user-created SQLite backup carries both the setting and
  historical aggregates. Add-only restore does not import either the
  setting or activity aggregates to a different library.

SQLite's newer-schema guard and backup inspection accept v24; older v17–v23
backups stay supported. Tests have been authored for fresh defaults,
v23→v24 conversion, a partially downgraded schema marker, opt-out across
restarts, no new activity while disabled, re-enable, active-history
preservation, UI switch behavior and private SQLite export. They have
**not been executed** in this development increment. No Windows build,
Android build or GitHub Actions was triggered.
