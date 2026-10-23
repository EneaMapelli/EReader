import '../domain/cast_span.dart';
import '../domain/reading_anchor.dart';
import '../domain/voice_cast.dart';

enum ConversationTurnOrigin { reviewedSpan, manualSegment }

/// A verified earlier dialogue turn: the named character SPOKE these words.
/// It does not say who any pronoun or title inside a later sentence refers to.
class ConversationSpeakerCue {
  const ConversationSpeakerCue({
    required this.speakerId,
    required this.start,
    required this.end,
    required this.attributionStart,
    required this.attributionEnd,
    required this.excerpt,
    required this.sourceDigest,
    required this.origin,
  });

  final String speakerId;
  /// Source bounds of the displayed (possibly truncated) excerpt.
  final int start;
  final int end;
  /// Full source range of the approved speaker attribution.
  final int attributionStart;
  final int attributionEnd;
  final String excerpt;
  final String sourceDigest;
  final ConversationTurnOrigin origin;

  bool matchesSource(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      source.substring(start, end) == excerpt &&
      attributionStart <= start && end <= attributionEnd &&
      CastSpan.validUtf16Range(
        source, attributionStart, attributionEnd) &&
      CastSpan.digest(excerpt) == sourceDigest;
}

class ConversationSpeakerInspection {
  const ConversationSpeakerInspection({
    required this.turns,
    required this.lookbackStart,
    required this.referenceStart,
    required this.conflictingLabels,
  });

  final List<ConversationSpeakerCue> turns;
  final int lookbackStart;
  final int referenceStart;
  /// Two accepted speaker labels disagree about the same preceding words.
  /// Such labels are suppressed from the cue list rather than ranked.
  final bool conflictingLabels;

  bool get hasMultipleSpeakers =>
      turns.map((turn) => turn.speakerId).toSet().length > 1;
}

/// Examines attributions already accepted by a person (never LLM proposals).
/// No text after the target reference is inspected; these are previous
/// SPEAKERS, not antecedents or predicted referents for the current pronoun.
class ConversationSpeakerInspector {
  const ConversationSpeakerInspector();

  static const maxLookback = 1200;
  static const maxTurns = 5;
  static const maxExcerptCharacters = 180;

  ConversationSpeakerInspection inspect({
    required String bookId,
    required String source,
    required int scopeStart,
    required int referenceStart,
    required int referenceEnd,
    required List<CastCharacter> cast,
    required List<CastSpan> reviewedSpans,
    required List<SegmentCastAssignment> manualSegments,
    required int? Function(ReadingAnchor) offsetFromAnchor,
  }) {
    if (bookId.isEmpty || scopeStart < 0 ||
        !CastSpan.validUtf16Range(source, referenceStart, referenceEnd) ||
        referenceStart < scopeStart) {
      throw const FormatException('Invalid dialogue review boundary');
    }
    final known = <String>{};
    for (final person in cast) {
      person.validate();
      if (person.bookId != bookId || !known.add(person.id)) {
        throw const FormatException('Foreign or duplicate review character');
      }
    }
    var begin = (referenceStart - maxLookback)
        .clamp(scopeStart, referenceStart).toInt();
    if (begin < referenceStart && begin > 0 &&
        source.codeUnitAt(begin) >= 0xDC00 &&
        source.codeUnitAt(begin) <= 0xDFFF) {
      begin++;
    }
    final all = <ConversationSpeakerCue>[];
    void add({
      required int start,
      required int end,
      required String speaker,
      required ConversationTurnOrigin origin,
    }) {
      if (!known.contains(speaker) || start < begin ||
          end > referenceStart ||
          !CastSpan.validUtf16Range(source, start, end)) return;
      final excerptStart = (end - maxExcerptCharacters)
          .clamp(start, end).toInt();
      var left = excerptStart;
      if (left > start && source.codeUnitAt(left) >= 0xDC00 &&
          source.codeUnitAt(left) <= 0xDFFF) left++;
      if (!CastSpan.validUtf16Range(source, left, end)) return;
      final excerpt = source.substring(left, end);
      all.add(ConversationSpeakerCue(
        speakerId: speaker,
        start: left,
        end: end,
        attributionStart: start,
        attributionEnd: end,
        excerpt: excerpt,
        sourceDigest: CastSpan.digest(excerpt),
        origin: origin,
      ));
    }

    for (final span in reviewedSpans) {
      if (span.bookId != bookId ||
          span.status != CastSpanStatus.accepted ||
          !span.lockedByUser || span.speakerId == null) continue;
      final start = span.resolvedStart(offsetFromAnchor);
      if (start == null || start < begin ||
          start + span.length > referenceStart) continue;
      // Never even hash text after the reference. Check hard bounds first.
      if (!span.matchesSource(source, offsetFromAnchor)) continue;
      add(
        start: start, end: start + span.length,
        speaker: span.speakerId!,
        origin: ConversationTurnOrigin.reviewedSpan,
      );
    }
    for (final item in manualSegments) {
      if (item.bookId != bookId || !known.contains(item.characterId)) continue;
      final start = item.anchor == null
          ? item.start : offsetFromAnchor(item.anchor!);
      if (start == null) continue;
      final end = start + item.end - item.start;
      if (start < begin || end > referenceStart ||
          !CastSpan.validUtf16Range(source, start, end) ||
          SegmentCastAssignment.fingerprint(
              source.substring(start, end)) != item.sourceDigest) continue;
      add(
        start: start, end: end, speaker: item.characterId,
        origin: ConversationTurnOrigin.manualSegment,
      );
    }

    // Contradictions between TWO different approved labels on overlapping
    // source words are not an opportunity to choose the newest model label.
    // Both are omitted, and the review UI receives an explicit warning.
    final conflicts = <int>{};
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        if (all[i].speakerId != all[j].speakerId &&
            all[i].attributionStart < all[j].attributionEnd &&
            all[j].attributionStart < all[i].attributionEnd) {
          conflicts.add(i);
          conflicts.add(j);
        }
      }
    }

    final filtered = [
      for (var i = 0; i < all.length; i++)
        if (!conflicts.contains(i) && all[i].matchesSource(source)) all[i],
    ];
    filtered.sort((a, b) {
      final recency = b.end.compareTo(a.end);
      if (recency != 0) return recency;
      // Prefer precisely reviewed spans when both sources describe the same
      // utterance, without duplicating it in the dialogue history.
      final origin = a.origin.index.compareTo(b.origin.index);
      return origin != 0 ? origin : a.speakerId.compareTo(b.speakerId);
    });
    final unique = <String>{};
    final output = <ConversationSpeakerCue>[];
    for (final cue in filtered) {
      final key = cue.speakerId + ':' +
          cue.attributionStart.toString() + ':' +
          cue.attributionEnd.toString();
      if (!unique.add(key)) continue;
      output.add(cue);
      if (output.length == maxTurns) break;
    }
    return ConversationSpeakerInspection(
      turns: List.unmodifiable(output),
      lookbackStart: begin,
      referenceStart: referenceStart,
      conflictingLabels: conflicts.isNotEmpty,
    );
  }
}
