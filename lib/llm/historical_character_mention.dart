import '../domain/cast_span.dart';
import 'dialogue_analysis_plan.dart';

/// Source-verified, earlier-chapter mention of a character explicitly chosen
/// by the user. Never an inferred speaker assignment or a new identity.
class HistoricalCharacterMention {
  const HistoricalCharacterMention({
    required this.scopeId,
    required this.scopeStart,
    required this.scopeEnd,
    required this.characterId,
    required this.matchedName,
    required this.mentionStart,
    required this.mentionEnd,
    required this.excerptStart,
    required this.excerpt,
    required this.sourceDigest,
  });

  final String scopeId;
  final int scopeStart;
  final int scopeEnd;
  final String characterId;
  final String matchedName;
  final int mentionStart;
  final int mentionEnd;
  final int excerptStart;
  final String excerpt;
  final String sourceDigest;

  int get excerptEnd => excerptStart + excerpt.length;

  /// Defense in depth: never accept a fabricated historical "preview" that
  /// points into the analyzed chapter or past the spoiler ceiling.
  bool isValidFor(DialogueAnalysisWindow window) {
    if (scopeId.isEmpty || scopeId == window.scope.id ||
        characterId.isEmpty || matchedName.isEmpty ||
        !window.cast.any((member) => member.id == characterId) ||
        scopeStart < 0 || scopeEnd <= scopeStart ||
        scopeEnd > window.scope.start ||
        excerptStart < scopeStart || excerptEnd > scopeEnd ||
        excerptEnd > window.effectiveCeiling ||
        mentionStart < excerptStart || mentionEnd > excerptEnd ||
        mentionEnd <= mentionStart ||
        !CastSpan.validUtf16Range(
            excerpt, mentionStart - excerptStart, mentionEnd - excerptStart) ||
        CastSpan.digest(excerpt) != sourceDigest) return false;
    final actual = excerpt.substring(
      mentionStart - excerptStart, mentionEnd - excerptStart,
    );
    return actual.toLowerCase() == matchedName.toLowerCase();
  }

  bool matchesOriginal(String source) =>
      CastSpan.validUtf16Range(source, excerptStart, excerptEnd) &&
      source.substring(excerptStart, excerptEnd) == excerpt &&
      CastSpan.digest(excerpt) == sourceDigest;
}

