import 'speech_segment.dart';

/// Refines speech segments around explicitly quoted dialogue.
/// Does NOT infer who speaks, dialogue confidence or sentence semantics.
/// It handles common «…», “…” and "…" delimiters, including quotes that
/// span multiple existing segments. Nested/mismatched quotes need review.
///
/// Every new span is an unchanged substring of the original text.
List<SpeechSegment> splitQuotedSegments(List<SpeechSegment> original) {
  final result = <SpeechSegment>[];
  int? expectedClose;

  for (final segment in original) {
    final text = segment.text;
    var start = 0;
    void add(int from, int until) {
      while (from < until && _isWhitespace(text.codeUnitAt(from))) {
        from++;
      }
      while (until > from && _isWhitespace(text.codeUnitAt(until - 1))) {
        until--;
      }
      if (until <= from) return;
      result.add(SpeechSegment(
        segment.start + from,
        segment.start + until,
        text.substring(from, until),
      ));
    }

    for (var i = 0; i < text.length; i++) {
      final character = text.codeUnitAt(i);
      if (expectedClose == null) {
        final close = _closerFor(character);
        if (close == null) continue;
        add(start, i); // narration before the opening quote
        start = i; // keep opening quote in the spoken passage
        expectedClose = close;
      } else if (character == expectedClose) {
        add(start, i + 1); // closing quote stays with the dialogue
        start = i + 1; // following narrator text remains separate
        expectedClose = null;
      }
    }
    add(start, text.length);
  }
  return result;
}

int? _closerFor(int unit) {
  switch (unit) {
    case 0x00ab: return 0x00bb; // « »
    case 0x201c: return 0x201d; // “ ”
    case 0x0022: return 0x0022; // " "
    default: return null;
  }
}

bool _isWhitespace(int ch) =>
    ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 0xa0;
