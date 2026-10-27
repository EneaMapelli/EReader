/// Shared punctuation context used by both source-exact chunking and the
/// Windows-only spoken-phrase planner. Never changes text or UTF-16 anchors.
///
/// This is a conservative *name* heuristic, not a general abbreviation,
/// dictionary or pronunciation engine. A period inside a recognized title
/// followed by a capitalized name, an author initial, or a dotted uppercase
/// acronym is not treated as a full sentence stop. A true sentence period
/// still ends a chunk. When the TTS hard cap intervenes, chunking may still
/// break a phrase at a whitespace boundary for safety.
///
/// The scan is bounded around each period, even in a very large EPUB.
final RegExp _speechLetter = RegExp(r'^\p{L}$', unicode: true);
final RegExp _speechUpper = RegExp(r'^\p{Lu}$', unicode: true);
final RegExp _followingProperName =
    RegExp(r'^[ \t]+(\p{Lu}[\p{L}\p{M}]*)', unicode: true);

const Set<String> _nameTitles = {
  'sig', 'sigg', 'dott', 'dottssa', 'dr', 'mr', 'mrs', 'ms',
  'prof', 'ing', 'avv', 'arch', 'geom',
};

/// [start] and [end] restrict inspection to the supplied source chapter.
/// No lookahead is allowed outside a visual/structural source range.
bool isProtectedSpeechPeriod(
  String source,
  int offset, {
  int start = 0,
  int? end,
}) {
  final right = end ?? source.length;
  if (start < 0 || right > source.length || right < start) {
    throw RangeError('Invalid speech punctuation source range');
  }
  if (offset <= start || offset >= right ||
      source.codeUnitAt(offset) != 0x2E) {
    return false;
  }

  // Internal acronym dots: U.S.A. (the final dot remains a normal
  // sentence stop unless followed by a recognized capitalized name).
  if (offset + 1 < right &&
      _speechUpper.hasMatch(source.substring(offset - 1, offset)) &&
      _speechUpper.hasMatch(source.substring(offset + 1, offset + 2))) {
    return true;
  }

  // Match ONLY spaces/tabs followed by a capitalized word. Do not carry a
  // title across a paragraph break or scan the rest of a megabyte chapter.
  final windowEnd = offset + 82 < right ? offset + 82 : right;
  final following = _followingProperName.firstMatch(
    source.substring(offset + 1, windowEnd),
  );
  if (following == null) return false;

  // Scan a bounded prefix ending just before the dot, and require a word
  // boundary. Avoid treating the suffix of a huge token as an abbreviation.
  var beginning = offset;
  while (beginning > start && offset - beginning < 24 &&
      _speechLetter.hasMatch(source.substring(beginning - 1, beginning))) {
    beginning--;
  }
  if (beginning == offset ||
      (beginning > start &&
          _speechLetter.hasMatch(source.substring(beginning - 1, beginning)))) {
    return false;
  }
  final prefix = source.substring(beginning, offset);
  return _nameTitles.contains(prefix.toLowerCase()) ||
      (prefix.length == 1 && _speechUpper.hasMatch(prefix));
}
