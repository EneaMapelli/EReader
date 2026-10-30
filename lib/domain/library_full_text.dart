/// Optional on-device full-text index. Snippets are private excerpts and
/// must never be logged or sent to remote analytics/providers.
///
/// The offset belongs to the SAME canonical extracted UTF-16 string used by
/// the reader; it is not a PDF visual coordinate or an EPUB file byte offset.
/// Always validate against freshly decoded text before navigating. No state
/// mutation or audio playback is permitted by a search result alone.
class LibraryFullTextJump {
  const LibraryFullTextJump({
    required this.sourceOffset,
    required this.expectedText,
  });

  final int sourceOffset;
  final String expectedText;

  int? validatedOffset(String source) {
    if (expectedText.isEmpty || expectedText.length > 120 ||
        sourceOffset < 0 ||
        sourceOffset + expectedText.length > source.length) {
      return null;
    }
    // Case-only changes are harmless; source normalization/rewrites are not.
    // Checking exact UTF-16 span also prevents stale data from pointing to
    // an unrelated paragraph after EPUB/PDF extractor changes.
    final actual = source.substring(
        sourceOffset, sourceOffset + expectedText.length);
    return actual.toLowerCase() == expectedText.toLowerCase()
        ? sourceOffset : null;
  }
}

/// Find the first COMPLETE Unicode word matching an FTS token.
/// Searching the indexed canonical text, rather than an FTS5 byte offset,
/// preserves Dart's UTF-16 source indices even after surrogate pairs.
/// Return null for token normalization differences rather than navigating
/// to a substring inside an unrelated word.
LibraryFullTextJump? firstExactIndexedWord(
    String indexedSource, String queryToken) {
  if (queryToken.isEmpty || queryToken.length > 120) return null;
  final target = queryToken.toLowerCase();
  final words = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);
  for (final match in words.allMatches(indexedSource)) {
    final word = match.group(0)!;
    if (word.toLowerCase() == target) {
      return LibraryFullTextJump(
        sourceOffset: match.start,
        expectedText: word,
      );
    }
  }
  return null;
}

/// Choose the shortest nearby passage containing ALL distinct query words.
/// This scan runs only after the user selects a hit, never in query rebuilds.
/// It uses O(number of query terms) state even on large/repetitive books.
///
/// If FTS5 matched the words somewhere in the book but no close passage
/// exists, keep the conservative first-word fallback instead of presenting
/// distant unrelated passages as one sentence. Unicode offsets are UTF-16.
LibraryFullTextJump? bestIndexedPassage(
  String indexedSource,
  List<String> queryTokens, {
  int maxSpanChars = 320,
}) {
  if (queryTokens.isEmpty || queryTokens.length > 8 ||
      maxSpanChars < 1 || maxSpanChars > 2048) return null;
  final targets = <String>{};
  for (final token in queryTokens) {
    if (token.isEmpty || token.length > 120) return null;
    targets.add(token.toLowerCase());
  }
  if (targets.isEmpty) return null;
  if (targets.length == 1) {
    return firstExactIndexedWord(indexedSource, queryTokens.first);
  }

  // Store ONLY the most recent occurrence of each query term, never all
  // text matches. For every new occurrence, these latest positions give
  // the smallest candidate interval ending at that occurrence.
  final recent = <String, RegExpMatch>{};
  RegExpMatch? bestStart;
  var bestWidth = maxSpanChars + 1;
  final words = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);
  for (final match in words.allMatches(indexedSource)) {
    final token = match.group(0)!.toLowerCase();
    if (!targets.contains(token)) continue;
    recent[token] = match;
    if (recent.length != targets.length) continue;
    var earliest = match;
    for (final occurrence in recent.values) {
      if (occurrence.start < earliest.start) earliest = occurrence;
    }
    final width = match.end - earliest.start;
    if (width <= maxSpanChars && width < bestWidth) {
      bestWidth = width;
      bestStart = earliest;
      // Can't beat the total number of distinct nonempty words.
      // Do not stop early: the next phrase may have the same span but
      // is only accepted if it is strictly shorter (earliest wins).
    }
  }
  if (bestStart != null) {
    return LibraryFullTextJump(
      sourceOffset: bestStart.start,
      expectedText: bestStart.group(0)!,
    );
  }
  return firstExactIndexedWord(indexedSource, queryTokens.first);
}

class LibraryFullTextHit {
  const LibraryFullTextHit({
    required this.bookId,
    required this.title,
    required this.excerpt,
  });

  final String bookId;
  final String title;
  final String excerpt;
}

class LibraryFullTextIndexReport {
  const LibraryFullTextIndexReport({
    required this.processed,
    required this.indexed,
    required this.skipped,
    required this.remaining,
    required this.cancelled,
  });

  final int processed;
  final int indexed;
  final int skipped;
  final int remaining;
  final bool cancelled;
}
