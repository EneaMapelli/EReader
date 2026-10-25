import '../domain/cast_span.dart';
import '../domain/narrative_reference.dart';
import '../domain/voice_cast.dart';

enum AntecedentCueKind { explicitName, reviewedNarrativeLink }

/// A verified, earlier local cue shown to a human. It is NEVER a diagnosis
/// of who the text refers to and must not drive the narration engine.
class NarrativeAntecedentCue {
  const NarrativeAntecedentCue({
    required this.characterId,
    required this.start,
    required this.end,
    required this.matchedText,
    required this.kind,
    required this.contextStart,
    required this.context,
    required this.contextHash,
  });

  final String characterId;
  final int start;
  final int end;
  final String matchedText;
  final AntecedentCueKind kind;
  final int contextStart;
  final String context;
  final String contextHash;

  int get contextEnd => contextStart + context.length;

  bool matchesOriginal(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      CastSpan.validUtf16Range(source, contextStart, contextEnd) &&
      contextStart <= start && end <= contextEnd &&
      source.substring(start, end) == matchedText &&
      source.substring(contextStart, contextEnd) == context &&
      CastSpan.digest(context) == contextHash;
}

class NarrativeAntecedentInspection {
  const NarrativeAntecedentInspection({
    required this.cues,
    required this.windowStart,
    required this.windowEnd,
  });

  /// Empty cues mean 'no local signal', NOT evidence for a narrator.
  final List<NarrativeAntecedentCue> cues;
  final int windowStart;
  final int windowEnd;

  bool get containsDifferentPeople =>
      cues.map((c) => c.characterId).toSet().length > 1;
}

/// Strictly local look-behind within one scope, with an optional chain of
/// previously MANUALLY ACCEPTED references. No LLM, I/O or future text.
/// Different nearby identities remain competing hints rather than an answer.
class NarrativeAntecedentFinder {
  const NarrativeAntecedentFinder();

  static const maxLookback = 900;
  static const maxCues = 5;
  static const maxSnippet = 160;

  static final RegExp _letter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  bool _partOfWord(String source, int offset, {required bool before}) {
    if (before) {
      if (offset == 0) return false;
      final last = source.codeUnitAt(offset - 1);
      final from = last >= 0xDC00 && last <= 0xDFFF && offset >= 2
          ? offset - 2 : offset - 1;
      return _letter.hasMatch(source.substring(from, offset));
    }
    if (offset == source.length) return false;
    final first = source.codeUnitAt(offset);
    final to = first >= 0xD800 && first <= 0xDBFF &&
        offset + 1 < source.length ? offset + 2 : offset + 1;
    return _letter.hasMatch(source.substring(offset, to));
  }

