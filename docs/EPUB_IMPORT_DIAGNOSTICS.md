# EPUB import diagnostics and source-anchor integrity

Increment: 2026-10-24 on `feature/m0-flutter-foundation`.

**Source authored and committed; analyzer, Flutter test suites, Windows and
Android builds have not been run.** This is not a validated release.

## Two separate outcomes

EReader now distinguishes **optional incompatibilities**, for which
reading may continue, from **corrupt reading/source anchors**, which
must stop import before navigation or TTS starts.

### Nonfatal compatibility report

`EpubImportDiagnostics` is a fixed-category, bounded in-memory
aggregator. It reports counts for:

- skipped spine items with no readable text;
- absent or unusable publisher NAV/NCX (existing spine index fallback);
- internal links whose destinations are unsafe or missing;
- referenced footnotes that cannot be previewed;
- rejected non-manifest, malformed, oversized or unsupported pictures;
- inline formatting dropped because safe source mapping failed or the
  metadata budget was exhausted.

Counts saturate at 9,999, with at most one row per enum category. No
arbitrary archive filename, remote URL, book excerpt, XHTML, personal
path or publisher-provided error string is placed in diagnostic labels.
The optional import report is passed through `DocumentContent` and
displayed in `ReaderScreen` via a toolbar warning icon **only when a
book actually has warnings**. The report sheet is passive: it never
opens web URLs, changes speech, seeks, saves progress, changes voice
settings or triggers cloud requests.

The diagnostic model is rebuilt from the local EPUB on import/open.
There is **no database migration**, telemetry, server upload or
persistent dump of raw book contents.

### Fatal integrity audit

`verifyEpubSourceIntegrity` checks the final canonical UTF-16 source
before it becomes available to the reader:

1. Source is nonempty and OPF spine IDs are nonempty and unique (required
   for unambiguous `ReadingAnchor.sourceId` recovery).
2. Spine ranges are ordered, non-overlapping, nonempty, begin at offset
   zero and cover the original extracted text exactly, with the existing
   two-newline synthetic separator between entries.
3. No range, resolved link or navigation/footnote target lies outside
   a readable spine element, on a synthetic separator, or at the middle
   of a UTF-16 surrogate pair (emoji and similar characters).
4. Source hyperlinks remain ordered, non-overlapping and entirely
   inside **one** original spine element; they cannot consume
   synthetic separators or point to invalid target offsets.
5. Editorial NAV/NCX and source-verified in-spine note preview
   destinations must be valid original reader offsets. Auxiliary
   non-spine notes remain **keyed previews**, never fabricated offsets.

These checks use binary search for target/range lookup and never
change original text or silently repair a potentially incorrect anchor.
A structural failure raises `FormatException`, instead of allowing
broken progress/bookmark/TTS references.

`DocumentContent.offsetOf` additionally refuses an EPUB progress
anchor whose local offset exceeds its original spine range or splits
a surrogate pair. It returns `null` to permit the existing reader
recovery decision to handle a stale anchor; it no longer silently clamps
such an anchor into a different text position. Legacy TXT/PDF anchor
handling is unchanged.

**Note:** this does not implement full EPUB CFI, quote-based anchor
relocation or content-hash migration. The preexisting reader fallback
to the saved absolute progress offset still needs corpus validation
when an EPUB's canonical extracted text changes after a parser update
(e.g. newly supported attributed `<br>` tags). This is a known
integration risk, not a guaranteed recovery migration.

## Code and tests authored

- `lib/data/epub_import_diagnostics.dart`: bounded fixed-category
  warnings without attacker-controlled strings.
- `lib/data/epub_anchor_integrity.dart`: pure source/spine/link/target
  verification, with surrogate-pair safety and logarithmic range lookup.
- `lib/data/epub_text_extractor.dart`: records optional omissions,
  verifies final source/targets and returns a diagnostic summary.
  Also fixes legacy EPUB2 references to *verified auxiliary notes*:
  both early identification and final link resolution now accept
  a proven legacy note candidate, without assigning a fake TTS offset.
- `lib/data/book_decoder.dart`: passes report to `DocumentContent`,
  rejects stale EPUB local anchors rather than clamping.
- `lib/features/reader/epub_diagnostics_sheet.dart` and
  `reader_screen.dart`: view compatibility issues without changing
  narration or navigation state.
- `test/data/epub_anchor_integrity_test.dart`: seven authored cases
  for valid Unicode and anchors, duplicate spine IDs, separator gaps,
  overlapping links, invalid targets and half-emoji positions.
- `test/data/epub_import_diagnostics_test.dart`: three authored cases
  for category grouping, 9,999 count saturation and immutable snapshots.
- `test/features/epub_diagnostics_sheet_test.dart`: two widget cases
  for report display/dismissal and empty-report behavior.
- `test/data/epub_text_extractor_test.dart`: three additional
  integration cases for nonfatal warnings, skipped empty XHTML and
  duplicate stable spine identifiers.
- `test/data/reading_anchor_test.dart`: two regression cases for stale
  and Unicode-splitting persisted anchors.

All new tests are **authored but unexecuted** as requested.

## Pending verification

At final integration, run `flutter analyze`, all Dart/Flutter unit
and widget tests, sample EPUB2/3 corpus diagnostics and Android/Windows
GUI + background-TTS smoke tests. Pay particular attention to genuine
EPUBs with repeated manifest itemrefs, empty/image-only spine items,
strange normalization boundaries, NAV/NCX fallbacks, footnotes and
saved reader progress after parser upgrades.

Related: [EPUB Character Encoding](EPUB_CHARACTER_ENCODING.md),
[EPUB Chapter Navigation](EPUB_CHAPTER_NAVIGATION.md),
[Implementation Status](IMPLEMENTATION_STATUS.md).
