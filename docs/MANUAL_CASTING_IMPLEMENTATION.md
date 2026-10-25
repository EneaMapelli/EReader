# M4 manual cast — initial implementation

Status: initial implementation on the feature branch; **not compiled or run**. Native Windows/Android validation will occur at final integration, per the project owner.

## How a reader uses it

1. Import a TXT/EPUB/PDF book and enter text-reading mode.
2. Choose a native or OpenAI TTS provider and a narrator voice from the reader.
3. Open **Characters and manual voice cast** (the theatre-mask toolbar icon).
4. In **Characters**, add or rename a person, optionally with aliases, and assign a voice **from the active provider's installed/available catalog**. The available voice list is sourced from the active TTS adapter, not imagined by an LLM.
5. In **Passages**, filter/search extracted segments and assign the character who speaks. Leave passages as Narrator / unknown when attribution is unclear. For multi-speaker or mixed prose, prefer narrator for now.
6. Return to the reader. Each segment with a verified, source-anchored label uses the character's voice; the next unassigned segment automatically restores the narrator. Manual corrections update only local metadata, never book text or cloud consent.

This is a **manual-first** implementation. No LLM is called, no character is guessed, and no user books are uploaded for character recognition.

## Storage and source provenance

SQLite schema v6 adds three tables:

- cast_characters: stable per-book identity, display name and aliases.
- cast_voices: character ID and provider-specific voice name/locale. Separate profiles per provider, no silent cross-provider substitution.
- segment_cast: source book ID, original UTF-16 global start/end, SHA-256 of the exact original text, optional EPUB spine / PDF page / TXT body source anchor, and associated character ID. Foreign-key relationships cascade on deletion.

The player computes a source-offset map from anchors once on loading the book. Any missing chapter, changed text fingerprint or unavailable character voice reverts safely to narrator; it never assigns a different character automatically. Renaming a character does not change their ID, existing turns or voice.

The source content, original text positions, reading progress and cache keys are independent from manual labels. Cloud speech still requires per-book opt-in and budget reservations as before.

## Dialogue splitting

The reader now adds a quote-boundary pass after ordinary sentence segmentation. It supports common delimiters «…», “…” and "…" without changing the source text or offsets. This makes it easier to tag dialogue separately from surrounding narration. These are purely structural breaks: quotation marks do **not** identify the speaker, and nested quotes or quotation styles outside this small set still need manual review.

A passage may still contain more than one speaker, or quoted material that should use the narrator; leave such a passage unassigned. Arbitrary substring selection, forced alignment and full EPUB quote range selection are subsequent features.

## Known limitations

- Voice assignment currently uses only whole extracted speech segments; no character-specific rate/pitch/prosody or arbitrary selected character ranges yet.
- The narrator baseline is the book's selected voice. If none was selected, a system voice fallback is used; OpenAI Speech uses its default marin voice where available. Provider capability gates remain necessary for audio stitching, pitch, timings and background playback.
- Android MediaSession/background playback remains outstanding, as do offline neural ONNX TTS and other provider adapters.
- LLM model integration and automated dialogue attribution are **not** implemented. When added, suggested tags must not overwrite manual labels or send data without separate scope/cost/privacy authorization.
- There is no claim of accurate audio-boundary timing or perfect verbatim narration for OpenAI TTS.
- The SQLite schema, Flutter editor interactions and actual voice switching still need tests on Windows and Android at the final integration stage.

## Regression tests (authored, not executed)

- test/domain/voice_cast_test.dart: exact-source identity, stale hashes, anchor relocation and provider-specific profiles.
- test/domain/dialogue_segmenter_test.dart: separation of narrator and quoted dialogue without source text rewriting.
- test/audio/reader_player_test.dart: actor voice -> narrator voice, unsupported voice fallback, pause/play and seek.
- test/data/library_store_test.dart: SQLite v5-v6 upgrade, per-book cast isolation, rename stability and foreign-key cascade.

Next work: arbitrary text-span attribution with confidence/lockedByUser, in-book review queue, optional LLM annotation schema validation, speaker-aware output and real device validation.
