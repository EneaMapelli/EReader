# EPUB auxiliary footnotes outside OPF reading spine

Increment: 2026-10-24, branch `feature/m0-flutter-foundation`.
**Code committed and regression tests authored; no Flutter analyzer, Dart
tests, Android build, Windows build or real-device validation executed.**

## Supported workflow

An EPUB3 footnote reference inside an ordinary readable XHTML spine item
may point to a second, *non-spine* manifest-declared XHTML resource.
That document is **not** part of the TTS reading sequence or its
persistent position model. If a recognized semantic note body is found,
the reference is rendered as a tappable, in-place **read-only plain-text
preview** using the existing footnote modal.

- The user can open, select and scroll the auxiliary note and dismiss it.
  Neither opening nor closing calls the speech engine, mutates SQLite
  progress, pushes the back stack, changes the book viewport or sends a
  cloud request.
- Since an auxiliary XHTML file has **no valid spine source offset**,
  the popup deliberately has **no “Open in book” control**. Treating the
  reference as a synthetic position would corrupt saved anchors and
  narration. This is not a full auxiliary XHTML reader.
- Standard in-spine footnotes continue to offer the separate “Open in
  book” action and the normal bounded return stack. Normal links still
  use the existing source-anchored reader navigation.
- Auxiliary markup is presentation-only. The original source text,
  paragraph breaks, speech chunks, voice casting, consent and index
  remain bit-for-bit unchanged.

## Resolver and safety model

Only hyperlinks explicitly marked `epub:type="noteref"` or
`role="doc-noteref"` in the **readable spine** can request auxiliary
content. The resolver:

1. Canonicalizes the referenced relative `file.xhtml#id` path inside
   the EPUB ZIP. It rejects HTTP(S), data/javascript/file schemes,
   absolute paths, missing fragments and directory traversal.
2. Requires the exact local XHTML resource to be declared in the OPF
   manifest (`application/xhtml+xml` or `text/html`), not part of the
   readable spine and not the EPUB3 navigation document. An
   unlisted ZIP entry never qualifies.
3. Reads at most **12 distinct auxiliary XHTML files**, each no larger
   than **256 KiB**, and at most **24 distinct referenced anchors**.
4. Passes content through the existing bounded source-verified XHTML
   structural parser, which strips script, style, navigation, head,
   SVG and noscript nodes. Only an element with the referenced ID
   **and** `epub:type="footnote"` or `role="doc-footnote"` can be
   previewed. Ambiguous, missing or nonsemantic matches fail closed.
5. Enforces at most **1,600 UTF-16 code units per note** and
   **12,000 UTF-16 units across stored auxiliary previews**. No scripts,
   external resources, images, embedded fonts or CSS are evaluated.

An auxiliary note is identified by an internal canonical
`EPUB/relative.xhtml#fragment` key, **not a book offset**.
`EpubInternalLink.targetOffset` stays null for these links, and
`EpubInternalLink.auxiliaryFootnoteKey` is present only after
successful resolution. Layout validates the key against stored preview
metadata before creating the interactive span. The UI callback receives
only the key and shows the passive popup.

No EPUB archive bytes or fonts are uploaded to a remote service by
this workflow. There is no runtime network fetch.

## Changed files

- `lib/data/epub_text_extractor.dart`: bounded lookup of only
  referenced, manifest-declared non-spine note documents.
- `lib/data/epub_embedded_content.dart`: typed auxiliary metadata,
  with no fabricated source anchor.
- `lib/data/book_decoder.dart`: display-only auxiliary note records.
- `lib/features/reader/epub_visual_layout.dart`: verifies auxiliary
  marker keys while preserving exact original speech-run offsets.
- `lib/features/reader/epub_paragraph_tile.dart`: separate note-preview
  recognizers from source-navigation recognizers.
- `lib/features/reader/epub_note_preview_sheet.dart`: read-only
  auxiliary mode without the Open in book action.
- `lib/features/reader/reader_screen.dart`: opens keyed local
  previews without seek, TTS or persistent position changes.

## Unexecuted regression coverage

- `test/data/epub_navigation_test.dart`: manifest-allowed
  out-of-spine note, unchanged spoken text, undeclared ZIP file,
  missing/oversized/nonsemantic targets, external URLs and traversal.
- `test/features/epub_visual_layout_test.dart`: exact spoken runs
  and null source-target for auxiliary notes; unverified keys rejected.
- `test/features/epub_paragraph_tile_test.dart`: note-preview gesture
  cannot be mistaken for seek, TTS or ordinary link.
- `test/features/epub_note_preview_sheet_test.dart`: separate modal
  Close and barrier dismissal behavior, never offers Open in book.

## Deliberate limitations

Not all EPUB2 publishers mark footnotes semantically. Legacy
`class="footnote"`, link-only `div` notes and dynamically generated
popups are not inferred, to avoid mistaking arbitrary book content
for auxiliary note text. Complex XHTML formatting, equations, images,
bi-directional rich text and embedded media are not displayed in the
plain-text popup. Auxiliary note previews cannot be read aloud as
part of the book narration; that would require a separate,
user-consented and deliberately isolated speech mode.

No database schema changes were necessary. The next phase should
focus on real-world EPUB interoperability, static compiler checks
at the agreed integration gate, and an accessible richer note
viewer without violating source/voice boundaries.

Related: [EPUB Footnote Preview](EPUB_FOOTNOTE_PREVIEW.md),
[EPUB NAV/NCX and Footnotes](EPUB_NAV_NCX_FOOTNOTES.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
