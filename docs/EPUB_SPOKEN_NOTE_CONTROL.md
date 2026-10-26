# M2 — Spoken EPUB footnote control (2026-10-26)

## Implemented

An **off-by-default, session-only** "Skip EPUB footnotes in narration"
checkbox appears in the reader playback controls when EPUB extraction has
recognized at least one eligible in-spine note body.

- The EPUB body/source string, spine anchors, search, visual layout, bookmark
  positions, cast spans, and note previews are unchanged. The option only
  prevents eligible TTS segments from reaching an audio provider.
- Source ranges come from the existing bounded EPUB2/EPUB3 semantic note
  parser and are retained **only when eligible for a source-verified local
  note preview** (same 1,600 UTF-16 unit cap). Unverified superscripts, plain
  links, ordinary paragraphs, and external/unreadable notes cannot become
  skip targets. Non-spine auxiliary notes are not in the speech queue anyway.
- At playback time, a segment is suppressed only when its **entire** verified
  UTF-16 range falls inside a note body. Chunks overlapping normal prose and
  footnote markup are still read in full, rather than dropping book text.
  This is intentionally conservative, not a claim of universal footnote
  skipping or automatic sentence subdivision.
- Filtering runs **before** persisted segment-start checkpoints, cast voice
  selection, synthesis, paid cloud-character reservations and cloud prefetch.
  Skipped segments produce no synthesis call or new saved progress and cannot
  spend cloud quota. The next spoken segment's normal callback updates its
  own source-anchored checkpoint.
- Toggling affects **subsequent** chunks; it does not interrupt a sentence
  already being spoken. Seek, note popup navigation and visual reading remain
  independently available. No SQLite migration, model key, network call or
  additional user permission is introduced.

## Relevant source

- `lib/data/epub_speech_note_filter.dart`: validated source-bounded regions
  and conservative indexed membership check.
- `lib/data/epub_text_extractor.dart` /
  `lib/data/book_decoder.dart`: retain verified note ranges from the
  background worker into the canonical document.
- `lib/audio/reader_player.dart`: optional source filter before speech work.
- `lib/features/reader/reader_screen.dart`: session-only checkbox and
  source-exact filter registration.
- `test/data/epub_speech_note_filter_test.dart`: synthetic EPUB, source
  offsets, false-positive prevention, UTF-16, TTS/checkpoint and all-skipped.

## Manual verification checklist

1. Run the repo's local `tool/run-all-tests.ps1` and collect its sanitized
   per-test results, especially the new note-filter suite.
2. In Windows and Android EPUB playback, toggle the checkbox for a book with
   explicit EPUB3 footnotes, then for an EPUB2 book with recognized endnotes.
   Check that narration continues through normal prose and skips only complete
   note chunks; validate note popups still open.
3. Use a note body that begins or ends inside a mixed chunk: verify that it
   remains spoken rather than silently omitting normal prose.
4. With cloud speech explicitly approved and a small **test-only** quota,
   confirm a skipped chunk does not reserve or transmit text. Avoid opting into
   cloud prebuffering during the initial measurements.
5. Play, pause, seek into a skipped segment, switch chapter, close/reopen, and
   verify source-aligned recovery. Reopen should default to **read notes**.
6. Verify a malformed or unmarked note link does not become skippable.

**Validation:** Source and regression tests committed but no local Flutter
analyzer/test or Windows/Android real audio runs were performed in this
GitHub-only editing environment. This is an incremental M2 feature, not a
closed cross-platform acceptance gate.

**Cloud prebuffering caveat:** when the user enables note skipping while a
prior speculative request is already in flight, that earlier provider request
cannot be recalled and might still consume quota. The new filtering rule
prevents future skipped segments from being *scheduled* for prefetch.
