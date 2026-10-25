# Dialogue punctuation-aware TTS segmentation

The local-first sentence splitter in `lib/domain/speech_segment.dart`
retains exact UTF-16 offsets into the original text and enforces the
configured `maxChars` input cap for native/cloud TTS.

## Sentence boundaries

In narrative fiction a period, question mark or exclamation mark often
appears **before** a closing quotation mark. Previously, a phrase such as
`«Ciao!» Poi sorrise.` was not recognized as ending immediately after
`!»`, leading to unnecessarily long narration chunks or splits at
arbitrary word boundaries.

The splitter now recognizes ASCII/typographic quote closers, right guillemet
and closing parenthesis/bracket **after** terminal punctuation, and keeps
those delimiters inside the completed sentence. A natural whitespace or
end-of-range boundary must still follow the delimiters; an arbitrary
punctuation mark inside a word does not become a sentence boundary.
The scanner never consumes beyond `maxChars`, and UTF-16 surrogate pairs
remain intact. Decimal points such as `3.14` keep their existing handling.

This is deterministic local processing. It does not infer the speaker,
change any text supplied to TTS, invent SSML or incur cloud requests.
Source-aligned phrase offsets, highlights, bookmarks and manually assigned
character voices are preserved. Existing quote-group attribution remains
the responsibility of `dialogue_segmenter.dart`.

Regression cases cover guillemets, curly and ASCII quotes, nested
parentheses/brackets, question/exclamation clusters, Unicode emoji,
bounded source spans, and dialogue/narrator group transitions.

## Limitations

This is **not** a grammar/abbreviation detector. Abbreviations with a
space after the dot, nested malformed punctuation and dialogue styling
may still require language-specific segmentation. It does not make MP3
decoder output truly gapless or add word-level TTS timing.

**Validation:** source and tests authored; local Windows and Android
validation for this change is still pending. The last manually reported
Windows run (549/556) predates this change, and its detailed failure
files have not yet been published.

## Unicode clusters at provider chunk boundaries

A hard `maxChars` cutoff now also backtracks to avoid cutting a common
multi-code-point grapheme cluster: decomposed combining accents,
variation selectors, skin-tone modifiers, zero-width-joiner emoji and
paired regional indicator flags. The original UTF-16 code-unit source
text remains unchanged; no code units are discarded or copied between
segments. A single exceptionally long cluster that cannot fit the
provider limit fails closed with a `FormatException` rather than
silently omitting characters or violating the size limit.

These are intentionally limited, deterministic boundary guards rather
than full Unicode grapheme-break conformance. More extensive tests on
real-world scripts and complex combining/Indic sequences remain needed.
Added unexecuted source-exact tests for e + combining acute, joined
astronaut emoji, national flag and skin-tone emoji, and oversized
combining sequences.
