import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'reading_anchor.dart';
import 'speech_segment.dart';

/// Manually curated cast identities. Never infer name/gender from voice.
/// Character IDs are stable independent of the display name.
class CastCharacter {
  const CastCharacter({
    required this.id,
    required this.bookId,
    required this.name,
    this.aliases = const [],
  });

  final String id;
  final String bookId;
  final String name;
  final List<String> aliases;

  void validate() {
    if (id.isEmpty || id.length > 128 || bookId.isEmpty) {
      throw const FormatException('Invalid cast identity');
    }
    if (name.trim().isEmpty || name.length > 120) {
      throw const FormatException('Character must have a 1–120 character name');
    }
    if (aliases.length > 50 ||
        aliases.any((alias) => alias.trim().isEmpty || alias.length > 120)) {
      throw const FormatException('Invalid character aliases');
    }
  }
}

/// Voice IDs are scoped to providers. A voice called "nova" at one provider
/// does not refer to the same timbre at any other provider.
class CastVoiceAssignment {
  const CastVoiceAssignment({
    required this.characterId,
    required this.providerId,
    required this.voiceName,
    required this.voiceLocale,
  });

  final String characterId;
  final String providerId;
  final String voiceName;
  final String voiceLocale;

  void validate() {
    if (characterId.isEmpty || providerId.isEmpty ||
        voiceName.trim().isEmpty || voiceLocale.trim().isEmpty ||
        voiceName.length > 200 || voiceLocale.length > 40) {
      throw const FormatException('Invalid provider-specific voice assignment');
    }
  }
}

/// Exact manually assigned speech segment. The sha256 of the ORIGINAL source
/// segment detects extractor drift: no stale label can silently be reassigned
/// to changed content. Source anchor allows relocation after offset shifts.
class SegmentCastAssignment {
  const SegmentCastAssignment({
    required this.bookId,
    required this.start,
    required this.end,
    required this.sourceDigest,
    required this.characterId,
    this.anchor,
  });

  final String bookId;
  final int start;
  final int end;
  final String sourceDigest;
  final String characterId;
  final ReadingAnchor? anchor;

  static String fingerprint(String source) =>
      sha256.convert(utf8.encode(source)).toString();

  void validate() {
    if (bookId.isEmpty || characterId.isEmpty || start < 0 || end <= start ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceDigest)) {
      throw const FormatException('Invalid speech attribution');
    }
  }

  bool matches(SpeechSegment segment, {int? anchoredOffset}) {
    final effectiveStart = anchoredOffset ?? start;
    return segment.start == effectiveStart &&
        segment.end == effectiveStart + (end - start) &&
        sourceDigest == fingerprint(segment.text);
  }
}

/// Immutable snapshot used by the player during narration. A missing or stale
/// attribution always returns null (the narrator), never a guessed speaker.
/// Casting cannot add, remove or reorder a single character in the book.
class VoiceCastResolver {
  VoiceCastResolver({
    required List<SegmentCastAssignment> attributions,
    required List<CastVoiceAssignment> voices,
    required this.providerId,
    required this.bookId,
    required this.offsetFromAnchor,
  }) : _attributions = List.unmodifiable(attributions),
       _voices = List.unmodifiable(voices);

  final String providerId;
  final String bookId;
  final int? Function(ReadingAnchor) offsetFromAnchor;
  final List<SegmentCastAssignment> _attributions;
  final List<CastVoiceAssignment> _voices;

  String? speakerFor(SpeechSegment segment) {
    for (final attribution in _attributions) {
      if (attribution.bookId != bookId) continue;
      final relocated = attribution.anchor == null
          ? null : offsetFromAnchor(attribution.anchor!);
      if (attribution.anchor != null && relocated == null) continue;
      if (attribution.matches(segment, anchoredOffset: relocated)) {
        return attribution.characterId;
      }
    }
    return null;
  }

  CastVoiceAssignment? voiceFor(SpeechSegment segment) {
    final speaker = speakerFor(segment);
    if (speaker == null) return null;
    for (final voice in _voices) {
      if (voice.characterId == speaker && voice.providerId == providerId) {
        return voice;
      }
    }
    return null;
  }
}
