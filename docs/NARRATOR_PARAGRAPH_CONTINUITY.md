# M2 — Paragraph-safe narrator audio continuity (2026-10-26)

## Objective

Reduce avoidable TTS engine / MP3 decoder handoffs when successive small
sentences are spoken by the **unattributed narrator** in a single EPUB
paragraph. This does not implement gapless native playback: a 400 UTF-16
unit ceiling and non-mergable source boundaries still produce clips.

## Design and safety

- `coalesceQuotedSpeech` now supports `coalesceNarration: true`; the default
  is **false** to preserve all existing callers and unit fixtures.
- EReader enables the new option **only for EPUB** in `ReaderScreen._load`.
  The preflight's canonical paragraph/spine hard boundaries are passed in;
  when no preflight is available, the same indexed EPUB boundary generator
  is used. TXT and PDF behavior is unchanged.
- Only adjacent, *unlabelled*, quote-group-null narrator fragments may merge.
  Existing quote groups retain their prior conservative coalescing behavior;
  two different quotes and all narrator/character transitions stay separate.
- Explicit character assignments and user-locked narrator/unknown masks are
  never swallowed by unlabeled narration. A segment's existing `speakerByStart`
  entry is retained at its original source start.
- The original source substring is reused from first start to last end;
  intermediate gaps must contain whitespace only. Every input chunk has
  UTF-16 source checks and the merged text stays <=400 UTF-16 code units,
  maintaining the provider's previous per-request ceiling.
- Verified EPUB note-body starts and ends are additional hard boundaries.
  This prevents narrator coalescing from absorbing otherwise skippable note
  chunks into adjacent prose. If an *original* TTS segment already spans
  prose plus note content, the existing safe behavior still speaks it.
- Playback remains serialized in `ReaderPlayer`. No new cloud request,
  default paid prefetch setting, LLM request, consent, SQLite migration,
  speaker inference or API/provider change is introduced.

## Automated regression cases added (not executed)

`test/domain/narrator_continuity_test.dart` covers same-paragraph merge,
opt-in backwards compatibility, chapter/paragraph and quote boundaries,
known-character voices, explicit narrator masks, note edges, Unicode
source offsets, maximum 400-char output, and end-to-end sequential fake
TTS transitions from narrator -> actor -> narrator.

## Manual acceptance (Windows and Android)

1. Check out the current feature branch, run `tool/run-all-tests.ps1`, and
   publish the runner's sanitized results as already documented.
2. Use a legal EPUB narrative containing many short sentences and at least
   three sections; listen with system TTS and confirm that playback still
   follows the book in the right order, including page/chapter navigation.
3. Compare several consecutive narrator sentences and manually count
   `onSegmentStarted` checkpoints. A single merged utterance starts once
   at the first original source offset; sentence/word-level highlighting
   inside that merged utterance is **not** guaranteed.
4. Switch between a narrator and three manually assigned character voices;
   confirm that no voice leaks into the next narrator block.
5. Enable **Skip EPUB footnotes** and confirm that verified, separate note
   chunks remain skippable and popup reading remains available.
6. Repeat Pause/Play, seek, chapter jump, cold restart and Android background
   interruptions (audio focus, headset, lockscreen). Any provider-imposed
   gaps or wrong narrator restoration must be reported as native failures.

**Status:** Implementation and tests pushed to GitHub. Flutter/Dart and
real-device build/audio tests have not run in this editing environment.
The M2 70% and total ~55% implementation estimates are unchanged until native
acceptance measurements demonstrate actual improved continuity.
