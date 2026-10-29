import 'speech_abbreviation.dart';

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
        if (decimalDot ||
            (ch == 46 && isProtectedSpeechPeriod(
              source, i, start: start, end: end,
            ))) {
          // Keep book titles and author initials inside a single utterance.
          // Source offsets remain untouched; hard maxChars still applies.
          continue;
        }
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
    }

    // A hard input cap must not split a decomposed accent or a common
    // multi-code-point emoji sequence. Backtrack by code points until
    // a safe break; never silently drop a code unit to make progress.
    chunkEnd = backtrackCommonGraphemeBoundary(
        source, start: chunkStart, end: chunkEnd);
    while (chunkEnd > chunkStart &&
        _isWhitespace(source.codeUnitAt(chunkEnd - 1))) {
      chunkEnd--;
    }
    if (chunkEnd <= chunkStart) {
      throw const FormatException(
          'A Unicode text cluster exceeds the TTS chunk limit');
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

/// Return the nearest usable UTF-16 boundary at or before [end] without
/// splitting the common combining sequences supported by this reader.
///
/// The caller must impose its own character budget. Backtracking does not
/// rewrite or drop the underlying source: subsequent chunks restart at the
/// returned index. A single cluster longer than the budget is rejected rather
/// than silently cut into malformed speech/visual chunks.
///
/// This protects common accent and emoji clusters; full Unicode grapheme
/// segmentation (including complex Indic rules) remains a separate goal.
int backtrackCommonGraphemeBoundary(String source, {
  required int start,
  required int end,
}) {
  if (start < 0 || end <= start || end > source.length) {
    throw RangeError('Invalid UTF-16 chunk bounds');
  }
  var boundary = end;
  while (boundary > start && _splitsCommonGrapheme(source, boundary)) {
    boundary -= boundary >= 2 &&
            _isLowSurrogate(source.codeUnitAt(boundary - 1)) &&
            _isHighSurrogate(source.codeUnitAt(boundary - 2))
        ? 2 : 1;
  }
  if (boundary <= start) {
    throw const FormatException('Unicode text cluster exceeds chunk limit');
  }
  return boundary;
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
    c == 0x201C || // “ (closing German „…“ quote)
    c == 0x203A || // › (single guillemet close)
    c == 0x2019 || // ’
    c == 0x0022 || // "
    c == 0x0027 || // '
    c == 0x0029 || // )
    c == 0x005D;   // ]
bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;

// Read only the code point adjacent to a prospective UTF-16 boundary.
// Full grapheme segmentation is intentionally outside this bounded TTS
// chunker; these rules cover frequent decomposed accents/emoji clusters.
int _codePointAt(String text, int index) {
  final first = text.codeUnitAt(index);
  if (_isHighSurrogate(first) && index + 1 < text.length) {
    final second = text.codeUnitAt(index + 1);
    if (_isLowSurrogate(second)) {
      return 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00;
    }
  }
  return first;
}

int _codePointBefore(String text, int index) {
  final last = text.codeUnitAt(index - 1);
  if (_isLowSurrogate(last) && index >= 2) {
    final first = text.codeUnitAt(index - 2);
    if (_isHighSurrogate(first)) {
      return 0x10000 + ((first - 0xD800) << 10) + last - 0xDC00;
    }
  }
  return last;
}

bool _combiningOrModifier(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x1AB0 && c <= 0x1AFF) ||
    (c >= 0x1DC0 && c <= 0x1DFF) ||
    (c >= 0x20D0 && c <= 0x20FF) ||
    (c >= 0xFE20 && c <= 0xFE2F) ||
    (c >= 0xFE00 && c <= 0xFE0F) ||
    (c >= 0x1F3FB && c <= 0x1F3FF) ||
    (c >= 0xE0020 && c <= 0xE007F);

bool _regionalIndicator(int c) => c >= 0x1F1E6 && c <= 0x1F1FF;

bool _splitsCommonGrapheme(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return false;
  final afterUnit = text.codeUnitAt(offset);
  if (_isLowSurrogate(afterUnit) &&
      _isHighSurrogate(text.codeUnitAt(offset - 1))) {
    return true;
  }
  final after = _codePointAt(text, offset);
  final before = _codePointBefore(text, offset);
  if (_combiningOrModifier(after) ||
      after == 0x200D || before == 0x200D) return true;
  if (_regionalIndicator(before) && _regionalIndicator(after)) {
    // Pair regional indicator letters into flag clusters. A boundary
    // after an odd number of consecutive indicators is unsafe.
    var count = 0;
    var cursor = offset;
    while (cursor > 0 && _regionalIndicator(
        _codePointBefore(text, cursor))) {
      count++;
      cursor -= _isLowSurrogate(text.codeUnitAt(cursor - 1)) &&
              cursor >= 2 &&
              _isHighSurrogate(text.codeUnitAt(cursor - 2))
          ? 2 : 1;
    }
    return count.isOdd;
  }
  return false;
}
