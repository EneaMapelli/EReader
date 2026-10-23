# Conversation speakers versus narrative referents

Increment: 2026-10-23. Source saved on feature/m0-flutter-foundation.
Flutter tests, analyzer and Windows/Android builds are deferred until final integration.

## Distinct questions

In "Mira said Hello. Anna replied Go. She ran away", confirmed speech
attributions can establish who spoke Hello and Go. They do NOT establish
who "she" refers to. EReader now presents these as two distinct, verified
categories of local review hints: prior names/accepted narrative links,
and prior **speaking characters** from human-approved voice labels.

## UI

Voice Cast > Review > Pronouns and indirect narrative references opens a
human review dialog with previous antecedent mentions and a distinct
"Who spoke earlier? Confirmed dialogue speakers" section. Each excerpt shows
the character who spoke, provenance (manually assigned segment or accepted
precise span), source text and distance before the ambiguous reference.

Multiple earlier speakers produce a warning. Contradictory overlapping
accepted labels are both omitted and flagged. The referenced-person dropdown
always starts EMPTY, even when the LLM suggests a person, so the reader
must select the referent manually. Speaker cues never offer one-click
pronoun approval or change the TTS voice. Rejection remains supported.

## Source and privacy limits

- Read-only, offline scan; max 1,200 UTF-16 units **before** the current
  reference, within the current EPUB chapter/PDF page/TXT scope only.
- At most five source-grounded earlier speech excerpts, each at most
  180 UTF-16 characters shown. Full original annotation ranges are retained
  to verify overlap even when preview excerpts are truncated.
- Precise cast labels must be accepted, human-locked, same-book and
  source-aligned with valid original anchors and SHA-256 checks.
- Legacy manually assigned segment labels must match original source
  SHA-256 and valid anchors, with a known same-book speaker.
- Pending/rejected/unlocked suggestions, stale hashes, foreign identities,
  missing anchors, and any dialogue after the selected reference are excluded.
- Conflicting full-range labels with different speakers are discarded,
  and source-identical precise/legacy duplicate labels are deduplicated,
  favoring precise labels in display.
- Source excerpts are checked for UTF-16 surrogate pair integrity.
- Speaker order is for visualization only, never an identity conclusion.

## Implementation

- lib/llm/conversation_speaker_inspector.dart implements the source-verified
  ConversationSpeakerCue and bounded ConversationSpeakerInspection.
- lib/features/reader/voice_cast_screen.dart presents the new section
  separately from NarrativeAntecedentFinder and the manual referent selector.
- test/llm/conversation_speaker_inspector_test.dart defines thirteen
  unexecuted cases covering multi-speaker scenes, manual vs precise labels,
  stale and pending labels, overlaps, source anchors, Unicode boundaries,
  book isolation, excerpt truncation and the no-evidence fallback.

No database migration, extra model request, new API permission, external
text transmission, or automatic speaker-referent link is introduced.

## Validation

Source code and static readback checks only. Flutter/Dart analyzer and tests
have NOT been executed, nor Windows/Android builds or native runtime checks.
PR #1 remains draft pending final integration per owner request.
