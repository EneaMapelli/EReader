# EPUB read-only footnote peek — M1 increment

Date: 2026-10-24. Active branch: `feature/m0-flutter-foundation`.
**Source and unit/widget tests authored, NOT executed**. Flutter/Dart
analyzer and Android/Windows builds remain deferred to the final gate.

## What is implemented

A recognized in-book EPUB footnote can now be read in a bottom-sheet popup
**without leaving the current paragraph**:

- A user taps a source-verified `epub:type="noteref"` or
  `role="doc-noteref"` hyperlink. When the destination points to a
  verified semantic note body already present in the readable OPF spine,
  EReader opens a **selectable, scrollable, plain-text** footnote sheet.
- Tapping **Close** or dismissing the sheet only closes it. No media focus
  acquisition, TTS seek, new synthesis, SQLite progress update, scroll
  move, note return-stack push/pop, remote network request, or automatic
  playback occurs as part of the preview.
- **Open in book** is a separate user action. It closes the sheet and
  uses the preexisting paused internal-link navigation, persisting the
  exact target source anchor and recording the previous position on the
  bounded in-session return stack.
- If a *resolved in-spine* target lacks an identifiable preview, the
  existing safe hyperlink navigation remains available. Links to absent
  or non-spine targets remain rejected by the prior EPUB link resolver. Normal hyperlinks are not changed.

## Strict source alignment

`extractEpubStructure` detects note bodies with a bounded DOM traversal,
specifically elements that have both an `id` and
`epub:type="footnote"` or `role="doc-footnote"`. It records their
text ranges, then validates the entire normalized XHTML body against the
authoritative source string, using the exact same UTF-16 whitespace
projection as other EPUB presentation marks.

The extractor resolves note IDs to global OPF spine fragment locations,
but only if their ranges correspond to the readable text. The popup
text is copied directly from that exact, existing source substring,
after whitespace trimming for display.

Defensive limits: no more than 200 note bodies, at most 1,600 UTF-16
code units of original source per preview, with no scripts, CSS, WebView,
active content, external files, HTTP(S) access or markup execution.
Unsupported notes fall back to existing in-book navigation. The source
text is never duplicated or rewritten in the document/TTS stream.

This is display-only metadata in `DocumentContent.epubFootnotePreviews`.
No SQLite migration, changes to source hashes, cast attribution, voice
settings, cloud consent, anchors or PDF/TXT paths are involved.

## Code

- `lib/data/epub_structural_markup.dart` extracts semantic body ranges.
- `lib/data/epub_embedded_content.dart` introduces immutable
  `EpubFootnotePreview` records indexed by exact target offsets.
- `lib/data/epub_text_extractor.dart` verifies and bounds source
  substrings before emitting the previews.
- `lib/data/book_decoder.dart` conveys display-only note records.
- `lib/features/reader/epub_paragraph_tile.dart` routes actual
  footnote links to a distinct handler; ordinary links and references
  with no preview handler remain navigable.
- `lib/features/reader/epub_note_preview_sheet.dart` implements the
  passive UI with explicit Close/Open actions.
- `lib/features/reader/reader_screen.dart` maps verified source
  targets to the popup, retaining the document/session guard and
  existing safe navigation for explicit Open.

## Authored regressions, not yet run

- `test/data/epub_embedded_content_test.dart`: semantic note
  regions, Unicode and whole-body verification failure.
- `test/data/epub_navigation_test.dart`: cross-spine note snippet,
  exact target mapping, ordinary link without preview, oversized note
  fallback and unchanged speech source.
- `test/features/epub_paragraph_tile_test.dart`: distinct gesture
  callbacks for note versus ordinary links to the same source, plus
  compatibility with readers that do not provide a popup handler.
- `test/features/epub_note_preview_sheet_test.dart`: widget-level
  Close, Open, modal dismissal and long-content scrolling.

## Limits and subsequent work

The popup deliberately supports only notes **inside readable XHTML
spine items**, with explicit semantic note markup and a verified ID.
It cannot display notes in non-linear auxiliary files, mathematical
formula/image-only notes, embedded media, rich CSS or links inside a
note's preview. Popup text is plain, not HTML. A publisher's
footnote/backlink reconstruction is not attempted.

Next steps include accessible footnote rich text, support for
non-spine auxiliary notes within strict safety limits, repeated
anchors/note references, and real-book/native Android/Windows
integration tests. Do not claim release readiness until the
agreed analyzer, tests and platform builds have run.

See [EPUB NAV/NCX and Footnotes](EPUB_NAV_NCX_FOOTNOTES.md) and
[Implementation Status](IMPLEMENTATION_STATUS.md).
