# Whole-book reading progress and safe source scrubbing

Date: 2026-10-29 · Branch: `feature/m0-flutter-foundation`

## Reader UX

The text reader now shows a **whole-book source-position percentage** and
an accessible slider next to the existing `Segment X of Y` information.
The two measures deliberately answer different questions:

- The percentage is based on the canonical document's UTF-16 source
  offset divided by the canonical text length, including non-spoken
  paragraphs and silent EPUB spine items.
- The segment counter counts TTS speech chunks and is **not** a page,
  elapsed-time or accurate played-audio-duration estimate.

When audio is active, the source position tracks the start of the
currently active audible segment. When paused, the EPUB visual source
offset (including a verified text-only note destination) takes priority;
ordinary TXT/PDF text uses the currently visible segment. A natural
speech EOF is displayed as 100%, even if the last chapter had text
that could not be synthesized.

The slider only commits its selection on **drag release**. While the
thumb moves it updates the percentage preview but never touches
`ReaderPlayer`, bookmarks, provider lookahead or persisted positions.
Releasing pauses active narration before navigating, then keeps it
paused. It cannot silently trigger extra OpenAI Speech requests.

## Source navigation and safety

- **EPUB:** Reuses the existing exact `_navigateToSourceOffset` path.
  This maps canonical offsets to the nearest future audible segment,
  preserving visual-only trailing sections and source anchors.
  A progress seek is **not** a hyperlink: it doesn't enter the
  link-return history.
- **TXT / PDF text layer:** Maps the source fraction to a corresponding
  real TTS segment using the existing binary lookup, stops the current
  session, then seeks to that segment without auto-playing. 100% uses
  the source-EOF navigation path instead of replaying the final clip.
- **Faithful PDF page viewer:** Continues to use the page-number and
  zoom controls, not the text offset scrubber. No false correspondence
  between extracted text order and a scanned PDF page is asserted.
- The data model is pure and bounds fractions/offsets. No database
  migration, permission, network service, source rewrite or audio
  synthesis adapter change is required.
- Manual scroll updates the small progress widget independently of the
  whole EPUB layout, keeping long-book scrolling responsive.

This is approximate *reading location*, not percent of listening
duration, precise word-progress or proof that every source character
was consumed. The 100% visual position is independent of a user
listening to the entire recording.

## Regression tests authored

- `test/domain/reading_progress_test.dart`: source fractions,
  percentage, bounds, zero/invalid lengths, EOF and non-finite input.
- `test/features/reading_progress_bar_test.dart`: percentage and
  accessible semantics, no seek while dragging, exactly one release
  callback, empty book disabled, and external position update.

**Tests are not executed**: Flutter/Dart SDK isn't available to the
GitHub editing toolchain. In particular, seek fidelity under native
Stop races and large EPUB visual-scroll frame performance remain
device acceptance tasks. No Windows/Android builds or GitHub Actions
were launched.
