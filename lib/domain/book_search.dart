import 'speech_segment.dart';

/// Plain-text, offline search over visible speech segments.
/// Returns zero-based segment indices; no content leaves the device.
List<int> findMatchingSegments(
  List<SpeechSegment> segments,
  String query, {
  int maxResults = 100,
}) {
  if (maxResults < 1) throw ArgumentError.value(maxResults, 'maxResults');
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final result = <int>[];
  for (var index = 0; index < segments.length; index++) {
    if (segments[index].text.toLowerCase().contains(needle)) {
      result.add(index);
      if (result.length >= maxResults) break;
    }
  }
  return result;
}

/// A hit in the canonical book source, measured in UTF-16 code units.
/// [excerpt] is for display only, not an alternative audio segment.
class BookSourceMatch {
  const BookSourceMatch(this.start, this.end, this.excerpt);

  final int start;
  final int end;
  final String excerpt;
}

/// Search ALL extracted text, including EPUB captions and other unspoken
/// paragraphs. Results preserve original UTF-16 offsets without rebuilding
/// speech segments, using an escaped case-insensitive regular expression
/// rather than lowercasing the source (which can change Unicode length).
///
/// Results start at [startOffset], then wrap once to the beginning of the book.
/// This avoids returning only the first 100 occurrences in a long EPUB when
/// the reader is currently near the end. No index or hidden full-text cache
/// is persisted. This is local-only: no remote API or book-content upload.
List<BookSourceMatch> findSourceTextMatches(
  String source,
  String query, {
  int maxResults = 100,
  int contextChars = 60,
  int startOffset = 0,
}) {
  if (maxResults < 1) throw ArgumentError.value(maxResults, 'maxResults');
  if (startOffset < 0 || startOffset > source.length) {
    throw ArgumentError.value(startOffset, 'startOffset');
  }
  if (contextChars < 0 || contextChars > 512) {
    throw ArgumentError.value(contextChars, 'contextChars');
  }
  final needle = query.trim();
  if (needle.isEmpty || needle.length > 120 || source.isEmpty) {
    return const [];
  }
  final pattern = RegExp(RegExp.escape(needle), caseSensitive: false,
      unicode: true);
  final results = <BookSourceMatch>[];
  // Never hand RegExp a cursor in the middle of an emoji surrogate pair.
  var cursor = startOffset;
  if (cursor > 0 && cursor < source.length &&
      _sourceLowSurrogate(source.codeUnitAt(cursor)) &&
      _sourceHighSurrogate(source.codeUnitAt(cursor - 1))) {
    cursor--;
  }

  void appendHit(RegExpMatch hit) {
    var start = hit.start - contextChars;
    if (start < 0) start = 0;
    var end = hit.end + contextChars;
    if (end > source.length) end = source.length;
    // A display excerpt must also never split a UTF-16 surrogate pair.
    if (start > 0 && start < source.length &&
        _sourceLowSurrogate(source.codeUnitAt(start)) &&
        _sourceHighSurrogate(source.codeUnitAt(start - 1))) start--;
    if (end > 0 && end < source.length &&
        _sourceLowSurrogate(source.codeUnitAt(end)) &&
        _sourceHighSurrogate(source.codeUnitAt(end - 1))) end++;
    final excerpt = source.substring(start, end)
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    results.add(BookSourceMatch(hit.start, hit.end, excerpt));
  }

  for (final hit in pattern.allMatches(source, cursor)) {
    appendHit(hit);
    if (results.length >= maxResults) return List.unmodifiable(results);
  }
  if (cursor > 0) {
    for (final hit in pattern.allMatches(source)) {
      if (hit.start >= cursor) break;
      appendHit(hit);
      if (results.length >= maxResults) break;
    }
  }
  return List.unmodifiable(results);
}

bool _sourceHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _sourceLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
