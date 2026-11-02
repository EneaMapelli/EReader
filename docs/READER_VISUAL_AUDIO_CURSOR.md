# Separate visual and spoken reading positions

Implemented on `feature/m0-flutter-foundation` (draft PR #1). This is a
source-only development increment; native device and Flutter test execution
are still pending.

## Why this matters

A reader may continue listening while looking up a paragraph elsewhere.
Those are **two different locations**, not one reading checkpoint:

- **Speech cursor:** the `ReaderPlayer.currentIndex` and its independent
  media/crash-recovery lifecycle.
- **Visible cursor:** first source-aligned visible paragraph or EPUB visual
  block, including unspoken captions and OPF sections with no distinct
  source-text offset.

The earlier implementation temporarily disabled scrolling to speech but
still let `_onPlaybackChanged` overwrite the visual index. It also ignored
visible-block notifications during playback because the audio player was
not settled idle. The resulting bookmark suggestions, TOC label and
reading-progress display could represent the narrator rather than the
paragraph actually being consulted.

## New behavior

- With active automatic follow, the speech cursor remains authoritative
  for the displayed position.
- With follow **temporarily detached**, or explicitly disabled while
  narration continues, genuine manual scrolling updates the visual cursor
  without seeking the TTS engine.
- EPUB uses the canonical visual block's source offset, with a separate
  silent-spine ID when available; TXT and PDF extracted-text views use the
  visible speech-aligned text segment. Physical PDF pages are unaffected.
- Bookmarks, the starting point for in-book search, the current TOC/chapter
  indicator, in-book link return origins, and the *visible* progress bar
  use the visual cursor during detached browsing. Audio playback and its
  media progress continue using the speech cursor.
- Scroll browsing during audio playback **never writes a SQLite reading
  checkpoint**. A temporarily detached view stays non-persistent even
  after pausing, until explicit navigation or returning to narration.
  Explicit bookmark creation is still a deliberate user action.
- Pressing **Play** after pausing while detached resumes the previous
  speech cursor, **not** the unrelated paragraph being previewed.
- **Return to narrated passage** reconnects the viewport, updates the
  displayed progress and starts normal following, without invoking audio
  Play, Pause or Seek.
- Active remote chapter changes cannot silently overwrite a detached
  visual cursor. Paused explicit remote chapter navigation still updates
  the visible location and its existing checkpoint handling.
- Genuine manual EPUB scrolling releases a stale initial restore guard,
  which might otherwise suppress visual progress for its five-second
  pending-target window.
- Visual progress and chapter-label refreshes from list-position
  callbacks are coalesced after the Flutter frame rather than rebuilding
  during scroll layout.

## Tests authored

`test/features/reader_position_ownership_test.dart` covers authority
selection, active detached tracking, prevention of auto-persistence,
exact EPUB visual offsets, narrator advancement without changing bookmark
suggestions, and Pause/Play seek policy. These tests have been committed
but **not executed**. Existing follow, scrolling, keyboard and EPUB
navigation tests also need regression runs.

## Manual acceptance checks

1. Play a long EPUB. Scroll to another chapter while speech continues;
   the visible TOC, bookmark location and progress indicator should
   describe the page on screen, not the currently heard sentence.
2. Advance three or more audio chunks. The viewed paragraph and its
   bookmark suggestion must remain unchanged, with no audio pause/seek.
3. Create a bookmark while detached. Confirm it points to the paragraph
   on screen; reopening it must navigate to that source passage.
4. Pause and then Play while detached. Audio must resume the spoken
   passage where it paused, not move to the manually inspected chapter.
5. Press **Return to narrated passage** (or Ctrl/Cmd+Shift+J). The page,
   chapter label and progress bar should return to the current audio
   position; narration must not be restarted.
6. Repeat with Follow narration manually disabled. Scrolling should
   update only the visual position, without introducing a temporary
   return button; re-enabling follow should reconnect.
7. Check EPUB captions and illustration-only spine entries sharing
   an offset; note where identical offsets cannot uniquely identify a
   bookmarked visual-only chapter in older bookmark records.
8. Repeat in TXT and PDF text mode. Verify physical PDF page bookmarks
   are unchanged.
9. Confirm passive scrolling during playback does not change saved
   source progress, even if audio is paused afterward. Explicit seek,
   bookmark, and actual audio progress should retain their own existing
   persistence behavior.
10. Verify native media next/previous commands during detached and
    normal follow, plus rotation, links, search and chapter jumps.

## Remaining release gates

Flutter `analyze`, local unit/widget tests, and Windows/Android
integration tests with real TTS engines and media controls remain
**not executed**. No Windows build or GitHub Actions were initiated.
The draft PR is not ready to merge solely from source inspection.
