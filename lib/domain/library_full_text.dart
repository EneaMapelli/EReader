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
