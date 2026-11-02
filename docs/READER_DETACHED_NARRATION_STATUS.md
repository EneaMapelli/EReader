# Narration highlights and position while browsing elsewhere

**Branch:** `feature/m0-flutter-foundation` · Draft PR #1 · 2026-11-02

## User-facing behavior

When narration is playing and the user manually scrolls away with
**Follow narration** enabled, the reader temporarily detaches visual
following as before. A compact **TTS 12/240** indicator now sits next to
**Return to narrated passage**. It represents the audio cursor only, not
the current page or reading progress.

- The indicator advances as the TTS engine moves through segments, even
  if the narrated sentence is offscreen. It shows **TTS complete** at
  speech EOF, and a pause icon when narration is paused.
- Screen readers receive a full announcement such as
  "Narration playing, segment 12 of 240; viewing elsewhere". The compact
  status itself is **not interactive**: using it never pauses, seeks, starts
  synthesis, rewrites a bookmark or updates the visible reading position.
- The adjacent return button is the explicit action to reconnect the
  viewport. The new indicator does not appear in ordinary reading,
  native PDF page view, or when follow was deliberately disabled (where
  there is no temporary-detachment state).
- If the spoken EPUB segment happens to be visible, the reader's existing
  source-aligned TTS highlight remains in place. There is **no attempt to
  scroll the displayed passage or change its selection** solely to paint
  an offscreen speech highlight. The visual cursor continues to drive
  the chapter label, bookmark suggestion and displayed reading progress.
- EPUB search-result highlighting takes precedence on overlapping
  character spans: the original text, inline links, tap recognizers,
  source UTF-16 offsets and active TTS segment index remain unchanged.
  TXT/PDF extracted-text highlight styling remains unchanged. No change
  to the voice engine, OpenAI usage, source text or saved progress.

## Regression coverage authored, not executed

- `test/features/reader_narration_status_indicator_test.dart` checks
  first/active/completed/empty audio indexes, pause/play semantics,
  repaint on audio cursor advancement, and non-interactive behavior.
- `test/features/epub_paragraph_tile_test.dart` checks an overlapping
  search match and active TTS highlight in night mode, including exact
  source characters and tap recognizers.
- The pre-existing `reader_position_ownership_test.dart` and follow
  policy tests cover detached visual-vs-audio ownership and must be run
  during integration.

## Manual Windows/Android acceptance

1. Play a long EPUB; scroll several pages away using the reader. Confirm
   **TTS x/y** and **Return to narrated passage** appear together.
2. Let audio play several segments without touching the screen. The
   status should advance, with no automatic scroll back to narration,
   no audio request beyond normal playback and no new saved visual
   checkpoint.
3. Search for a word in the currently spoken paragraph. Where the result
   intersects the TTS highlight, verify search highlighting remains
   distinct and the original source text and link clicks are preserved.
4. Pause while detached. Confirm the icon and accessibility wording
   indicate paused; pressing Play should resume the original spoken
   position without jumping to the inspected paragraph.
5. Tap the **Return to narrated passage** button or use
   **Ctrl/Cmd+Shift+J**. The indicator should disappear and normal
   auto-follow should resume; it must not start a new audio seek.
6. Verify high contrast, night, warm paper, large text scale, smallest
   Android viewport, focus mode, and long books with thousands of
   segments. The status must not cover the scrollable text excessively.
7. Confirm native PDF pages and deliberately disabled follow have no
   detached status. In TXT/PDF extracted-text reading, the indicator
   should describe the audio position and not the visual progress bar.
8. Inspect screen-reader semantics for the status and return button;
   the status label should be announced without suggesting it is a
   clickable command.

Flutter analyzer/tests, Windows/Android rendering, and actual audio
integration have **not** been executed. No build or GitHub Actions
were launched. Keep PR #1 in draft pending native QA.
