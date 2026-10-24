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
