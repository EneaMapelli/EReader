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

class LibraryFullTextHit {
  const LibraryFullTextHit({
    required this.bookId,
    required this.title,
    required this.excerpt,
    this.jump,
  });

  final String bookId;
  final String title;
  final String excerpt;
  /// Null when the FTS tokenizer matched but a source-exact UTF-16
  /// destination could not be verified in the indexed text.
  final LibraryFullTextJump? jump;
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
