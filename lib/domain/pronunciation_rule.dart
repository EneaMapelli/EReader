/// Plain-literal substitutions applied to *audio input only*. They never
/// modify displayed book text, source offsets, search results or annotations.
/// A rule belongs to all books (bookId == null) or to one imported book.
class PronunciationRule {
  const PronunciationRule({
    required this.id,
    required this.pattern,
    required this.replacement,
    this.bookId,
    this.wholeWord = true,
    this.caseSensitive = false,
    this.enabled = true,
  });

  final String id;
  final String? bookId;
  final String pattern;
  final String replacement;
  final bool wholeWord;
  final bool caseSensitive;
  final bool enabled;

  void validate() {
    if (id.isEmpty || id.length > 128) {
      throw const FormatException('Invalid pronunciation rule ID');
    }
    if (bookId != null && bookId!.isEmpty) {
      throw const FormatException('Book scope requires a nonempty book ID');
    }
    if (pattern.trim().isEmpty || pattern.length > 100) {
      throw const FormatException('Pronunciation phrase must have 1–100 characters');
    }
    if (replacement.trim().isEmpty || replacement.length > 200) {
      throw const FormatException('Replacement must have 1–200 characters');
    }
    if (pattern.contains('\n') || replacement.contains('\n')) {
      throw const FormatException('Pronunciation rules cannot contain line breaks');
    }
  }
}

/// Collect matches from the ORIGINAL sentence, then apply all changes once.
/// Book-specific rules beat global ones at the same starting position;
/// longest match wins inside one scope. No cascading rules or Regex supplied
/// by users, so substitutions are deterministic and cannot loop.
class PronunciationTransformer {
  const PronunciationTransformer();

  static final RegExp _wordChar =
      RegExp(r'[\p{L}\p{N}_]', unicode: true);

  String apply(
    String original,
    Iterable<PronunciationRule> rules, {
    required String bookId,
  }) {
    final candidates = <_Candidate>[];
    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (rule.bookId != null && rule.bookId != bookId) continue;
      rule.validate();
      final pattern = RegExp(
        RegExp.escape(rule.pattern),
        caseSensitive: rule.caseSensitive,
        unicode: true,
      );
      for (final match in pattern.allMatches(original)) {
        if (rule.wholeWord) {
          final before = match.start > 0
              ? original.substring(0, match.start).runes.last
              : null;
          final after = match.end < original.length
              ? original.substring(match.end).runes.first
              : null;
          // Boundary only applies when the first/last matched code point is
          // a word character; punctuation in phrases stays matchable.
          final matchFirst = rule.pattern.runes.first;
          final matchLast = rule.pattern.runes.last;
          if (before != null &&
              _isWordRune(before) && _isWordRune(matchFirst)) {
            continue;
          }
          if (after != null &&
              _isWordRune(after) && _isWordRune(matchLast)) {
            continue;
          }
        }
        candidates.add(_Candidate(match.start, match.end, rule));
      }
    }

    candidates.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      final aScope = a.rule.bookId == null ? 1 : 0;
      final bScope = b.rule.bookId == null ? 1 : 0;
      if (aScope != bScope) return aScope.compareTo(bScope);
      final byLength = (b.end - b.start).compareTo(a.end - a.start);
      if (byLength != 0) return byLength;
      return a.rule.id.compareTo(b.rule.id);
    });

    final output = StringBuffer();
    var cursor = 0;
    for (final candidate in candidates) {
      if (candidate.start < cursor) continue;
      output.write(original.substring(cursor, candidate.start));
      output.write(candidate.rule.replacement);
      cursor = candidate.end;
    }
    output.write(original.substring(cursor));
    return output.toString();
  }

  static bool _isWordRune(int rune) =>
      _wordChar.hasMatch(String.fromCharCode(rune));
}

class _Candidate {
  const _Candidate(this.start, this.end, this.rule);
  final int start;
  final int end;
  final PronunciationRule rule;
}
