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

## Focus reading mode and small-screen text viewport

Reader tools > Reading appearance now offers **Hide narration controls**
when the book has playable text (EPUB, TXT or the PDF text layer).
The lower transport/progress panel disappears to give the reading content
more vertical space, but the normal reader AppBar stays available for
navigation and settings. A small, accessible **Show narration controls**
floating button remains visible at the lower edge, including with large
system fonts. The same reader-tools action also reverses the mode.

### Protecting bookmarks during visual-only layout changes

Changing between compact/expanded controls, hiding/restoring transport,
or changing reading appearance can change the first paragraph visible
without any scroll gesture. The reader now cancels pending viewport
checkpoint writes before these transitions and suspends viewport-derived
saves until a genuine user scroll resumes. The saved source offset and
EPUB spine anchor are not overwritten simply because a row of controls
appeared or disappeared.

Only an actual input inside the reading viewport re-enables normal
manual-scroll tracking: touch drag details, physical wheel/trackpad scroll
or unmodified keyboard scrolling keys (Up/Down, Page Up/Down, Home/End)
when not editing or controlling an interactive widget. A generic
UserScrollNotification is NOT trusted: Flutter can also emit it during
programmatic jumps or narration auto-follow. Modified keyboard shortcuts
still take their ordinary source-exact chapter navigation path and do not
masquerade as manual scrolls.

Explicit book search/TOC/segment navigation still uses its existing
independent source-position save path. The gate does not alter audio/TTS,
request network access, or introduce a new database schema.

Regression tests cover relayout suppression, synthetic jump/animateTo
notifications, genuine touch drag resumption, keyboard scroll intent vs
chapter shortcuts and typing, plus an integrated TXT reader scenario
checking the database manual-position revision while expanding,
hiding and restoring narration controls.

This focus setting is intentionally **session-only** and starts off for
each newly opened reader. Activating it collapses any previously expanded
advanced-control panel. It does not press Play/Pause or seek, and does not
explicitly save a new reading position, TTS preference, or cloud-consent
value. Returning from PDF text-layer mode to the native PDF page viewer
automatically resets focus mode so the PDF page controls are unchanged.

On AppBars narrower than 420 px, or when the system scales a 16 px
label to at least 26 px, the reader keeps its Back/title and Reader tools
actions visible while moving the direct EPUB contents, internal-link return
and in-book search icons into the existing organized Reader tools menu.
Those actions remain available in that menu, and their foreground keyboard
shortcuts continue to work. Wider screens retain the original direct icons.

On viewports narrower than 380 logical pixels, left/right reading margins
shrink from 24 px to 14 px. Wider layouts retain their existing 24 px.
While focus mode is active the scrollable book receives 104 px of bottom
clearance, so the final paragraph can scroll above the floating restore
button without being obscured. The source positions and author-defined
EPUB sections are unaffected by these insets.

## Files and verification

- lib/features/reader/reader_compact_controls.dart — independent compact
  transport UI, live segment status, readable tooltips, wrapping buttons.
- lib/features/reader/reader_screen.dart — defaults to compact, retains
  source-progress slider, bounded scrollable advanced view and callbacks.
- lib/features/reader/reader_focus_restore_button.dart — accessible
  always-visible restore action when the lower controls are hidden.
- lib/features/reader/reader_viewport_save_gate.dart — suppresses bookmark
  writes caused only by viewport resizing.
- lib/features/reader/reader_viewport_layout.dart — deterministic
  small-phone horizontal margins, AppBar compactness and bottom FAB clearance.
- lib/features/reader/reader_tool_menu_options.dart — contextual
  focus-mode toggle, never shown for the native PDF page viewer.
- test/features/reader_compact_controls_test.dart — callback isolation,
  Play/Pause state, sleep timer hint and 320x420 screen with 200% text.
- test/features/reader_focus_restore_button_test.dart — actionable
  accessible restore FAB, including a narrow large-text smartphone.
- test/features/reader_viewport_save_gate_test.dart — relayout-versus-user
  scroll intent and resumption behavior.
- test/features/reader_focus_checkpoint_integration_test.dart — actual
  ReaderScreen and local TXT persisted-position revision guard.
- test/features/reader_viewport_layout_test.dart — small-screen margins,
  380 px breakpoint, and bottom clearance.
- test/features/reader_tool_menu_options_test.dart — focus toggle
  selected state and PDF/empty-text exclusions.

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

7. Open focus mode from Reader tools, restore it with the floating button,
   then repeat with an active sleep timer and while TTS is playing; the
   underlying player state must not be changed by display toggling.
8. On a 320 px viewport, scroll to the last paragraph in focus mode:
   the final words must remain accessible above the restore button.
9. Toggle focus mode after opening a PDF's text layer, return to native
   PDF pages and verify focus mode is cleared and page navigation works.
10. At 320 px and 200% text scaling, confirm the book title and Reader
    tools icon remain visible; open tools to reach EPUB contents/search/link
    return actions hidden from the compact AppBar.

This increment does not claim a native test pass or change milestone
completion / release readiness estimates.
