# Direct and accessible EPUB chapter history shortcut

Implemented on `feature/m0-flutter-foundation` · 2026-11-03 · draft PR #1.

## Reader experience

EPUB chapter visit history is now accessible directly from **one history
icon** when the current session has an actionable Back or Forward
destination. It does not add another permanent toolbar or disturb
the central chapter title.

- **Compact narration controls:** a single history icon appears in
  the wrapping transport row, beside but **separate from** the TTS
  previous/next segment and playback buttons.
- **Immersive focus mode:** the same icon is shown in the AppBar only
  when chapter history exists. Narration controls remain hidden.
- **No history:** the icon is omitted entirely, as are EPUB-only
  chapter history shortcuts in TXT/PDF reading modes.

The popup exposes only currently valid actions:

| Action | When visible |
| --- | --- |
| **Back to previous visited position** | At least one chapter Back origin |
| **Forward to next visited position** | At least one forward destination |
| **Recent chapter positions** | At least two chapter Back origins |

All callbacks reuse the reader's existing guarded source-navigation
methods (`_returnToSectionJumpOrigin`,
`_forwardToChapterVisit`, `_openChapterVisitHistory`).
Selecting an action does not start speech or change narration
preferences. Tapping the icon and dismissing the popup without an
action performs **no seek or checkpoint write**.

## Accessibility and small screens

The history popup uses a single 48px standard Flutter popup button
with a descriptive tooltip, and its three individual menu rows have
full, explicit labels and meaningful icons. Items that are not
possible are **omitted**, rather than offered as misleading commands.

The **Recent chapter positions** sheet now has a compact, truncation-
safe title/subtitle header that remains usable on a narrow viewport
at 200% text size. Each visit has a single explicit TalkBack
semantics action announcing:
- Full chapter title.
- Publisher/OPF section ordinal and count.
- Whole-book source percentage.
- Position in the newest-first visit list.

The underlying accessible return action continues to select an exact
`ReaderChapterVisit` object, not the displayed index or a speech
segment. No history is consumed until a winning, durable source seek
commits. The existing revision guards, 20-element limits and silent
illustrated OPF spine identities remain unchanged.

## Regression tests authored

- `test/features/reader_chapter_history_shortcut_test.dart`: popup
  action visibility, independent Back/Forward/Recent callbacks,
  cancellation without navigation, tooltip, and 320px at 200%
  accessibility scaling.
- `test/features/reader_compact_controls_test.dart`: only one compact
  history entry appears, it is hidden when the user has no history,
  and it never invokes the TTS segment skip callbacks.
- `test/features/reader_chapter_visit_history_sheet_test.dart`:
  each saved visit exposes an explicit TalkBack action with title,
  ordinal and newest-first order; title remains discoverable at
  320px and 200% text scale.
- `test/features/reader_focus_epub_integration_test.dart`: a
  self-contained two-chapter EPUB3 checks that Back and Forward
  work from the compact history popup, and Back remains available
  in immersive focus mode without showing TTS transport controls.

## Manual acceptance checklist

1. Open an EPUB without prior chapter switches. Verify no history
   icon appears, while chapter arrows and TTS controls still work.
2. Change to the next chapter and use the history popup → Back;
   then popup → Forward. Check both exact saved source positions
   and no automatic narration.
3. Make 3+ section switches; popup → Recent chapter positions;
   verify newest-first labels and choose an older visit.
4. Enter focus mode. Verify the history icon appears in AppBar,
   remains accessible with the popup and never reveals TTS controls.
5. Repeat on a 320px phone at 200–300% text, with a long translated
   chapter name and TalkBack enabled. Verify each distinct action
   is announced once, and the chapter visit header is truncated
   without horizontal overflow.
6. Cancel both popup and history sheet and confirm no position
   write. Verify TXT/PDF do not show EPUB-specific history.
7. Verify silent illustrated OPF sections, same-offset anchors,
   revision-superseded navigations and session reload continue to
   preserve the established history safeguards.

**Validation:** code, tests and documentation committed and statically
inspected. Flutter analyzer, widget/integration execution and native
device acceptance remain pending. No Windows build or GitHub Actions
were triggered; PR #1 remains draft.
