/// Search modes use the same explicit, on-device FTS5 index. Phrase mode
/// requires consecutive tokenizer words; it does not claim AI semantics.
enum LibraryFullTextMatchMode { allWords, exactPhrase }

/// Parse at most eight literal Unicode FTS words from a bounded query.
/// Never expose raw user-provided FTS operators to MATCH.
List<String> libraryFullTextTokens(String query) {
  if (query.trim().isEmpty || query.length > 120) return const [];
  final words = RegExp(r'[\p{L}\p{N}]+', unicode: true)
      .allMatches(query).map((match) => match.group(0)!).toList();
  if (words.isEmpty || words.length > 8) return const [];
  return List.unmodifiable(words);
}

/// Only internally generated quoted tokens are passed into SQLite MATCH.
/// Double quotes and punctuation in the input are treated as separators.
String? libraryFullTextMatchExpression(
  String query, {
  LibraryFullTextMatchMode mode = LibraryFullTextMatchMode.allWords,
}) {
  final tokens = libraryFullTextTokens(query);
  if (tokens.isEmpty) return null;
  if (mode == LibraryFullTextMatchMode.exactPhrase) {
    return '"${tokens.join(' ')}"';
  }
  return tokens.map((token) => '"$token"').join(' AND ');
}

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
    this.contextBefore = '',
    this.contextAfter = '',
  });

  final int sourceOffset;
  final String expectedText;
  /// Limited surrounding source captured at selection time, not persisted.
  /// Checking context avoids pointing to an unrelated same-named word after
  /// edits in another chapter or extractor normalization.
  final String contextBefore;
  final String contextAfter;

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
    if (actual.toLowerCase() != expectedText.toLowerCase()) return null;
    if (contextBefore.length > 64 || contextAfter.length > 2112 ||
        sourceOffset < contextBefore.length ||
        sourceOffset + expectedText.length + contextAfter.length >
            source.length) {
      return null;
    }
    if (contextBefore.isNotEmpty &&
        source.substring(sourceOffset - contextBefore.length,
            sourceOffset) != contextBefore) {
      return null;
    }
    final afterStart = sourceOffset + expectedText.length;
    if (contextAfter.isNotEmpty &&
        source.substring(afterStart, afterStart + contextAfter.length) !=
            contextAfter) {
      return null;
    }
    return sourceOffset;
  }
}

/// Capture a bounded context around one selected occurrence. For
/// proximity-matched multiword searches, include the entire selected window
/// in the suffix so changing another query term rejects the old location.
LibraryFullTextJump _captureIndexedWord(
  String source,
  RegExpMatch word, {
  int? passageEnd,
}) {
  final before = (word.start - 32).clamp(0, source.length).toInt();
  final desiredEnd = ((passageEnd ?? word.end) + 32)
      .clamp(word.end, source.length).toInt();
  return LibraryFullTextJump(
    sourceOffset: word.start,
    expectedText: word.group(0)!,
    contextBefore: source.substring(before, word.start),
    contextAfter: source.substring(word.end, desiredEnd),
  );
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
      return _captureIndexedWord(indexedSource, match);
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
  int? bestEnd;
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
      bestEnd = match.end;
      // Can't beat the total number of distinct nonempty words.
      // Do not stop early: the next phrase may have the same span but
      // is only accepted if it is strictly shorter (earliest wins).
    }
  }
  if (bestStart != null) {
    return _captureIndexedWord(
      indexedSource, bestStart, passageEnd: bestEnd);
  }
  return firstExactIndexedWord(indexedSource, queryTokens.first);
}

/// An explicitly selected, source-exact search passage with a bounded
/// display preview. Neither the preview nor the jump changes stored progress.
class LibraryFullTextPassage {
  const LibraryFullTextPassage({
    required this.jump,
    required this.excerpt,
    required this.allTermsNearby,
  });

  final LibraryFullTextJump jump;
  final String excerpt;
  /// False means the terms match only across distant parts of this book.
  final bool allTermsNearby;
}

class _IndexedPassageCandidate {
  const _IndexedPassageCandidate(this.start, this.end, this.anchor);
  final int start;
  final int end;
  final RegExpMatch anchor;
  int get width => end - start;
}

