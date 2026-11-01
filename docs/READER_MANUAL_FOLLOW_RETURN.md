# Manual scrolling while narration is active — temporary auto-follow detachment

_Date: 2026-11-01. Implemented on `feature/m0-flutter-foundation`, PR #1 draft._

## Reader behavior

- With **Follow narration** enabled, scrolling the active EPUB, TXT or PDF
  extracted-text viewport with a real mouse wheel, vertical touchpad pan,
  touchscreen drag or unmodified keyboard scrolling key temporarily suspends
  automatic viewport jumps, **only while audio is playing**. Narration itself
  continues with the existing voice, position and cost/privacy settings.
- An accessible **Return to narrated passage** floating button and a
  **Navigate & find → Return to narrated passage** menu action appear while
  follow is temporarily detached. Both go directly to the current spoken
  segment without a player seek, restart, pause, paid TTS request or
  deliberate progress save. The follow preference remains enabled.
- A manual scroll while narration is idle does **not** detach. A disable of
  **Follow narration** is a separate, explicit choice; the return control
  is not displayed when disabled.
- Temporarily detached state remains until explicit return, a follow-setting
  change, or a new reader load. Reading another book does not inherit
  detachment. Pausing playback does not silently reset the user's decision.
- Vertical drag notifications are accepted only from the book-list viewport;
  nested horizontal table scrolls, drag-free relayout notifications and
  synthetic scroll events cannot detach narration follow. Scroll gestures
  coalesce a single post-frame UI refresh to avoid calling setState during
  a Flutter scroll/layout phase.
- Rotation, changing reading appearance, opening panels, native programmatic
  follow jumps, TOC/voice navigation and ordinary rebuilds are not
  classified as manual scroll events.
- PDF physical page view has no follow button; the change applies only to
  the extracted text reader.

## Safety and persistence

The `ReaderNarrationFollowPolicy` is in-memory presentation state only.
`ReaderPlayer` and `LibraryStore` are never called by its manual-scroll
transition. Returning calls `ItemScrollController.jumpTo` and suspends
viewport checkpoint writes before moving; it does not modify the audio
cursor or any exact EPUB source anchor. The existing normal audio completion
and crash-recovery checkpoints are unaffected.

## Tests authored (not executed)

- `test/features/reader_narration_follow_policy_test.dart`: initial state,
  playback-only suspension, duplicate scroll, resumption, disabled preference,
  and new-document reset.
- `test/features/reader_return_to_narration_button_test.dart`: accessibility,
  visible control identity and explicit callback.
- `test/features/reader_keyboard_shortcuts_test.dart`: Ctrl/Cmd+Shift+J
  rejoins narration only when detached, never from a hidden route, editor,
  focused control, missing reader or repeated key; does not trigger playback.
- `test/features/reader_direct_scroll_input_test.dart`: vertical direct
  drag notifications are accepted, horizontal, synthetic and end events
  are rejected.
- `test/features/reader_tool_menu_options_test.dart`: return action only
  exists in supported text-mode/detached states, follow preference still
  appears selected.

## Manual verification checklist (Windows and Android)

1. Start audible narration and use wheel/touchpad/touch drag to scroll
   elsewhere. Confirm audio continues, the current sentence is not dragged
   back into view at the next TTS chunk and the return button is shown.
2. While still narrating, tap **Return to narrated passage**. Confirm the
   current spoken segment appears and automatic follow resumes on the next
   speech chunk; no extra synthesis, Stop/Seek or playback restart.
3. Repeat with keyboard Page Down and arrow-down scrolling outside interactive
   widgets; focused sliders/text input must retain their own keys. Press
   **Ctrl/Cmd+Shift+J** to rejoin the narrator without Play/Seek. Verify the
   shortcut does nothing when not detached, during text entry and from a
   hidden route. Scroll horizontally within an EPUB table: the return
   button must *not* appear solely because of table movement.
4. Disable **Follow narration**, then scroll while audio plays: no return
   button must appear. Re-enable following; confirm standard follow behavior.
5. Pause after scrolling away: the return action should still work without
   resuming audio; it must not change the stored reading position.
6. With **Hide narration controls** enabled, both focus-restore and
   return-to-narration buttons must remain usable without obscuring controls.
7. Check TXT, mixed EPUB with unspoken illustrated spine entries, and PDF
   extracted text separately; physical PDF pages must be unaffected.
8. Rotate/reflow/navigate EPUB notes and links and change text spacing.
   These programmatic changes must not trigger a false detachment or
   overwrite bookmarks.
9. Verify that after tapping Return and exiting/reopening, progress remains
   at the correct speech/reading checkpoint; no retroactive viewport save
   should rewrite an exact EPUB source bookmark.
10. At final integration, run local `flutter analyze`, the targeted follow,
    keyboard and scroll-filter test suites, and physical-device tests.
    No builds/Actions were started
    in this code-editing session.

**Validation status:** code/test authored and committed; Dart/Flutter tests,
Windows/Android UI behavior and native TTS integration have not been executed.
Do not merge the draft PR or mark follow UX verified on devices yet.
