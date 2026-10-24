# EPUB character encoding and XHTML line-break compatibility

Increment: 2026-10-24 on `feature/m0-flutter-foundation`.
Status: **source and regression tests authored on GitHub; no Dart/Flutter
analyzer, Flutter tests, Windows or Android builds have been executed**.

## What changed

The previous importer called `utf8.decode` on every ZIP text resource.
That failed with older, otherwise usable EPUB2 books whose XHTML
explicitly declared Windows-1252 or ISO-8859-1. A new bounded,
strict `decodeEpubTextResource` reads each resource's header before
decoding its payload.

| Encoding | Conditions | Behavior |
| --- | --- | --- |
| UTF-8 | Default, XML/meta declaration or BOM | Strict; malformed bytes fail |
| UTF-16LE / UTF-16BE | BOM; or recognizable XML signature **with explicit declaration** | Strict code-unit decoding; malformed surrogate pairs fail |
| Windows-1252 | Explicit XML or HTML `meta charset` / HTTP-equiv declaration | Maps typographic quotes, euro sign and punctuation; undefined bytes fail |
| ISO-8859-1 | Explicit XML or HTML charset declaration | Literal Latin-1 mapping, **not** silently reinterpreted as Windows-1252 |

Common aliases `utf8`, `utf16`, `latin1`, `cp1252`, etc. normalize
to these known labels. The new strict policy rejects unsupported labels
(e.g. `Shift_JIS`), conflicting XML/meta declarations, BOM/declaration
mismatches, NUL bytes and unpaired UTF-16 surrogate code units.

No heuristic fallback is attempted after a UTF-8 decoding error:
undocumented legacy bytes or replacement characters could silently
change the text used for TTS, cast attribution and persistent anchors.

The shared decoding path now covers:
- META-INF/container.xml, OPF manifest and metadata;
- every readable spine XHTML document;
- EPUB3 NAV and EPUB2 NCX documents;
- referenced manifest-declared auxiliary note XHTML;
- the existing ZIP `mimetype` check (still UTF-8/default).

All byte-length budgets already enforced by `EpubTextExtractor`
remain in force. The decoded Dart `String` remains the authoritative
UTF-16 source for all book positions, including supplementary-plane
emoji. Original ZIP bytes and an alternate character offset model
are not saved in the reader database.

## Nonstandard XHTML `br` elements

`lib/data/epub_html_preprocess.dart` now centralizes the preexisting
paragraph-close handling and recognizes `<br clear="all">`,
`<br class="foo"/>` and `<br title="greater > than">`, in addition
to ordinary `<br>`/`<br/>`. Quoted `>` characters in attributes
are handled. The same preprocessing function feeds **all three**
source consumers:

1. `EpubTextExtractor._extractVisibleText` (actual read-aloud text);
2. `extractEpubInlineStyles` (bold/italic/heading spans);
3. `extractEpubStructure` (linked ranges, note targets and tables).

This is essential: independent normalization would misalign links,
footnotes, style spans and narration. Previously unsupported attributed
breaks may now add a newline to the actual source text; older saved
*offset-only* anchors for exactly those affected EPUBs may require
migration checks at the integration gate. Standard plain `<br>`
and existing paragraph behavior are unchanged.

## Source files and authored, unexecuted tests

- `lib/data/epub_text_decoder.dart`: explicit encoding policy, BOM
  detection, declaration checks, CP1252 code point table and strict
  UTF-16 surrogate decoding.
- `lib/data/epub_html_preprocess.dart`: shared safe text normalization.
- `lib/data/epub_text_extractor.dart`,
  `lib/data/epub_inline_style.dart` and
  `lib/data/epub_structural_markup.dart`: use the same decoding or
  XHTML line-break preprocessing as applicable.
- `test/data/epub_text_decoder_test.dart`: 12 authored cases covering
  strict UTF-8/BOM, declared Windows-1252/ISO-8859-1, UTF-16 LE/BE,
  surrogate errors, declaration conflict, invalid bytes and budgets.
- `test/data/epub_encoding_integration_test.dart`: six ZIP-level tests
  covering full EPUB extraction, chapter headings, inline styles,
  source-exact fragments, supplementary Unicode and attributed
  `br` elements, plus rejection of malformed inputs.

## Remaining limitations

EPUB itself normally requires standards-compliant XML encodings.
This compatibility path intentionally supports only a bounded
set of common historical encodings, rather than trusting unverified
heuristics. It does not interpret arbitrary character sets, execute
XHTML JavaScript or author CSS, or provide an unrestricted HTML engine.

Complex malformed XHTML, script/comment markup edge cases,
unsupported encodings, and archive interoperability still require
a real-world EPUB fixture corpus and the agreed analyzer + native
Windows/Android integration gate before release.

Related: [EPUB2 Legacy Footnotes](EPUB2_LEGACY_FOOTNOTES.md),
[EPUB Paragraph Renderer](EPUB_PARAGRAPH_RENDERER.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