/// Return a bounded list of *distinct* local passages for one book only.
/// All-term spans are ranked by tightness, then source order. Overlapping
/// windows collapse to one representative instead of showing near-duplicates.
/// A distant match only yields one clearly labelled fallback occurrence.
/// Scanning is linear in source length with O(query terms + limit) retention.
List<LibraryFullTextPassage> findIndexedPassages(
  String indexedSource,
  List<String> queryTokens, {
  int limit = 6,
  int maxSpanChars = 320,
  int contextChars = 65,
}) {
  if (limit < 1 || limit > 10 || maxSpanChars < 1 ||
      maxSpanChars > 2048 || contextChars < 0 ||
      contextChars > 160 || queryTokens.isEmpty ||
      queryTokens.length > 8) {
    return const [];
  }
  final targets = <String>{};
  for (final token in queryTokens) {
    if (token.isEmpty || token.length > 120) return const [];
    targets.add(token.toLowerCase());
  }
  final latest = <String, RegExpMatch>{};
  final chosen = <_IndexedPassageCandidate>[];
  final words = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);

  int compare(_IndexedPassageCandidate a, _IndexedPassageCandidate b) {
    final width = a.width.compareTo(b.width);
    return width != 0 ? width : a.start.compareTo(b.start);
  }

  for (final match in words.allMatches(indexedSource)) {
    final token = match.group(0)!.toLowerCase();
    if (!targets.contains(token)) continue;
    latest[token] = match;
    if (latest.length != targets.length) continue;

    var earliest = match;
    for (final entry in latest.values) {
      if (entry.start < earliest.start) earliest = entry;
    }
    final candidate = _IndexedPassageCandidate(
        earliest.start, match.end, earliest);
    if (candidate.width > maxSpanChars) continue;

    // Merge a cluster of close competing windows to avoid repeats.
    final overlaps = <_IndexedPassageCandidate>[];
    for (final existing in chosen) {
      // Near-adjacent windows usually describe the same paragraph, even
      // when their exact term spans do not overlap.
      if (targets.length > 1 &&
          candidate.start <= existing.end + 72 &&
          existing.start <= candidate.end + 72) {
        overlaps.add(existing);
      }
    }
    if (overlaps.isNotEmpty) {
      final best = ([candidate, ...overlaps]..sort(compare)).first;
      chosen.removeWhere(overlaps.contains);
      chosen.add(best);
    } else {
      chosen.add(candidate);
    }
    chosen.sort(compare);
    if (chosen.length > limit) chosen.removeLast();
  }

  // A book-wide AND match may have no passage containing all the terms
  // nearby. Show one conservative fallback, not a fabricated phrase.
  if (chosen.isEmpty) {
    final fallback = firstExactIndexedWord(indexedSource, queryTokens.first);
    if (fallback == null) return const [];
    return [
      LibraryFullTextPassage(
        jump: fallback,
        excerpt: _indexedPassageExcerpt(indexedSource,
            fallback.sourceOffset,
            fallback.sourceOffset + fallback.expectedText.length,
            contextChars),
        allTermsNearby: false,
      ),
    ];
  }

  return List.unmodifiable([
    for (final candidate in chosen)
      LibraryFullTextPassage(
        jump: _captureIndexedWord(indexedSource, candidate.anchor,
            passageEnd: candidate.end),
        excerpt: _indexedPassageExcerpt(indexedSource,
            candidate.start, candidate.end, contextChars),
        allTermsNearby: true,
      ),
  ]);
}

/// Positions of genuinely consecutive query tokens in the indexed
/// canonical source. SQLite FTS phrase matching is the book-level filter;
/// this local pass supplies verified UTF-16 destinations, independent of
/// SQLite's UTF-8 byte offsets. Bounded rolling window (max 8 tokens),
/// bounded result list, no content saved or sent to an external service.
List<LibraryFullTextPassage> findIndexedExactPhrases(
  String indexedSource,
  List<String> queryTokens, {
  int limit = 6,
  int maxSpanChars = 320,
  int contextChars = 65,
}) {
  if (limit < 1 || limit > 10 || maxSpanChars < 1 ||
      maxSpanChars > 2048 || contextChars < 0 || contextChars > 160 ||
      queryTokens.isEmpty || queryTokens.length > 8 ||
      queryTokens.any((token) => token.isEmpty || token.length > 120)) {
    return const [];
  }
  final targets = queryTokens.map((word) => word.toLowerCase()).toList();
  final window = <RegExpMatch>[];
  final results = <LibraryFullTextPassage>[];
  final words = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);
  for (final match in words.allMatches(indexedSource)) {
    window.add(match);
    if (window.length > targets.length) window.removeAt(0);
    if (window.length != targets.length) continue;
    var matches = true;
    for (var i = 0; i < targets.length; i++) {
      if (window[i].group(0)!.toLowerCase() != targets[i]) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    final first = window.first;
    final end = window.last.end;
    if (end - first.start > maxSpanChars) continue;
    results.add(LibraryFullTextPassage(
      jump: _captureIndexedWord(
        indexedSource, first, passageEnd: end),
      excerpt: _indexedPassageExcerpt(
        indexedSource, first.start, end, contextChars),
      allTermsNearby: true,
    ));
    if (results.length >= limit) break;
  }
  return List.unmodifiable(results);
}

/// A display-only excerpt; avoid splitting a surrogate pair at a boundary.
String _indexedPassageExcerpt(
    String source, int start, int end, int contextChars) {
  var left = (start - contextChars).clamp(0, source.length).toInt();
  var right = (end + contextChars).clamp(0, source.length).toInt();
  if (left > 0 && left < source.length &&
      source.codeUnitAt(left) >= 0xDC00 &&
      source.codeUnitAt(left) <= 0xDFFF) left--;
  if (right > 0 && right < source.length &&
      source.codeUnitAt(right) >= 0xDC00 &&
      source.codeUnitAt(right) <= 0xDFFF) right++;
  return source.substring(left, right)
      .replaceAll(RegExp(r'\s+'), ' ').trim();
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
