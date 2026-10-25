/// Spoken chunks retain offsets into the original source text.
/// Offsets are UTF-16 code-unit indices (as used by Dart String).
class SpeechSegment {
  const SpeechSegment(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// Deterministic, bounded splitting for native and cloud speech.
///
/// Prefer the first complete sentence inside the available chunk; otherwise
/// split at a word boundary if the chunk is too long. Every spoken substring
/// is sourced from the unmodified document and never crosses surrogate pairs.
/// Whitespace between chunks is skipped rather than sent to the speech API.
List<SpeechSegment> segmentSpeech(String source, {int maxChars = 400}) =>
    segmentSpeechRange(source,
        start: 0, end: source.length, maxChars: maxChars);

/// Segment a slice of the original String without copying the whole
/// chapter first. Returned spans use GLOBAL UTF-16 offsets, the same as
/// bookmarks, cast annotations and cloud speech playback. This is crucial
/// when reading multi-megabyte EPUB spine documents.
List<SpeechSegment> segmentSpeechRange(
  String source, {
  required int start,
  required int end,
  int maxChars = 400,
}) {
  if (maxChars < 16) throw ArgumentError.value(maxChars, 'maxChars');
  if (start < 0 || end < start || end > source.length) {
    throw RangeError('Invalid speech source range');
  }
  if ((start > 0 && start < source.length &&
          _isLowSurrogate(source.codeUnitAt(start)) &&
          _isHighSurrogate(source.codeUnitAt(start - 1))) ||
      (end > 0 && end < source.length &&
          _isLowSurrogate(source.codeUnitAt(end)) &&
          _isHighSurrogate(source.codeUnitAt(end - 1)))) {
    throw const FormatException('Speech range splits a UTF-16 character');
  }
  final result = <SpeechSegment>[];
  var cursor = start;

  while (cursor < end) {
    while (cursor < end && _isWhitespace(source.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= end) break;

    final chunkStart = cursor;
    final limit = (chunkStart + maxChars < end)
        ? chunkStart + maxChars
        : end;
    var chunkEnd = limit;
    var firstSentenceEnd = -1;
    var lastWhitespace = -1;

    for (var i = chunkStart; i < limit; i++) {
      final ch = source.codeUnitAt(i);
      if (_isWhitespace(ch)) {
        lastWhitespace = i;
        if (ch == 10 || ch == 13) {
          firstSentenceEnd = i;
          break;
        }
      }
      if (_isPunctuation(ch)) {
        final decimalDot = ch == 46 &&
            i > chunkStart &&
            i + 1 < end &&
            _isDigit(source.codeUnitAt(i - 1)) &&
            _isDigit(source.codeUnitAt(i + 1));
        if (decimalDot) continue;
        // A sentence-final mark is often enclosed by closing quotes
        // or brackets in novels: «Hello!» Next speaker. Consume those
        // closers as part of the SAME spoken sentence, but never step
        // beyond maxChars or cut a surrogate pair.
        var next = i + 1;
        while (next < limit &&
            _isSentenceClosingDelimiter(source.codeUnitAt(next))) {
          next++;
        }
        if (next >= end || _isWhitespace(source.codeUnitAt(next))) {
          firstSentenceEnd = next;
          break;
        }
      }
    }

    if (firstSentenceEnd > chunkStart) {
      chunkEnd = firstSentenceEnd;
    } else if (limit < end && lastWhitespace > chunkStart) {
      chunkEnd = lastWhitespace;
    } else if (limit < end &&
        _isLowSurrogate(source.codeUnitAt(limit)) &&
        _isHighSurrogate(source.codeUnitAt(limit - 1))) {
      chunkEnd = limit - 1;
    }

    while (chunkEnd > chunkStart &&
        _isWhitespace(source.codeUnitAt(chunkEnd - 1))) {
      chunkEnd--;
    }
    if (chunkEnd <= chunkStart) {
      cursor = limit;
      continue;
    }
    result.add(SpeechSegment(
      chunkStart,
      chunkEnd,
      source.substring(chunkStart, chunkEnd),
    ));
    cursor = chunkEnd;
  }
  return result;
}

bool _isWhitespace(int c) =>
    c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0;
bool _isPunctuation(int c) => c == 46 || c == 33 ||
    c == 63 || c == 0x2026;
// Common quotation and parenthetical closing marks only. Apostrophes
// within words are unaffected: this is used solely AFTER punctuation.
bool _isSentenceClosingDelimiter(int c) =>
    c == 0x00BB || // »
    c == 0x201D || // ”
    c == 0x2019 || // ’
    c == 0x0022 || // "
    c == 0x0027 || // '
    c == 0x0029 || // )
    c == 0x005D;   // ]
bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;
