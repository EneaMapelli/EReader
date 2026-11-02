# Immersive reading: compact visual progress and F11 shortcut

Implemented on `feature/m0-flutter-foundation` (draft PR #1) on 2026-11-02.

## User experience

The reader's focus/immersion mode hides the entire bottom narration
panel to give text more vertical space. Previously that also hid
source progress, forcing users to leave focus mode to see how much of
the book they had read.

When focus mode is active on EPUB, TXT or PDF **extracted-text** views,
a compact progress strip now appears in the existing AppBar header:

- Source-text percentage and a slim progress bar reflect the
  **visible reading position** using existing `_visibleProgressOffset`.
  It is not a PDF physical page number or an estimated audio duration.
- Tapping the strip opens the existing **Go to book position** dialog,
  without pausing, seeking or starting the speech engine simply by
  opening it. Choosing a destination explicitly uses the established
  latest-intent seek and checkpoint pipeline. Cancel leaves SQLite
  reading progress unchanged.
- Screen readers receive an explicit actionable semantics label
  including the current percentage; unlike a decorative progress bar
  the control can be activated through its semantics tap action.
- It refreshes through `_visualProgressTick`, which already tracks
  visible viewport movement independently of a detached narration
  cursor, including silent EPUB source blocks and explicit exact-source
  jumps.
- A visual-only native PDF page view does **not** display the source
  progress bar, because PDF page position is a different coordinate.
  Focus controls in that mode are already unavailable.
- **F11** toggles immersive reading on Windows/desktop when the text
  reader is ready. It delegates to the existing visual layout-change
  gate, so it never creates a new reading checkpoint, seeks speech,
  or re-enables follow. Text inputs, hidden routes, modified keys,
  repeated keydown and unavailable readers do not trigger F11.
  The shortcut is included in the reader's F1 help dialog.

The bottom restore-controls button remains available, and the normal
reading transport/progress slider reappears when focus mode is disabled.

## Implementation

- `lib/features/reader/reader_focus_progress_strip.dart`: a small,
  stateless, accessible progress/navigate presentation component.
- `lib/features/reader/reader_screen.dart`: conditional AppBar bottom,
  existing visual-source progress listener, existing go-to dialog and
  F11 callback via existing layout-gate method.
- `lib/features/reader/reader_keyboard_shortcuts.dart`: guarded focus
  keyboard action, dispatch and updated help.

## Regression coverage

- `test/features/reader_focus_progress_strip_test.dart`: percentage
  calculation/clamping, tap and semantics action, unknown length, narrow
  viewport and enlarged typography.
- `test/features/reader_focus_checkpoint_integration_test.dart`: mode
  shows visual progress, dialog cancel never writes a reading position,
  confirmed 75% jump persists an explicit position and remains immersed;
  F11 enter/exit does not change a saved checkpoint.
- `test/features/reader_keyboard_shortcuts_test.dart`: F11 key mapping,
  inactive-reader, editor, hidden route, modifier and repeat guards,
  and transport independence.

## Manual acceptance

1. Open an EPUB with silent sections. Enter focus mode via tools or F11:
   progress should remain visible and display the source position of
   the currently consulted text.
2. Scroll during TTS, keeping visual follow temporarily detached:
   the progress strip tracks the visible text; speech continues from
   its own position, with the existing return-to-narration action.
3. Tap progress and cancel: book progress and playback stay unchanged.
   Tap again, select 75%: navigation saves a source-exact checkpoint,
   preserves focus mode and never auto-starts narration.
4. On TXT and PDF extracted-text views check visible progress and the
   existing Go-to-position dialog. Native PDF pages must remain unchanged.
5. Verify at widths 320–420 logical pixels, high text scaling and
   TalkBack/screen-reader activation. Ensure no clipping or overlapping
   AppBar controls and no accidental keyboard transport actions.
6. Repeat F11 while focus changes/keyboard search/dialog routes open;
   inactive routes and editors must keep their keyboard behavior.

**Validation:** source changes, integration tests and regression tests
are authored and committed, not executed with Flutter or native
Windows/Android devices. Do not treat a passing code inspection as a
passing runtime test. Per project preference, no build or GitHub
Actions have been launched and PR #1 remains in draft.
