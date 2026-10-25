/// Select the precise location to remember before following an EPUB link.
///
/// While narration is active, the current spoken phrase is authoritative.
/// Otherwise the paragraph actually visible to the reader is authoritative,
/// even if it has no speech segment of its own. Never infer the return
/// address from the next playable TTS segment in a silent illustration.
int epubSourceOffsetForLinkReturn({
  required int speechOffset,
  required bool narrationActive,
  int? visualOffset,
}) {
  if (!narrationActive && visualOffset != null && visualOffset >= 0) {
    return visualOffset;
  }
  return speechOffset;
}

/// A bounded, in-memory back stack for EPUB footnotes and internal links.
/// Stores original source offsets, not visual indices, speech indices,
/// web URLs or generated EPUB CFI values.
class EpubLinkHistory {
  EpubLinkHistory({this.maxDepth = 20})
      : assert(maxDepth > 0);
  final int maxDepth;
  final List<int> _locations = [];

  bool get canReturn => _locations.isNotEmpty;
  int? get last => canReturn ? _locations.last : null;
  int get length => _locations.length;

  void push(int fromOffset, int toOffset) {
    if (fromOffset < 0 || toOffset < 0 || fromOffset == toOffset) return;
    if (_locations.length == maxDepth) _locations.removeAt(0);
    _locations.add(fromOffset);
  }

  void commitReturn() {
    if (_locations.isNotEmpty) _locations.removeLast();
  }

  void clear() => _locations.clear();
}
