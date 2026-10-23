import '../data/book_decoder.dart';
import '../domain/cast_span.dart';
import '../domain/voice_cast.dart';
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

/// Does NOT scan the full book. It visits at most a few already completed
/// earlier scopes and searches a capped tail of each scope for approved cast
/// names/aliases, without uploading a book-wide index.
class HistoricalCharacterConcordance {
  const HistoricalCharacterConcordance();

  static const maxOlderScopes = 6;
  static const maxSearchPerScope = 50000;
  static const maxMentions = 5;
  static const maxMentionsPerPerson = 2;
  static const maxSentCharacters = 550;
  static const maxSnippetCharacters = 130;

  static final RegExp _word = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  bool _letterNextTo(String text, int at, {required bool before}) {
    if (before) {
      if (at <= 0) return false;
      final last = text.codeUnitAt(at - 1);
      final start = last >= 0xDC00 && last <= 0xDFFF && at >= 2
          ? at - 2 : at - 1;
      return _word.hasMatch(text.substring(start, at));
    }
    if (at >= text.length) return false;
    final first = text.codeUnitAt(at);
    final end = first >= 0xD800 && first <= 0xDBFF &&
            at + 1 < text.length
        ? at + 2 : at + 1;
    return _word.hasMatch(text.substring(at, end));
  }

  List<HistoricalCharacterMention> build({
    required String bookId,
    required DocumentContent document,
    required List<DialogueAnalysisScope> scopes,
    required DialogueAnalysisWindow window,
  }) {
    if (bookId != window.bookId || window.cast.isEmpty) return const [];
    final source = document.text;
    final earlier = scopes.where((scope) =>
        scope.id != window.scope.id &&
        scope.start >= 0 &&
        scope.end <= window.scope.start &&
        scope.end <= window.effectiveCeiling &&
        scope.end <= source.length &&
        scope.start < scope.end).toList()
      ..sort((a, b) => b.end.compareTo(a.end));
    final candidates = earlier.take(maxOlderScopes);
    final result = <HistoricalCharacterMention>[];
    final perCharacter = <String, int>{};
    var totalChars = 0;
    for (final scope in candidates) {
      if (result.length >= maxMentions) break;
      final scanStart = (scope.end - maxSearchPerScope)
          .clamp(scope.start, scope.end).toInt();
      for (final person in window.cast) {
        if (person.bookId != bookId ||
            (perCharacter[person.id] ?? 0) >= maxMentionsPerPerson ||
            result.length >= maxMentions) continue;
        final names = <String>{person.name, ...person.aliases};
        ({int start, int end, String name})? latest;
        for (final name in names) {
          if (name.trim().length < 2 || name.length > 120) continue;
          final expression = RegExp(
            RegExp.escape(name), caseSensitive: false, unicode: true,
          );
          for (final match in expression.allMatches(
              source, scanStart)) {
            if (match.start >= scope.end) break;
            if (match.end > scope.end ||
                !CastSpan.validUtf16Range(
                    source, match.start, match.end) ||
                _letterNextTo(source, match.start, before: true) ||
                _letterNextTo(source, match.end, before: false)) continue;
            if (latest == null || match.start > latest.start) {
              latest = (start: match.start, end: match.end, name: name);
            }
          }
        }
        if (latest == null) continue;
        final budget = maxSentCharacters - totalChars;
        if (budget < 20) break;
        var left = (latest.start - 38).clamp(
            scope.start, latest.start).toInt();
        var right = (latest.end + 38).clamp(
            latest.end, scope.end).toInt();
        while (right - left > maxSnippetCharacters ||
            right - left > budget) {
          if (right - latest.end > latest.start - left) {
            right--;
          } else if (left < latest.start) {
            left++;
          } else if (right > latest.end) {
            right--;
          } else {
            break;
          }
        }
        if (right - left > budget) continue;
        // Ensure excerpts never split emoji or supplementary code points.
        if (left > 0 && left < source.length &&
            source.codeUnitAt(left) >= 0xDC00 &&
            source.codeUnitAt(left) <= 0xDFFF) left++;
        if (right < source.length && right > 0 &&
            source.codeUnitAt(right - 1) >= 0xD800 &&
            source.codeUnitAt(right - 1) <= 0xDBFF) right--;
        if (left > latest.start || right < latest.end ||
            !CastSpan.validUtf16Range(source, left, right)) continue;
        final excerpt = source.substring(left, right);
        final mention = HistoricalCharacterMention(
          scopeId: scope.id, scopeStart: scope.start,
          scopeEnd: scope.end, characterId: person.id,
          matchedName: source.substring(latest.start, latest.end),
          mentionStart: latest.start, mentionEnd: latest.end,
          excerptStart: left, excerpt: excerpt,
          sourceDigest: CastSpan.digest(excerpt),
        );
        if (!mention.isValidFor(window) ||
            !mention.matchesOriginal(source)) continue;
        result.add(mention);
        totalChars += excerpt.length;
        perCharacter[person.id] = (perCharacter[person.id] ?? 0) + 1;
      }
    }
    return List.unmodifiable(result);
  }
}
