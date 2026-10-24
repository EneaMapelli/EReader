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
List<SpeechSegment> segmentSpeech(String source, {int maxChars = 400}) {
  if (maxChars < 16) throw ArgumentError.value(maxChars, 'maxChars');
  final result = <SpeechSegment>[];
  var cursor = 0;

  while (cursor < source.length) {
    while (cursor < source.length && _isWhitespace(source.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= source.length) break;

    final start = cursor;
    final limit = (start + maxChars < source.length)
        ? start + maxChars
        : source.length;
    var end = limit;
    var firstSentenceEnd = -1;
    var lastWhitespace = -1;

    for (var i = start; i < limit; i++) {
      final ch = source.codeUnitAt(i);
      if (_isWhitespace(ch)) {
        lastWhitespace = i;
        if (ch == 10 || ch == 13) {
          firstSentenceEnd = i; // newline is a natural paragraph boundary
          break;
        }
      }
      if (_isPunctuation(ch)) {
        // A dot inside a decimal number is not the end of a sentence.
        final decimalDot = ch == 46 &&
            i > start &&
            i + 1 < source.length &&
            _isDigit(source.codeUnitAt(i - 1)) &&
            _isDigit(source.codeUnitAt(i + 1));
        if (decimalDot) continue;
        final next = i + 1;
        if (next >= source.length ||
            _isWhitespace(source.codeUnitAt(next))) {
          firstSentenceEnd = next;
          break;
        }
      }
    }

    if (firstSentenceEnd > start) {
      end = firstSentenceEnd;
    } else if (limit < source.length && lastWhitespace > start) {
      end = lastWhitespace;
    } else if (limit < source.length &&
        _isLowSurrogate(source.codeUnitAt(limit)) &&
        _isHighSurrogate(source.codeUnitAt(limit - 1))) {
      end = limit - 1;
    }

    // Only whitespace can be trimmed; speech content must be verbatim.
    while (end > start &&
        _isWhitespace(source.codeUnitAt(end - 1))) {
      end--;
    }
    if (end <= start) {
      // Guard against pathological runs of paragraph delimiters.
      cursor = limit;
      continue;
    }

    result.add(SpeechSegment(
      start,
      end,
      source.substring(start, end),
    ));
    cursor = end;
  }
  return result;
}

bool _isWhitespace(int c) =>
    c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0;
bool _isPunctuation(int c) => c == 46 || c == 33 ||
    c == 63 || c == 0x2026;
bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;
