# Library keyboard navigation and searchable tools — 2026-10-31

Scope: M1 reader/library usability, M6 desktop and hardware keyboard accessibility.
Branch: feature/m0-flutter-foundation.

## User behavior

| Key | Behavior |
| --- | --- |
| Ctrl/Cmd+F | Focus the existing library catalog search (only when books are present and idle). |
| Ctrl/Cmd+K | Open library tools with its local search field immediately focused. |
| Ctrl/Cmd+O | Open the already-existing local EPUB/PDF/TXT file picker, subject to import/busy safeguards. |
| F1 | Display a scrollable keyboard guide, including at enlarged text scale. |

- Toolbar-opened tools keep the compact, non-autofocused menu. Keyboard-opened
  tools expose search even if fewer than eight actions exist.
- The Keyboard shortcuts entry lives under a Help section in Library tools.
- No keyboard action runs for editable text fields, inactive routes, modal
  dialogs, key-up/repeat events or modified combinations using Alt/Shift.
- Import and tool shortcuts are unavailable during an existing import/backup;
  interrupted Android picker recovery also blocks opening a second picker.
- Ctrl/Cmd+F is disabled in an empty library: no hidden search field receives focus.
- Key commands use the same guarded import, catalog and action-sheet callbacks
  as on-screen buttons; no new book copies, audio playback, cloud or DB changes
  are performed just by opening a tool.

## Files

- lib/features/library/library_keyboard_shortcuts.dart:
  pure keyboard-action resolver, foreground Focus wrapper, accessible help.
- lib/features/library/library_screen.dart:
  search FocusNode lifecycle, toolbar hints, menu help and keyboard callbacks.
- test/features/library_keyboard_shortcuts_test.dart:
  mapping, modifiers/repeat, focused text, dialogs, callback isolation,
  narrow enlarged-text help.
- test/features/library_keyboard_integration_test.dart:
  SQLite-backed catalog, Ctrl+F focus/filter, Ctrl+K search, compact toolbar
  behavior and help discovery.

## Validation and release gates

Tests are authored but **not executed** in this environment (Flutter/Dart SDK
unavailable); no Windows/Android build or GitHub Action has been started.

1. Run analyzer and widget tests on a Flutter-equipped host and fix actual errors.
2. Try Ctrl/Cmd+F on a populated catalog and verify cursor focus/scroll; then
   try it on an empty library.
3. Check Ctrl/Cmd+K search filtering, Esc/modal dismissal and screen readers.
4. Try Ctrl/Cmd+O: cancel the picker, import one valid book, and attempt
   a repeated keystroke while an import is active; no duplicate picker.
5. Verify tablet/Android hardware keyboard, native Windows keyboard, F1 at
   200% text scale and all existing drag/drop/SAF paths.

No milestone percentage increase is warranted without native evidence.
