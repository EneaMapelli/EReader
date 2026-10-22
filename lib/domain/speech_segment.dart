/// Spoken chunks keep offsets into the original extracted text.
/// String offsets are UTF-16 code-unit indices (matching Dart String APIs).
class SpeechSegment {
  const SpeechSegment(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// Produces chunks without reordering/rewriting non-whitespace characters.
/// Leading/trailing whitespace between chunks is intentionally unspoken.
/// The source text remains the authority for navigation and display.
List<SpeechSegment> segmentSpeech(String source, {int maxChars = 400}) {
  if (maxChars < 16) throw ArgumentError.value(maxChars, 'maxChars');
  final segments = <SpeechSegment>[];
  int cursor = 0;

  while (cursor < source.length) {
    while (cursor < source.length && _isWhitespace(source.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= source.length) break;

    final start = cursor;
    int end = (start + maxChars < source.length)
        ? start + maxChars
        : source.length;

    if (end < source.length) {
      // Prefer finishing a sentence, falling back to a word boundary.
      int sentenceEnd = -1;
      int wordEnd = -1;
      for (int i = start; i < end; i++) {
        final u = source.codeUnitAt(i);
        if (u == 46 || u == 33 || u == 63 || u == 10 || u == 0x2026) {
          sentenceEnd = i + 1;
        }
        if (_isWhitespace(u)) wordEnd = i;
      }
      if (sentenceEnd > start) {
        end = sentenceEnd;
      } else if (wordEnd > start) {
        end = wordEnd;
      } else {
        // Avoid splitting UTF-16 surrogate pairs at a hard boundary.
        if (end < source.length &&
            _isLowSurrogate(source.codeUnitAt(end)) &&
            _isHighSurrogate(source.codeUnitAt(end - 1))) {
          end--;
        }
      }
    }

    int spokenEnd = end;
    while (spokenEnd > start &&
        _isWhitespace(source.codeUnitAt(spokenEnd - 1))) {
      spokenEnd--;
    }
    if (spokenEnd > start) {
      segments.add(SpeechSegment(
        start,
        spokenEnd,
        source.substring(start, spokenEnd),
      ));
    }
    cursor = end;
  }
  return segments;
}

bool _isWhitespace(int u) =>
    u == 32 || u == 9 || u == 10 || u == 13 || u == 0xA0;
bool _isHighSurrogate(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLowSurrogate(int u) => u >= 0xDC00 && u <= 0xDFFF;
