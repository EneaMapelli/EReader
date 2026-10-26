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
  var lastSpokenEnd = 0;
  var hasSpoken = false;
  for (final entry in spine) {
    // A zero-length OPF XHTML resource is a valid navigation-only item.
    // Its source coordinate is the end of the preceding spoken item (or
    // zero before the first one). It may NOT steal bytes from a neighbor.
    if (entry.id.isEmpty || !ids.add(entry.id) ||
        entry.start < 0 || entry.end < entry.start ||
        entry.end > text.length ||
        _splitsSurrogate(text, entry.start) ||
        _splitsSurrogate(text, entry.end)) {
      throw const FormatException('EPUB spine source anchor integrity failure');
    }
    if (entry.start == entry.end) {
      if (entry.start != lastSpokenEnd) {
        throw const FormatException('Invalid silent EPUB spine position');
      }
      continue;
    }
    if (!hasSpoken) {
      if (entry.start != 0) {
        throw const FormatException('EPUB text starts outside first spine');
      }
    } else if (entry.start != lastSpokenEnd + 2 ||
        entry.start > text.length ||
        text.substring(lastSpokenEnd, entry.start) != '\n\n') {
      throw const FormatException('Unexpected EPUB spine separator');
    }
    lastSpokenEnd = entry.end;
    hasSpoken = true;
  }
  if (!hasSpoken || lastSpokenEnd != text.length) {
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
