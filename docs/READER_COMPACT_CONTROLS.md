# Compact reader transport and advanced narration controls — 2026-10-31

Branch: feature/m0-flutter-foundation
Scope: M2 reader experience / M6 accessibility.

## What changed

The reading surface no longer reserves most of its height for always-visible
speech settings. A **compact transport bar is the default** for TXT, EPUB
and PDF text-layer reading when playable segments exist.

Always visible at the bottom:
- Exact-source book progress slider; seeking still commits only on release.
- Current spoken segment or explicit "Reading complete" status.
- Previous segment, Play/Pause, Next segment.
- A "More narration controls" button. Its tooltip indicates if a sleep
  timer is active. The four actions are icon buttons with accessible hints,
  arranged in a wrapping layout on narrow or large-text screens.

The **More narration controls** action shows the original full reader
control set, including EPUB section navigation, spoken progress and speaker,
sleep timer, footnote narration options, local/cloud audio buffering options,
voice selection, performance diagnostics, speech preference scope, pitch,
volume, speed, language and pauses. It has a "Less controls" action to
return to reading. All existing audio-provider and database callbacks are
preserved; merely opening the panel never starts playback or cloud speech.

The advanced panel has a separate visible scrollbar and its height is bounded
to 52% of the viewport (130–420 logical pixels). This keeps part of the book
visible even when the diagnostics and voice settings are long, and avoids a
full-height column overflow on small phones. Expanded controls are owned by
the foreground ReaderScreen and are not persisted as a book preference:
opening a new book starts in spacious reading mode.

The native PDF page viewer is intentionally unchanged; faithful PDF pages
continue using their own page navigation and zoom controls. The reader AppBar,
search, chapter directory, bookmarks, F1 keyboard help and existing audio
shortcuts also remain unchanged.

## Files and verification

- lib/features/reader/reader_compact_controls.dart — independent compact
  transport UI, live segment status, readable tooltips, wrapping buttons.
- lib/features/reader/reader_screen.dart — defaults to compact, retains
  source-progress slider, bounded scrollable advanced view and callbacks.
- test/features/reader_compact_controls_test.dart — callback isolation,
  Play/Pause state, sleep timer hint and 320x420 screen with 200% text.

The code and tests are committed but Flutter/Dart is unavailable in this
environment: **tests have not been executed**. No Windows executable,
Android build, CI job or GitHub Action was intentionally started.

## Native acceptance checklist

1. Import a long TXT and an EPUB: more readable text must remain visible,
   and source progress / play / previous / next should still work.
2. Open advanced controls, scroll to the voice, rate and optional TTS
   settings at the very bottom, then collapse the panel. Ensure playback
   continues and selected voice/consent persist as before.
3. Verify system text sizes 150%, 200% and 250% on a 320–390 px Android
   display; confirm transport buttons remain tappable and no panel overflows.
4. With a sleep timer active, verify its active hint remains discoverable in
   compact mode; cancel the timer from advanced controls.
5. Open a visual PDF: the page navigation and zoom must remain unchanged.
6. Check TalkBack/Narrator semantics and keyboard focus; Ctrl/Cmd commands
   must still reach the reader, and focus in the settings controls must not
   trigger narration navigation.

This increment does not claim a native test pass or change milestone
completion / release readiness estimates.
