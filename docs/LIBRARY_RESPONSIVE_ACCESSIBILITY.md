# Responsive library controls and book actions (2026-10-31)

Scope: M1 library experience, M6 accessibility.
Branch: feature/m0-flutter-foundation.

## UI changes

- Under 600 logical pixels wide the existing library search field stays visible;
  format, sort, reading shelf, collection, favorites and opened-history controls
  move into one **Filters & sort** panel, initially collapsed.
- The button displays the number of active nondefault filter/sort dimensions.
  Closing/reopening the panel never resets selected filters.
- A separate reset control appears when filters/sorting are active. It calls
  the existing view-only _clearFilters implementation, not SQLite deletion.
  Clearing filters does not unstar books, change shelf status or membership.
- The result count reads "Showing X of Y books", as a live semantic region
  on both compact and desktop screens. Searching still queries only local
  catalog metadata, not book contents.
- The expanded filter panel is independently vertically scrollable and
  height-bounded to 32% of the screen (105–235 logical pixels). Book results
  keep their own scroll area, avoiding filter rows consuming the whole phone.
- At 600 pixels and above, existing sort dropdowns, status/collection selectors
  and filter chips remain visible exactly as in the prior desktop design.

## Accessible compact book rows

- Under 600 logical pixels, each book keeps a separate accessible Favorite
  button and More action. The individual Reading shelf button moves inside
  More as three **CheckedPopupMenuItem** options (To read, Reading, Finished);
  the currently selected shelf is explicitly marked checked.
- More still offers Book collections, Edit book details and Remove book.
  These invoke the same existing guarded callbacks and confirmation flow.
- On wider layouts, the preexisting shelf button, favorite star and More
  remain three independent actions.
- Under 600 pixels with accessibility text at roughly 170% or larger,
  the app bar omits its redundant second-line count (the result count stays
  visible), title may span two lines and metadata up to three. The row is
  taller and not marked dense. Favorite moves into More as a checked menu
  action, retaining the same persistence callback but leaving room for text.
- Library book rows preserve stable FocusNodes across catalog rebuilds.
  Tab/Shift+Tab reaches the row and accessible controls; Enter activates
  the selected book through its existing onTap. Shift+F10 on a focused
  row or a long press on touch opens the same More action menu, never audio.
  Focused rows receive a visible, theme-aware highlight.
- Per-book FocusNodes and PopupMenu GlobalKeys are now owned by
  LibraryBookRowFocus states and released as their lazily built rows leave
  the ListView's cache area. They are **not** stored in an unbounded
  screen-wide map; a 1,000-book catalog creates focus resources only for
  visible/cached items. The keyed row wrapper and ListView's
  findChildIndexCallback preserve the same focus state when a visible
  book moves after sorting. Offscreen rows are reconstructed on demand.
  No background listeners are used.
- Book title and metadata text expose full accessible labels even when
  visually truncated. Each row has a stable key for regression testing.
- Compact More tooltips include the book title and mention shelf controls.

## Verification

New tests in test/features/library_responsive_layout_test.dart cover:
- narrow default layout, result count and preserved book visibility;
- filter expansion, chip selection, collapse and reset without deletion;
- compact More shelf selection and marked state, favorite star and actions;
- catalog search result count and clearing without affecting stored records;
- wide desktop layout unchanged;
- 390-pixel layout with 150% text scaling and no widget overflow;
- 390-pixel layout at 200% text, two-line book titles and favorite toggling
  with checked-state accessibility through the More menu;
- Shift+F10 and long-press context-menu activation without opening a book;
- existing focus identity when the visible book list is re-sorted;
- the desktop result-count announcement and 1,000-book lazy-list focus
  allocation/disposal regression cases in
  test/features/library_book_row_focus_test.dart.

**Validation status:** source changes and tests authored and committed;
Dart/Flutter is unavailable in this execution environment. No test run,
Windows compilation or GitHub Action was triggered. Native layout and screen
reader acceptance are still required before milestone sign-off.

Manual QA: Android 360x640/390x700, enlarged system text, Windows resized
below/above 600 px; toggle filters with existing selections, change shelf
from More, star/unstar and verify collections, edit and remove confirmation.
Use a real keyboard/screen reader to inspect labels and checked selections.
On Windows verify row focus with Tab, Enter to open a book and Shift+F10
for actions; on Android verify long press and the checked Favorite action.
Test fonts at 170%, 200% and 250%, including a 320-pixel screen.
