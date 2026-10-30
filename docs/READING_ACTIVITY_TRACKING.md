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
Backup preview now accepts schema v23 in addition to v17–v22.
Deleting a book deletes its activity rows by foreign-key cascade.
There is no automatic cloud analytics or API spend.

Authored tests cover aggregate persistence, migration, deletion, idle /
bounded-time sampling, input limits, and goal edits. They are **not executed**
in this development session. No Windows/Android builds or GitHub Actions.
