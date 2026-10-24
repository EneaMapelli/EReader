import 'cast_span.dart';
import 'speech_segment.dart';

/// A source chunk and the quoted *turn* it belongs to, if any.
/// Matching groups stay stable across underlying segmentSpeech boundaries.
class QuotedSpeechChunk {
  const QuotedSpeechChunk(this.segment, this.quoteGroup);

  final SpeechSegment segment;
  final int? quoteGroup;
}

/// Splits source-aligned chunks around common quote marks without guessing
/// speakers or rewriting book text. Carries open-quote state across chunks.
/// Unbalanced/nested quotations are deliberately not auto-attributed.
List<QuotedSpeechChunk> splitQuotedSegmentsWithRegions(
    List<SpeechSegment> original) {
  final result = <QuotedSpeechChunk>[];
  int? expectedClose;
  int? openGroup;
  var nextGroup = 0;

  for (final segment in original) {
    final text = segment.text;
    var start = 0;
    void add(int from, int until, int? group) {
      while (from < until && _isWhitespace(text.codeUnitAt(from))) {
        from++;
      }
      while (until > from && _isWhitespace(text.codeUnitAt(until - 1))) {
        until--;
      }
      if (until <= from) return;
      result.add(QuotedSpeechChunk(SpeechSegment(
        segment.start + from,
        segment.start + until,
        text.substring(from, until),
      ), group));
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (expectedClose == null) {
        final close = _closerFor(ch);
        if (close == null) continue;
        add(start, i, null);
        start = i;
        expectedClose = close;
        openGroup = nextGroup++;
      } else if (ch == expectedClose) {
        add(start, i + 1, openGroup);
        start = i + 1;
        expectedClose = null;
        openGroup = null;
      }
    }
    add(start, text.length, openGroup);
  }
  return List.unmodifiable(result);
}

/// Backwards compatible source-exact segmentation API for reader search/UI.
List<SpeechSegment> splitQuotedSegments(List<SpeechSegment> original) =>
    List.unmodifiable([
      for (final part in splitQuotedSegmentsWithRegions(original)) part.segment,
    ]);

/// Coalesce tiny TTS fragments WITHIN THE SAME quoted turn and voice only.
/// This reduces synthesis hand-offs caused by sentence and chunk boundaries.
/// Never crosses a quote/narrator boundary, an explicit speaker/unknown mask,
/// a non-whitespace source gap, or the provider input character cap.
/// Does not eliminate provider-imposed pauses or promise seamless audio.
PreparedCastSpeech coalesceQuotedSpeech({
  required String source,
  required List<SpeechSegment> chunks,
  required List<QuotedSpeechChunk> quotedChunks,
  required Map<int, String?> speakerByStart,
  int maxChars = 400,
  List<int> hardBoundaries = const [],
}) {
  if (maxChars < 16) throw ArgumentError.value(maxChars, 'maxChars');
  final merged = <SpeechSegment>[];
  final labels = <int, String?>{};
  final sortedBoundaries = hardBoundaries.toList()..sort();
  var quoteIndex = 0;
  int? lastGroup;
  bool lastHadLabel = false;
  String? lastSpeaker;
  for (final chunk in chunks) {
    if (!CastSpan.validUtf16Range(source, chunk.start, chunk.end) ||
        source.substring(chunk.start, chunk.end) != chunk.text) {
      throw const FormatException('Speech chunk is not source-aligned');
    }
    while (quoteIndex < quotedChunks.length &&
        quotedChunks[quoteIndex].segment.end <= chunk.start) {
      quoteIndex++;
    }
    int? group;
    if (quoteIndex < quotedChunks.length) {
      final q = quotedChunks[quoteIndex];
      if (q.segment.start <= chunk.start &&
          chunk.end <= q.segment.end) {
        group = q.quoteGroup;
      }
    }
    final hasLabel = speakerByStart.containsKey(chunk.start);
    final speaker = speakerByStart[chunk.start];
    final previous = merged.isEmpty ? null : merged.last;
    final continuous = previous != null &&
        previous.end <= chunk.start &&
        source.substring(previous.end, chunk.start).trim().isEmpty;
    final sameVoice = previous != null &&
        lastHadLabel == hasLabel &&
        lastSpeaker == speaker;
    final crossesSourceBoundary = previous != null &&
        _hasHardBoundary(sortedBoundaries, previous.start, chunk.end);
    if (group != null && group == lastGroup && sameVoice && continuous &&
        !crossesSourceBoundary &&
        chunk.end - previous!.start <= maxChars) {
      final combined = SpeechSegment(
        previous.start,
        chunk.end,
        source.substring(previous.start, chunk.end),
      );
      merged[merged.length - 1] = combined;
      // Previous label, if present, remains keyed to its unchanged start.
      continue;
    }
    merged.add(chunk);
    if (hasLabel) labels[chunk.start] = speaker;
    lastGroup = group;
    lastHadLabel = hasLabel;
    lastSpeaker = speaker;
  }
  return PreparedCastSpeech(
    List.unmodifiable(merged), Map.unmodifiable(labels));
}

/// Binary search keeps paragraph-aware coalescing O(chunks * log breaks).
/// Boundaries equal to the beginning or end of a chunk do not count as
/// *crossing* that chunk.
bool _hasHardBoundary(List<int> sorted, int start, int end) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final middle = low + (high - low) ~/ 2;
    if (sorted[middle] <= start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low < sorted.length && sorted[low] < end;
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
