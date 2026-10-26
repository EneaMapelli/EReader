# Visual-only EPUB/PDF navigation without fabricated narration

**2026-10-26 — M2 source increment, authored tests NOT executed.**
Branch: `feature/m0-flutter-foundation`, draft PR #1.

## Intended semantics

A book can have visible sections with no extractable spoken text: EPUB
illustrations, empty OPF spine resources, silent footnotes, or PDF pages
that are scans rather than text-layer content. The visual/source bookmark
belongs to the exact selected section. The TTS engine may instead have
a next audible segment — or none. EReader must not conflate those cursors,
silently jump backward, invent OCR text or start paid cloud synthesis.

## EPUB OPF sections

- `buildEpubChapters` now preserves **every OPF spine range**, including
  whitespace-only and zero-length text ranges. The directory and section
  indicator can therefore show an unspoken section rather than silently
  dropping it. Such entries carry `hasSpeech=false`; the directory
  explicitly labels them *no spoken text*.
- Each entry retains its exact `start` source offset and a separate
  speech cursor. A silent middle section has the **next** playable clip;
  an unspoken final section maps to `segments.length` (speech EOF).
- Navigating to a directory entry now persists its ORIGINAL visual
  source offset. It does not store the start of the next spoken clip
  and never implicitly starts audio. A silent chapter cannot replace
  the semantic heading of the next spoken chapter.
- Internal EPUB links, return history and source-exact bookmarks after
  the final spoken clip also use the speech EOF cursor, rather than
  replaying the last paragraph. Source offsets equal to document EOF
  are accepted for explicit navigation; the visual list still clamps
  to its final available block.
- `ReaderPlayer.seekToSourceEnd` stops any active utterance using its
  existing serialized, latest-wins native Stop barrier, then sets speech
  completion without automatic resume or synthesizing text. An
  interrupted/unfinished Stop never authorizes the final cursor.
- Explicit Play on a completed narration still means the reader
  deliberately restarts from the beginning. For silent middle chapters,
  Play starts at the next available spoken chunk only when requested.

A fully textless/zero-length spine item may have **no independent visual
paragraph** to scroll to in today's EPUB text-only renderer. Its OPF
index entry and exact source bookmark are retained, but drawing the
original illustrated layout requires later graphical EPUB rendering.

## PDF physical pages without selectable text

- `pdfTextOffsetForVisualPage` already advances forward from an
  image-only page to the next real text-layer page. This remains true
  for interior gaps in the page sequence.
- When the selected physical page and *all following pages* have no
  selectable text, it now returns **null**, not the START of the
  preceding readable page.
- ReaderScreen rejects this explicit Read Aloud attempt with a clear
  message, rather than falling back to some unrelated saved speech
  checkpoint or synthesizing an earlier page. Visual page controls
  remain available and do not overwrite narrated reading progress.
- EReader still does not OCR scanned/image-only pages automatically.
  Text extraction order within complex PDF pages is not validated.

## Regression tests (authored, not executed)

- `test/features/reader/epub_silent_chapter_navigation_test.dart`:
  unspoken middle/trailing OPF sections, zero-length source ranges,
  exact chapter offsets, next-audible cursor and EOF without final
  clip replay, malformed range refusal.
- `test/audio/rapid_playback_navigation_test.dart`: new source-only EOF
  navigation from a live utterance, retained Stop confirmation, and
  supersession of a pending auto-resuming Seek.
- `test/data/pdf_text_navigation_test.dart`: forward navigation over
  multiple scanned pages and no backward TTS at trailing scanned pages.
- Existing `test/features/reader/pdf_speech_navigation_test.dart`
  validates page-aware TTS segment boundaries, source anchors and EOF.

## Manual integration checks

1. Run `tool/run-all-tests.ps1` on Windows and read the targeted suite
   logs. No automatic tests have been invoked by this edit.
2. Load an EPUB with a text chapter, a visual-only/empty OPF resource,
   another text chapter, then a silent appendix. Open the chapter
   directory and select each in order. Verify the original source
   position is saved and voice output is never started by navigation.
3. On a silent middle chapter, press Play and confirm it starts at the
   first subsequent playable clip, not the previous text. At the final
   silent chapter, it must not replay the previous text until the
   user deliberately presses Play to restart.
4. From a speaking chapter, trigger rapid Seek, a silent trailing link
   and Pause while native Stop is delayed. Verify no unexpected resume,
   lost text bookmark, overlapping audio or cloud quota.
5. Open a mixed scanned/text PDF. Choose an image-only middle page,
   then explicitly Read Aloud: narration may start at the next text
   page. On final scanned pages with no subsequent text, display
   the clear no-text error rather than speaking earlier pages.
6. Verify source bookmarks, physical PDF visual-page persistence,
   Android background/media controls, and narrator voice restoration.

**Release caveat:** Flutter/Dart analyzer, native builds, media-driver
checks and manual UI flows have NOT been executed. Progress estimates
remain M2 ~70% and overall M0–M6 ~55% pending on-device validation.
