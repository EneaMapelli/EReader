# EPUB2 legacy footnotes — conservative paired recognition

Increment: 2026-10-24, branch `feature/m0-flutter-foundation`.
**Source and regression fixtures written to GitHub; Flutter analyzer,
automated tests and Android/Windows builds have NOT been run.**

## Supported legacy patterns

Older EPUB2 books often predate the EPUB3 `epub:type="noteref"` and
`epub:type="footnote"` semantic attributes. EReader now recognizes
a small, auditable subset of **paired** older patterns:

- A link explicitly marked with `class="footnote-ref"`,
  `footnoteref`, `fnref`, `fn-ref`, `endnote-ref`,
  `noteref` or `rel="footnote"`; alternatively, a short
  numeric, bracketed-numeric, asterisk, dagger or double-dagger
  **superscript** link.
- An actual destination body marked with `class="footnote"`,
  `foot-note`, `endnote` or `end-note` on a supported block
  element, or `<li id="fn...">` inside
  `<ol class="footnotes">` / `<ul class="endnotes">`.
- A legacy note with no container `id` may use a leading,
  empty `<a name="fn1"></a>` (or `id`) as its target, but only
  within an already recognized note block. An anchor that appears
  **after** unrelated text never turns that whole block into
  a footnote.
- All recognized legacy destinations can be in the readable
  OPF spine, or in previously supported manifest-declared auxiliary
  XHTML. Auxiliary notes remain **preview only**, with no synthetic
  source/TTS offset and no Open in book action.

## Mandatory paired evidence

A reference is initially only a `legacyNoteCandidate`. It is promoted
to a real footnote **only if** its canonical, in-book destination
resolves to a second, independently recognized note body.

A generic `<sup><a href="#chapter2">2</a></sup>` is **not enough**
to convert a section link into a note. Class token matching is exact,
so `footnoteish`, `noteworthy` and
`footnote-references-extra` never qualify.

The parser continues to compare the entire normalized XHTML body
against the original extracted string. Source offsets are in UTF-16
code units and do not change; there is no regex-based search for
the first matching phrase, and repeat text cannot change the source
anchor. Any ambiguity or unmatched reference is ignored or stays a
regular internal link if the target is in the reading spine.

The legacy rules do not infer notes from unrelated `href` fragments,
external URLs, unlisted ZIP resources, or generic `<ol>` lists.

## Safety and narration

- OPF manifest and normalized ZIP path checks are still enforced.
- The prior budget for auxiliary note content is unchanged:
  at most 12 XHTML files of 256 KiB, 24 distinct note references,
  1,600 UTF-16 code units per preview and 12,000 in aggregate.
- No XHTML scripts, SVG, stylesheets, arbitrary CSS, external fonts
  or network URLs are executed/fetched.
- Only the canonical OPF spine is used for speech text, bookmarks,
  search, cast spans, SQLite positions and resume anchors.
- Legacy auxiliary notes can be read and closed locally but cannot
  start TTS, cloud requests, or fake a navigation location.

## Implementation

- `lib/data/epub_structural_markup.dart`: exact-token
  legacy reference/body classification, named anchors and
  UTF-16-aligned structural markers.
- `lib/data/epub_text_extractor.dart`: validates the candidate
  against a verified in-spine or auxiliary note destination before
  promoting `isFootnote`.
- Existing popup, reader navigation and TTS code remain unchanged,
  because the verified notes reuse the already-safe types and
  presentation models.
- `test/data/epub_legacy_notes_test.dart`: ten authored end-to-end
  EPUB2 ZIP fixture tests for in-spine notes, outside-spine notes,
  named anchors, ordinary numbered links, class false positives,
  nonleading names, undeclared files, repeat references and
  size-limit fallback.
- `test/data/epub_embedded_content_test.dart`: four additional
  structural parser tests for preliminary link hints, verified
  bodies, named anchors and false-positive rejection.

## Deliberate limitations

EPUB2 footnote conventions are not standardized enough to identify
every book perfectly without false positives. This increment does
**not** guess from generic `class="note"`, arbitrary `<a href>`,
unmarked prose, loosely named IDs or rendered-number position alone.
Legacy `<a name>` is accepted only in a validated note container.
Publisher-specific conventions may need separately tested opt-in
adapters, not silent broadening of source rules.

Source implementation is **not yet validated** by the Dart analyzer,
Flutter tests or real Android/Windows devices. Compatibility on a
representative EPUB2/EPUB3 corpus remains an integration gate.

Related: [Auxiliary Footnotes](EPUB_AUXILIARY_FOOTNOTES.md),
[EPUB Footnote Preview](EPUB_FOOTNOTE_PREVIEW.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
