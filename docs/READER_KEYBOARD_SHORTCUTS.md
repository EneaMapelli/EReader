# Foreground reader keyboard shortcuts

Date: **2026-10-29**
Branch: `feature/m0-flutter-foundation`
Scope: **M1/M2/M6 — desktop accessibility and reader navigation**

## Implemented shortcuts

| Shortcut | Action |
| --- | --- |
| Space | Toggle narration Play/Pause |
| Left arrow | Previous source-aligned spoken segment |
| Right arrow | Next source-aligned spoken segment |
| Ctrl+F (Windows), Cmd+F (macOS keyboards) | Search in the current book |
| Ctrl+B / Cmd+B | Open this book's bookmarks |
| Ctrl+K / Cmd+K | Open searchable reader tools; focus its search field |
| F1 | Open an in-app keyboard-shortcut guide |

These commands call the **existing ReaderScreen actions**: playback still
uses `ReaderMediaHandler` when attached and retains its cloud-consent,
Stop/Seek, saved offset and native voice selection barriers. The
keyboard listener does not create or control a separate audio queue.

The playback row also has a discoverable **Keyboard shortcuts (F1)**
help button. Tooltips for search, bookmarks and previous/next segment
show the relevant key combinations. On Android, touch controls remain
unchanged; hardware keyboards may use the same foreground shortcuts.

## Focus, safety and source navigation

`ReaderKeyboardShortcuts` is an optional foreground-only Focus wrapper
with a pure `resolveReaderKeyboardAction` mapper and stable callbacks:

- Only a **KeyDownEvent** triggers an action; key-up and repeated key
  events never start repeated navigation or toggle playback.
- Narration/segment shortcuts require a loaded reader with actual speech
  segments; keyboard transport is enabled in PDF **text-layer reading mode**,
  not faithful visual PDF page mode. Ctrl/Cmd+K is a separate tool-menu
  shortcut available in any loaded EPUB/TXT/PDF reader, including the faithful
  PDF page viewer, without enabling TTS.
- Shortcuts never intercept an `EditableText` focus. A text search,
  pronunciation field, title edit or voice editor can still type spaces,
  arrows and Ctrl/Cmd combinations without moving the book.
- Focused interactive controls (slider, button, action row) retain Space and
  arrow-key semantics; these keys do not accidentally seek narration.
- Ctrl/Cmd+K opens the existing tool sheet and focuses its local search
  field, even if a short PDF menu contains fewer than eight actions. Tapping
  the ordinary toolbar menu never autofocuses or forces Android's keyboard.
- Inactive routes and modal dialogs do not handle reader commands.
- Shift+arrow, Alt+arrow and unrelated modifier combinations remain
  available to operating system / accessibility / selection controls.
- Left/right move between **TTS segments**, not words or visual page
  numbers. The existing source offsets, chapter navigation, EPUB
  captions, highlights and bookmarks remain authoritative.
- Ctrl/Cmd+F and Ctrl/Cmd+B open existing dialogs rather than creating
  new providers or copying book contents elsewhere.
- Disabled controls and interruptions still use the existing player
  session guards. Keyboard actions never auto-activate cloud TTS
  without the same explicit per-book consent required by the Play button.

## Tests authored

`test/features/reader_keyboard_shortcuts_test.dart` covers:

1. Basic space/arrows/F1 routing.
2. Ctrl/Cmd combinations and rejected alternative modifiers.
3. Editing text, inactive routes and reader-not-ready rejection.
4. Repeats and key-up events.
5. Real Focus key dispatch to callbacks.
6. Search-field typing remains protected.
7. Modal dialog focus isolation.
8. No shortcuts while loading.
9. Accessible help dialog opens and closes, and can scroll when text is
   enlarged on narrow screens.
10. Ctrl/Cmd+K availability, modifiers/repeat suppression and visual-only PDF
    support; interactive-focus transport guards.
11. Shortcut-initiated search autofocus, including compact tool menus
    (see organized_action_sheet_search_test.dart).

**Tests authored, not executed.** Flutter/Dart is not installed in this
connected environment. A manual keyboard, focus, screen-reader and
native TTS review remains required before desktop/Android accessibility
is considered complete.

No Windows or Android build, CI/GitHub Action or cloud speech request
was launched.
