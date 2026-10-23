# Cross-chunk dialogue casting and TTS continuity

Source increment: 2026-10-23, feature/m0-flutter-foundation. Flutter
analyzer, tests and native Windows/Android builds have NOT been executed;
the owner requested development first and final integration later.

## Problem fixed

A sentence/character chunk may split one very long quotation into
several source-aligned TTS requests. Previously, precise CastSpan labels
were source-relative and could be retained across fragments, but a saved
legacy SegmentCastAssignment only matched a new speech chunk when both its
exact start and end offsets matched. Long manually labelled dialogue could
therefore silently fall back to narrator for the following fragments.

## Reader implementation

1. splitQuotedSegmentsWithRegions retains an opaque quote-group ID
   across the underlying segmentSpeech boundaries. It never infers a
   speaker; mixed narration and dialog are kept in distinct regions.
   The older public splitQuotedSegments API remains compatible.
2. prepareCastSpeech resolves source-hashed *legacy* interval labels as
   well as source-hashed precise, accepted, human-locked labels, using
   original UTF-16 ranges and optional relocated reading anchors.
   Labels from other books and character IDs not in the curated roster
   are rejected. Stale SHA-256 matches are never accepted.
3. The prepared speech segments are split on all relevant label boundaries.
   A valid fine-grained manual speaker or explicit narrator mask overrides
   a legacy whole-quote assignment, preserving exact local corrections.
   Conflicting fine-grained labels are not applied, and also suppress an
   older legacy assignment in the disputed interval. Overlapping legacy
   assignments are discarded rather than guessed from ordering.
4. coalesceQuotedSpeech conservatively groups successive fragments only
   when they belong to the **same quoted region**, preserve the **same
   resolved speaker state**, are separated solely by original whitespace,
   and the combined **original source length stays within 400 UTF-16
   code units**. Distinct quotations and narrator/character boundaries
   remain separate. Empty/unknown versus explicit narrator labels remain
   separate, even though both use narrator fallback.
5. The Flutter ReaderScreen creates this complete source-grounded queue
   before playback and maps each resulting chunk start to a verified
   speaker. It no longer falls back to the legacy exact-chunk resolver,
   which could reapply an obsolete tag after coalescing.
6. ReaderPlayer already remembers the selected native/provider voice key
   and invokes chooseVoice only when it actually changes. After
   coalescing, consecutive long-quote fragments still share the character
   voice. A narrator segment restores the narrator timbre.

The original book text and read-along UTF-16 offsets are unchanged,
including emoji. The player continues saving the current source offset
and can resume or seek by the resulting chunk boundaries. Existing
provider-specific voice mapping and per-book cloud speech permissions
remain untouched.

## Important limitations

This is **chunk-aware voice continuity**, not waveform/audio splice,
phoneme-level duration alignment or gapless output. TTS engines may insert
small pauses between calls when quotations exceed the 400-character cap.
True gapless playback or cross-chunk prosody would require engine-specific
streaming/prebuffering and platform testing. No cross-character voice
inference, hidden LLM request or full-book audio regeneration was added.

The conservative common-quote parser still does not automatically handle
complex nested quotes, unmatched delimiters or dialogue without punctuation;
the detailed manual turn editor remains available to resolve those cases.

## Tests authored, not run

- test/domain/cross_chunk_cast_test.dart: **12 tests** for long confirmed
  and legacy dialogue across source chunks; exact narrator overrides;
  fine speaker precedence; unknown segment isolation; strict 400-unit
  cap; stale/book/character validation; conflicting legacy ranges;
  source-anchor relocation; non-crossing of separate quoted turns;
  UTF-16 emoji; and suppression of disputed precise labels over legacy.
- test/audio/reader_player_test.dart: **1 added test** that runs a mocked
  native playback queue across a long labelled quote and narrator
  continuation, asserting only two provider voice transitions (narrator
  to character and back) and exact spoken text order.
- Existing tests in test/domain/dialogue_segmenter_test.dart and
  test/domain/cast_span_test.dart retain the previous API expectations.

Next production gates (deferred): dart format, Flutter analyzer, unit
tests, Windows/Android build and playback testing on available TTS engines,
particularly cloud audio seams, pause/resume and seek after coalescing.
PR #1 remains draft until those checks are completed.
