import '../domain/speech_segment.dart';

/// A verified, source-aligned footnote body inside the EPUB reading spine.
/// This is metadata only: it never removes or rewrites book/source characters.
class EpubSpokenNoteRange {
  const EpubSpokenNoteRange(this.start, this.end);
  final int start;
  final int end;
}

/// Opt-in conservative rule for silent footnotes in narrated EPUB files.
///
/// A chunk is skipped ONLY when the entire original-source chunk is inside a
/// verified note body. A chunk crossing the note boundary remains audible:
/// we must not silently omit ordinary book text. Manual navigation, visual
/// layout, search, character casting and persisted source anchors are intact.
class EpubSpeechNoteFilter {
  EpubSpeechNoteFilter(String source, List<EpubSpokenNoteRange> ranges)
      : _source = source,
        _ranges = _normalize(source, ranges);

  final String _source;
  final List<EpubSpokenNoteRange> _ranges;

  bool get hasNotes => _ranges.isNotEmpty;

  bool contains(SpeechSegment segment) {
    if (_ranges.isEmpty || segment.start < 0 ||
        segment.end <= segment.start || segment.end > _source.length ||
        _source.substring(segment.start, segment.end) != segment.text) {
      return false;
    }
    // Last range whose start is <= segment.start. Merged source ranges are
    // disjoint, so no unrelated page/chapter text can become eligible.
    var low = 0;
    var high = _ranges.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_ranges[middle].start <= segment.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return false;
    return segment.end <= _ranges[low - 1].end;
  }

  static List<EpubSpokenNoteRange> _normalize(
    String source,
    List<EpubSpokenNoteRange> ranges,
  ) {
    final ordered = <EpubSpokenNoteRange>[];
    if (ranges.length > 200) {
      throw const FormatException('Excessive EPUB spoken note annotations');
    }
    for (final range in ranges) {
      if (range.start < 0 || range.end <= range.start ||
          range.end > source.length || range.end - range.start > 1600 ||
          (range.start > 0 && range.start < source.length &&
           _splitSurrogate(source, range.start)) ||
          (range.end < source.length && _splitSurrogate(source, range.end))) {
        throw const FormatException('Invalid EPUB spoken note source range');
      }
      ordered.add(range);
    }
    ordered.sort((a, b) => a.start.compareTo(b.start));
    final merged = <EpubSpokenNoteRange>[];
    for (final range in ordered) {
      if (merged.isNotEmpty && range.start < merged.last.end) {
        final previous = merged.removeLast();
        merged.add(EpubSpokenNoteRange(
          previous.start, range.end > previous.end ? range.end : previous.end,
        ));
      } else {
        merged.add(range);
      }
    }
    return List.unmodifiable(merged);
  }

  static bool _splitSurrogate(String text, int offset) {
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return before >= 0xD800 && before <= 0xDBFF &&
        after >= 0xDC00 && after <= 0xDFFF;
  }
}
