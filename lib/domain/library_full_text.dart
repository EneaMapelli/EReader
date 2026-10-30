/// Optional on-device full-text index. Snippets are private excerpts and
/// must never be logged or sent to remote analytics/providers.
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
