/// Pure structural audit of the canonical extracted EPUB source.
///
/// Any violation threatens saved progress, speech alignment or link safety,
/// so importing must fail instead of trying to correct/guess an offset.
/// Optional visual resources may be omitted before reaching this audit.
void verifyEpubSourceIntegrity({
  required String text,
  required List<({String id, int start, int end})> spine,
  required List<({int start, int end, int? target})> links,
  required List<int> navigationTargets,
  required List<int> noteTargets,
}) {
  if (text.isEmpty || spine.isEmpty) {
    throw const FormatException('Empty EPUB source or spine');
  }
  final ids = <String>{};
  var expectedStart = 0;
  for (final entry in spine) {
    if (entry.id.isEmpty || !ids.add(entry.id) ||
        entry.start != expectedStart ||
        entry.end <= entry.start || entry.end > text.length ||
        _splitsSurrogate(text, entry.start) ||
        _splitsSurrogate(text, entry.end)) {
      throw const FormatException('EPUB spine source anchor integrity failure');
    }
    expectedStart = entry.end;
    if (expectedStart < text.length) {
      if (expectedStart + 2 > text.length ||
          text.substring(expectedStart, expectedStart + 2) != '\n\n') {
        throw const FormatException('Unexpected EPUB spine separator');
      }
      expectedStart += 2;
    }
  }
  if (expectedStart != text.length) {
    throw const FormatException('EPUB source not covered by spine');
  }

  int spineIndexAt(int offset) {
    var low = 0, high = spine.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (spine[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < spine.length && offset >= spine[low].start
        ? low : -1;
  }

  bool readable(int offset) =>
      spineIndexAt(offset) >= 0 && !_splitsSurrogate(text, offset);

  var previousLinkEnd = 0;
  for (final link in links) {
    if (link.start < previousLinkEnd || link.start < 0 ||
        link.end <= link.start || link.end > text.length ||
        !readable(link.start) ||
        _splitsSurrogate(text, link.end) ||
        (link.target != null && !readable(link.target!))) {
      throw const FormatException('EPUB link source anchor integrity failure');
    }
    // A source link must be wholly inside one spine file; otherwise it
    // would include synthetic separators never present in the XHTML.
    if (spineIndexAt(link.start) != spineIndexAt(link.end - 1)) {
      throw const FormatException('EPUB link crosses spine files');
    }
    previousLinkEnd = link.end;
  }
  for (final offset in navigationTargets) {
    if (!readable(offset)) {
      throw const FormatException('EPUB navigation target outside spine');
    }
  }
  for (final offset in noteTargets) {
    if (!readable(offset)) {
      throw const FormatException('EPUB footnote target outside spine');
    }
  }
}

bool _splitsSurrogate(String value, int offset) {
  if (offset <= 0 || offset >= value.length) return false;
  final before = value.codeUnitAt(offset - 1);
  final after = value.codeUnitAt(offset);
  return before >= 0xd800 && before <= 0xdbff &&
      after >= 0xdc00 && after <= 0xdfff;
}
