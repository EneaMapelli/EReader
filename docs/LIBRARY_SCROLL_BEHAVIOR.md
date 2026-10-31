# Library scroll and return behavior (2026-10-31)

Scope: M1/M6, library usability and accessible long-catalog navigation.
Branch: feature/m0-flutter-foundation.

## Behavioral contract

1. The library owns a single ScrollController for its result list.
   Opening a book pushes the reader on top of the same library route.
   The scroll controller remains alive, so returning to the library keeps
   the existing viewport without scrolling to the first imported book.
2. A *change of view* (search input, format, reading shelf, collection,
   favorite filter, activity filter, sort order, or Clear filters) resets
   the results scroll offset to zero. This is intentional: the first
   matching/sorted book must be visible after the catalog changes, not an
   arbitrary position from a previous longer result set.
3. The controller uses keepScrollOffset=false: no stored PageStorage offset
   is resurrected if a filter produces zero results (unmounting ListView)
   and clearing the filter creates a new list. Position is not persisted
   between application launches.
4. A "Back to top of library" icon button appears beside the result count
   once the results list is scrolled more than 480 logical pixels. Its
   tooltip is exposed to screen readers. Activating it animates back to
   offset zero in 250 milliseconds and hides the button again.
5. The result count remains available on both desktop and narrow screens;
   sorting and filtering do not modify saved book positions or cloud consent.
6. The existing lazy row FocusNodes, stable book IDs, scrollable filter panel,
   book popup actions and Android SAF/Windows drag-and-drop remain unchanged.

The Back-to-top control is deliberately not shown for a short catalog or
while an empty filtered view is displayed. Its visibility changes only when
crossing the 480-pixel threshold, not on every scroll frame.

## Implementation and regression coverage

- lib/features/library/library_screen.dart: private controller, threshold
  listener, central _changeCatalogView helper, anchored reader navigation,
  back-to-top action, and controller disposal.
- test/features/library_scroll_restoration_test.dart: tests for 45 locally
  imported TXT books, deep scrolling and action visibility, smooth return to
  top, zero-result search/clear transitions, format/sort changes, and opening
  and returning from the reader without changing the viewport.
- Existing library responsive layout, focus lifecycle and keyboard tests
  remain required regression gates.

## Verification

Code and tests have been committed, but **Flutter/Dart is not installed in
this environment and tests have NOT been executed**. No native build or
GitHub Action has been started.

Manual acceptance on Windows and Android:
1. Import or load at least 50 books, scroll down, open a TXT book, go Back:
   library viewport should remain near the same title/position.
2. After scrolling, type an unmatched search query; clear it and check that
   the first book is shown instead of an empty/offscreen region.
3. Change filters/sort after scrolling; verify the first matching book is
   visible and saved per-book progress/favorites/shelves are unaffected.
4. Check the top button with mouse, touch, keyboard navigation, TalkBack and
   Narrator; confirm it vanishes when the list is back at the top.
5. Repeat on a small phone while the filter panel and virtual keyboard are
   open, and after returning from an EPUB/PDF reader.

These changes do not change milestone-completion percentages; native tests
and accessibility sign-off remain required.
