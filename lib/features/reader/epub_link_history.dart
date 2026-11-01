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

/// A return location can refer to a visual-only OPF spine item. Multiple
/// illustration sections may share one canonical UTF-16 source offset.
class EpubLinkReturnLocation {
  const EpubLinkReturnLocation({
    required this.sourceOffset,
    this.spineIdref,
  });

  final int sourceOffset;
  final String? spineIdref;
}

/// A bounded, in-memory back stack for EPUB footnotes and internal links.
/// No external URL, generated CFI, or audio segment index is stored.
class EpubLinkHistory {
  EpubLinkHistory({this.maxDepth = 20})
      : assert(maxDepth > 0);
  final int maxDepth;
  final List<EpubLinkReturnLocation> _locations = [];

  bool get canReturn => _locations.isNotEmpty;
  EpubLinkReturnLocation? get lastLocation =>
      canReturn ? _locations.last : null;
  int? get last => lastLocation?.sourceOffset;
  int get length => _locations.length;

  void push(
    int fromOffset,
    int toOffset, {
    String? fromSpineIdref,
    String? toSpineIdref,
  }) {
    if (fromOffset < 0 || toOffset < 0 ||
        (fromSpineIdref != null && fromSpineIdref.isEmpty) ||
        (toSpineIdref != null && toSpineIdref.isEmpty) ||
        (fromOffset == toOffset && fromSpineIdref == toSpineIdref)) {
      return;
    }
    if (_locations.length == maxDepth) _locations.removeAt(0);
    _locations.add(EpubLinkReturnLocation(
      sourceOffset: fromOffset,
      spineIdref: fromSpineIdref,
    ));
  }

  /// Never consume a newly pushed link after an async return was superseded.
  /// Identity is intentional: two visits to the same location are distinct.
  bool commitReturnIfTop(EpubLinkReturnLocation expected) {
    if (_locations.isEmpty || !identical(_locations.last, expected)) {
      return false;
    }
    _locations.removeLast();
    return true;
  }

  void commitReturn() {
    if (_locations.isNotEmpty) _locations.removeLast();
  }

  void clear() => _locations.clear();
}