  NarrativeAntecedentInspection inspect({
    required String bookId,
    required String source,
    required int scopeStart,
    required int referenceStart,
    required int referenceEnd,
    required List<CastCharacter> cast,
    List<NarrativeReferenceCandidate> reviewedReferences = const [],
  }) {
    if (bookId.isEmpty || scopeStart < 0 || referenceStart < scopeStart ||
        !CastSpan.validUtf16Range(
            source, referenceStart, referenceEnd)) {
      throw const FormatException('Invalid reference boundary');
    }
    var start = (referenceStart - maxLookback)
        .clamp(scopeStart, referenceStart).toInt();
    if (start < referenceStart &&
        !CastSpan.validUtf16Range(source, start, referenceStart) &&
        source.codeUnitAt(start) >= 0xDC00 &&
        source.codeUnitAt(start) <= 0xDFFF) {
      start++;
    }
    final prefix = source.substring(start, referenceStart);
    final people = <String, CastCharacter>{};
    for (final character in cast) {
      character.validate();
      if (character.bookId != bookId) {
        throw const FormatException('Foreign-book character in local cues');
      }
      if (people.containsKey(character.id)) {
        throw const FormatException('Duplicate local character identifier');
      }
      people[character.id] = character;
    }

    final found = <NarrativeAntecedentCue>[];
    void addCue({
      required String characterId,
      required int mentionStart,
      required int mentionEnd,
      required AntecedentCueKind kind,
    }) {
      if (mentionStart < start || mentionEnd > referenceStart ||
          !CastSpan.validUtf16Range(source, mentionStart, mentionEnd)) {
        return;
      }
      var contextStart =
          (mentionStart - 35).clamp(scopeStart, mentionStart).toInt();
      var contextEnd =
          (mentionEnd + 45).clamp(mentionEnd, referenceStart).toInt();
      while (contextEnd - contextStart > maxSnippet) {
        if (contextEnd - mentionEnd > mentionStart - contextStart) {
          contextEnd--;
        } else {
          contextStart++;
        }
      }
      // Tighten the presentation only, without shifting the quoted mention.
      if (contextStart < mentionStart &&
          source.codeUnitAt(contextStart) >= 0xDC00 &&
          source.codeUnitAt(contextStart) <= 0xDFFF) {
        contextStart++;
      }
      if (contextEnd > mentionEnd &&
          source.codeUnitAt(contextEnd - 1) >= 0xD800 &&
          source.codeUnitAt(contextEnd - 1) <= 0xDBFF) {
        contextEnd--;
      }
      if (contextEnd - contextStart > maxSnippet ||
          !CastSpan.validUtf16Range(
              source, contextStart, contextEnd)) return;
      final context = source.substring(contextStart, contextEnd);
      found.add(NarrativeAntecedentCue(
        characterId: characterId,
        start: mentionStart,
        end: mentionEnd,
        matchedText: source.substring(mentionStart, mentionEnd),
        kind: kind,
        contextStart: contextStart,
        context: context,
        contextHash: CastSpan.digest(context),
      ));
    }

    for (final character in cast) {
      if (character.bookId.isEmpty) continue;
      for (final name in {character.name, ...character.aliases}) {
        if (name.trim().length < 2 || name.length > 120) continue;
        final re = RegExp(RegExp.escape(name),
            caseSensitive: false, unicode: true);
        for (final match in re.allMatches(prefix)) {
          final from = start + match.start;
          final to = start + match.end;
          if (_partOfWord(source, from, before: true) ||
              _partOfWord(source, to, before: false)) continue;
          addCue(
            characterId: character.id,
            mentionStart: from, mentionEnd: to,
            kind: AntecedentCueKind.explicitName,
          );
        }
      }
    }

    for (final reviewed in reviewedReferences) {
      if (reviewed.bookId != bookId ||
          reviewed.status != NarrativeReferenceStatus.accepted ||
          reviewed.approvedCharacterId == null ||
          !people.containsKey(reviewed.approvedCharacterId) ||
          reviewed.start < start || reviewed.end > referenceStart ||
          !reviewed.matchesSource(source)) continue;
      addCue(
        characterId: reviewed.approvedCharacterId!,
        mentionStart: reviewed.start, mentionEnd: reviewed.end,
        kind: AntecedentCueKind.reviewedNarrativeLink,
      );
    }

    // Recency follows the END of a mention. An alias may contain the
    // shorter canonical name at its tail ("Captain Mira" vs "Mira").
    // If both end at the same position, prefer the complete longer alias
    // rather than discarding it as a duplicate of the shorter substring.
    // This ordering supplies evidence only, never an identity verdict.
    found.sort((a, b) {
      final recency = b.end.compareTo(a.end);
      if (recency != 0) return recency;
      final specificity = a.start.compareTo(b.start);
      return specificity != 0 ? specificity :
          a.characterId.compareTo(b.characterId);
    });
    final used = <String>{};
    final output = <NarrativeAntecedentCue>[];
    for (final cue in found) {
      // One most recent cue per cast identity keeps competing possibilities
      // visible instead of spamming one character's repeated name.
      if (!used.add(cue.characterId) || !cue.matchesOriginal(source)) {
        continue;
      }
      output.add(cue);
      if (output.length == maxCues) break;
    }
    return NarrativeAntecedentInspection(
      cues: List.unmodifiable(output),
      windowStart: start,
      windowEnd: referenceStart,
    );
  }
}
