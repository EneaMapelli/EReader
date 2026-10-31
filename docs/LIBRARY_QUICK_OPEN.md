# Quick open books in large catalogs — 2026-10-31

Branch: feature/m0-flutter-foundation. Scope: M1 library usability and M6 keyboard access.

## User experience

- On a populated library, tap the **Quick open a book** (bolt) icon beside
  the offline full-text search and reading-stats controls, or press
  **Ctrl/Cmd+J** when the foreground library has no active text editor.
- A searchable dialog opens with immediate focus. Type terms from the
  book title, author or series. Matching is case-insensitive; all terms
  must occur, possibly across different metadata fields.
- The most relevant title prefixes rank ahead of other title matches and
  author/series matches. With no query, recently opened books appear
  first, then the remaining titles alphabetically.
- The catalog is scanned fully but only the first 40 ranked items are
  shown. Search retains only the 40 best matches in memory (bounded top-K
  insertion) while still counting all matches. Ranking is recalculated
  only when the query changes; pressing arrow keys only updates an
  integer selection index, avoiding repeated whole-catalog scans.
  The exact match count is announced in a live accessible label.
  A book excluded from those 40 can still be found by refining its query.
- Press **Up / Down** while the search field is focused to move a
  highlighted selection through the 40 visible results. The list scrolls
  automatically to keep that result in view; the current selection is
  exposed both visually and in a live accessible label. Up/Down stop at
  the first/last entry (no wrapping).
- **Enter** opens the currently selected result for a nonempty query.
  With a blank query, Enter opens nothing until an arrow key has
  explicitly selected a result. Cancel/Escape closes without opening
  a reader or changing the catalog.
- Quick open searches the **entire** saved library, even when the main
  catalog view is filtered. On cancel the filter, sort and scroll position
  stay untouched. On selection the existing reader route is used and
  back navigation returns to the same main catalog view.
- No book is opened or narrated merely by searching; book contents,
  local paths, cloud TTS and provider requests are not accessed by the
  quick-open index. No external search requests are performed.
- The toolbar uses three compact icons on narrow phones (Quick open,
  offline full-text search, reading stats) instead of a long text button.
  The dialog caps list height and can scroll above an on-screen keyboard
  or when system text scaling is increased.

## Implementation

- lib/features/library/library_quick_open.dart:
  pure ranked matching, result cap and locally filtered dialog.
- lib/features/library/library_keyboard_shortcuts.dart:
  guarded Ctrl/Cmd+J binding and F1 shortcut-help explanation.
- lib/features/library/library_screen.dart:
  shortcut, toolbar, selection-to-reader integration and stale-ID guard.
- test/features/library_quick_open_test.dart:
  relevance, empty recent ordering, cross-field terms, limit and a
  1,000-title data set.
- test/features/library_quick_open_widget_test.dart:
  query/autofocus, cancel and selection, count/limit, large text,
  Up/Down/Enter behavior, offscreen highlight scrolling, Esc dismissal,
  and reset when a query changes.
- test/features/library_quick_open_test.dart:
  also checks selection clamping for empty, single and bounded lists.
- test/features/library_keyboard_shortcuts_test.dart:
  Ctrl/Cmd+J mapping, modifier/focus/route safety.
- test/features/library_keyboard_integration_test.dart:
  catalog filters unchanged on cancel and reader selection via quick open.

## QA gates

**Implementation and test source committed; Flutter/Dart not available here.**
No widget tests, native builds or GitHub Actions were run.

For native QA: try a 1,000+ title catalog on Android and Windows, type
partial titles/authors and multiword phrases, use Up/Down repeatedly
and Enter to open a highlighted item beyond the first viewport, verify
blank Enter does not select a book, then Escape/cancel. Activate
Ctrl+J after closing a modal dialog, test both filtered and unfiltered
catalogs, verify Narrator/TalkBack results counts and 150%-200% text with
keyboard open. Check no unintended TTS start and no new OS/file/network
permissions. This increment does not change release-readiness estimates.
