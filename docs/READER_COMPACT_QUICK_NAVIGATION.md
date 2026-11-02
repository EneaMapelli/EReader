# Reader compact quick navigation

Implemented on `feature/m0-flutter-foundation` (draft PR #1),
2026-11-02.

## Problem and behavior

The reader deliberately hides direct Search, EPUB Contents and Return
icons when the available AppBar width is under 420 logical pixels or
accessibility text scaling is large. Previously these common actions
were accessible only through the general Reader tools sheet, alongside
voice/appearance settings and diagnostics.

On these compact layouts, a single **Quick navigation** AppBar action
now opens a short navigation-only sheet. It coexists with the full
**Reader tools** button and the book title. The wide layout continues
to use direct Search/EPUB Contents/Return icons without duplicating
the mobile entry point.

Frequently needed actions appear first when available:

- Search this book (EPUB, TXT, PDF extracted text).
- EPUB publisher table of contents / spine navigation.
- User bookmarks (and PDF visual-page bookmarks in native page view).
- Exact original-source percentage jump.
- Return from internal link, return after a confirmed percentage jump
  and return to the current narrator without seeking.
- Return from extracted PDF text to native pages, plus EPUB boundary
  jumps, when those actions exist.

The sheet shows only actions actually available for the current book
and reader mode. A silent-only EPUB can still expose Contents without
fabricating playable or seekable TTS segments. Native PDF page mode
does not advertise text-search or text-percentage navigation.
If no navigation destination is available, the compact button remains
hidden; the general Reader tools sheet is still available.

## Implementation constraints

The quick sheet's items are selected from
`buildReaderToolSections(ReaderToolMenuAvailability)` by
`buildReaderQuickNavigationSections`, not duplicated. Every action ID
passes to the **same** `ReaderScreen._openReaderTools` switch and
existing source-exact navigation/SQLite checkpoint code.

- Opening the sheet itself never plays, pauses or seeks TTS.
- The existing Go-to dialog saves only on explicit confirmation.
- A tool selection is discarded if the reader was replaced/reloaded
  while the sheet was open. This prevents a dialog from applying
  an old book's action to a different player or source document.
- Full settings remain available while a book is loading; only the
  quick-navigation sheet requires a navigable destination.
- Focus/immersive mode retains the new quick navigation entry and its
  separate source-progress strip.

## Tests authored

`test/features/reader_tool_menu_options_test.dart` verifies
search/TOC/bookmark priority, no duplicate commands, EPUB silent TOC,
native PDF page bookmarks, TXT and PDF extracted-text gating, and
exclusion of appearance/speech configuration from Quick navigation.

`test/features/reader_quick_navigation_integration_test.dart`
covers compact AppBar visibility, short-sheet availability, canceled
percentage jump leaving book checkpoint unchanged, 320 logical pixels
with text scaling at 200%, wide toolbar behavior, and immersive mode
accessibility.

## Manual acceptance

1. Open a TXT on a 320–390px wide Android screen: tap the compass icon.
   Verify Search, Bookmarks and Go appear in this order, alongside a
   separately accessible full tools menu.
2. Cancel Go: it must leave the reading checkpoint and narration
   unchanged. Choose a real destination and verify the existing exact
   source selection is used.
3. For EPUB verify table of contents, internal-link return, silent
   sections, and last/first section are only available when valid.
4. For native PDF pages verify quick access to *page* bookmarks only;
   switch to extracted-text mode to see text search and Go.
5. Repeat in focus mode, rotation, narrow landscape and 200–300% text
   scaling. Confirm the back button and truncated book title remain
   visible and no AppBar overflow is reported.
6. Confirm the separate full menu still exposes appearance, TTS voices,
   pronunciation and diagnostics and remains accessible during loading.
7. Dismiss a quick navigation menu while changing books/reopening a
   document: stale actions must not navigate the new book.

**Validation:** code and test sources were inspected, but Flutter
analyzer, widget tests and real Android/Windows interaction have not
been executed here. No GitHub Actions or Windows executable builds
were started at the user's request. PR #1 remains in draft.
