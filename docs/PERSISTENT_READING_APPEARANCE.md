# Persistent visual reading preferences — EPUB/TXT/PDF text

Updated: **2026-10-29**
Branch: `feature/m0-flutter-foundation`

## Delivered

Reader appearance is no longer limited to temporary in-memory font size
and EPUB palette selections. The reader now supports:

| Setting | Range / values | Display |
| --- | --- | --- |
| Font size | 14–32 logical pixels | EPUB, TXT and PDF text mode |
| Line spacing | 1.2–2.4 font-height factor | EPUB body, TXT and PDF text |
| Font family | Serif / sans serif / monospace | EPUB, TXT and PDF text mode |
| Page palette | Device / warm paper / night | EPUB |

The existing fast font increase/decrease buttons and EPUB palette
menu **now persist** their choices. The new **Reading appearance** toolbar
control lets users adjust all applicable settings, then choose:

- **Save for book:** saves only this book's display preferences.
- **Set global default:** saves global defaults and clears this book's
  override, so this open book also adopts the new global defaults.
  Other books with explicit overrides remain unchanged.
- **Use global defaults:** removes this book's override without changing
  the global values.
- **Cancel:** does not modify the book or stored preferences.

The controls remain fully offline. There are no font downloads or extra
permissions, and no changes to how the book is read aloud.

## Data and migration

- New pure Dart `ReadingPreferences` model (version 1 JSON) with
  bounded numeric settings, finite-value validation and a whitelist of
  font/palette names. Unknown versions or malformed fields are rejected.
- SQLite **user_version = 18** adds the dedicated
  `reading_preferences(scope_id TEXT PRIMARY KEY, value_json TEXT)`
  table in a transaction. The existing speech preferences and all
  book/anchor tables are unchanged.
- Global preferences are stored under `global`; a per-book override is
  stored under `book:<content-sha256>`. A book override wins, otherwise
  global preferences apply, otherwise defaults.
- Removing a book also deletes its visual override in the existing
  transaction; other books and the global style are not modified.
- Settings survive a normal app restart and do not need an external
  server or account. EPUB book source hashes and saved reading offsets
  remain unchanged.

## Reader rendering

`EpubParagraphTile` accepts typography as visual-only parameters;
all source-aligned `EpubVisualRun` offsets, links, footnotes, spoken
segments, highlights, and display-only embedded media remain unmodified.
The body line spacing is configurable; chapter headings keep their
distinct heading proportions. TXT and PDF **text-layer mode** use the
same saved font/spacing but not the EPUB-only palette; faithful PDF page
viewing retains the existing viewer layout and zoom.

## Tests authored but not executed

- `test/domain/reading_preferences_test.dart`: default/round-trip,
  copying, invalid values and supported numeric bounds.
- `test/data/reading_preferences_store_test.dart`: fresh schema,
  global restart, book inheritance, unchanged reading position,
  unknown-book rejection and cleanup.
- `test/features/epub_paragraph_tile_test.dart`: typography changes
  without altering canonical text, taps or highlight position.
- `test/data/library_store_test.dart`: updated legacy upgrade
  expectation to schema v18.

**No Flutter/Dart test execution occurred** in this environment. No
Windows/Android builds or GitHub Actions were started. Verify actual
font availability and layout/readability on Windows/Android before
calling M1 accessibility acceptance complete.

## 2026-10-29 — Column layout, paragraph alignment and high contrast

Added **three persistent visual controls** to the same per-book/global
appearance dialog. These settings remain local-only and are independent
of speech synthesis, model selection and source bookmarks.

| Setting | Values | Behavior |
| --- | --- | --- |
| Reading column | 480–1000 logical pixels, default 760 | Upper bound on width, never forces overflow on a narrow Android screen |
| Paragraph alignment | Original / left / justified | Original retains EPUB justification and TXT/PDF text's start alignment |
| High-contrast EPUB palette | White background, black text | Clear yellow narration highlight, dark-blue search highlight and readable links |

The previous **SQLite v18** schema is unchanged. Its existing **JSON
version 1** settings are extended with optional `contentWidth` and
`textAlignment` fields. Stored v1 records with only the four older keys
load using the previous 760-pixel paragraph width and existing EPUB/TXT
alignment; no migration, data reset, or app update of an open ebook is
required. Invalid/non-finite column sizes and unknown options are rejected.

The colors of the added palette were chosen for high contrast. Computed
relative-luminance contrast ratios: body text 21:1 (black on white),
narration highlight 16.45:1 (black on yellow), search highlight and
link text 9.81:1 (white on dark blue, or dark blue on white). These
figures do **not** establish full WCAG conformance of the entire app;
screen-reader and large-font accessibility still need device testing.

EPUB `EpubParagraphTile` applies width and alignment around the
original source-exact `RichText` spans, including illustrations,
links and footnotes. TXT and PDF **text mode** use the same bounded
column and explicitly selected alignment. The original-faithful PDF
viewer remains unchanged.

Extended unexecuted regression coverage:

- `test/domain/reading_preferences_test.dart`: legacy v1 JSON, range
  and enum validation, high-contrast round-trip.
- `test/data/reading_preferences_store_test.dart`: old SQLite JSON
  loaded and rewritten with new fields, per-book persistence across
  reopen and TTS preference independence.
- `test/features/epub_paragraph_tile_test.dart`: width constraint,
  left/justified alignment, unchanged text/hit gestures and color mapping.

**Tests authored, not executed** because Flutter/Dart is unavailable in
the connected editing environment; no Windows/Android build or GitHub
Actions launched.
