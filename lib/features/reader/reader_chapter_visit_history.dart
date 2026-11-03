/// A return destination captured before a successfully committed EPUB
/// chapter switch. Offsets are canonical original UTF-16 source positions.
/// Identity matters: two visits to the same position are separate events.
class ReaderChapterVisit {
  const ReaderChapterVisit({
    required this.sourceOffset,
    required this.sectionTitle,
    required this.sectionNumber,
    required this.sectionCount,
    this.spineIdref,
  });

  final int sourceOffset;
  final String? spineIdref;
  final String sectionTitle;
  final int sectionNumber;
  final int sectionCount;
}

/// Bounded, in-memory back stack of EPUB chapter-switch origins.
///
/// A jump is recorded ONLY after the actual source seek and SQLite reading
/// checkpoint commit. The user can return to the most recent entry or select
/// an older entry from a sheet. Returning to an older entry removes it
/// and newer entries from Back while preserving them, in travel order,
/// in a separate Forward stack. A new committed chapter switch abandons
/// that Forward branch. Canceled, superseded or failed seeks mutate neither.
///
/// This history is independent of percentage Go and EPUB note/link return,
/// and is never persisted as a reading bookmark.
class ReaderChapterVisitHistory {
  ReaderChapterVisitHistory({this.maxDepth = 20}) : assert(maxDepth > 0);

  final int maxDepth;
  final List<ReaderChapterVisit> _entries = [];
  final List<ReaderChapterVisit> _forward = [];
  int _revision = 0;

  int get length => _entries.length;
  int get revision => _revision;
  bool get canReturn => _entries.isNotEmpty;
  ReaderChapterVisit? get latest =>
      _entries.isEmpty ? null : _entries.last;
  bool get canGoForward => _forward.isNotEmpty;
  ReaderChapterVisit? get nextForward =>
      _forward.isEmpty ? null : _forward.last;
  int get forwardLength => _forward.length;

  /// Newest first, stable for an open sheet. Entries are immutable.
  List<ReaderChapterVisit> get recent =>
      List<ReaderChapterVisit>.unmodifiable(_entries.reversed);

  bool contains(ReaderChapterVisit entry) =>
      _entries.any((item) => identical(item, entry));

  bool recordCommittedJump({
    required int fromOffset,
    required int toOffset,
    required int sourceLength,
    required String sectionTitle,
    required int sectionNumber,
    required int sectionCount,
    String? originSpineIdref,
    String? destinationSpineIdref,
  }) {
    if (sourceLength <= 0 ||
        fromOffset < 0 || fromOffset > sourceLength ||
        toOffset < 0 || toOffset > sourceLength ||
        (originSpineIdref != null && originSpineIdref.isEmpty) ||
        (destinationSpineIdref != null && destinationSpineIdref.isEmpty) ||
        sectionTitle.trim().isEmpty ||
        sectionCount < 1 ||
        sectionNumber < 1 || sectionNumber > sectionCount ||
        (fromOffset == toOffset &&
            originSpineIdref == destinationSpineIdref)) {
      return false;
    }
    if (_entries.length == maxDepth) _entries.removeAt(0);
    _entries.add(ReaderChapterVisit(
      sourceOffset: fromOffset,
      spineIdref: originSpineIdref,
      sectionTitle: sectionTitle,
      sectionNumber: sectionNumber,
      sectionCount: sectionCount,
    ));
    // Branching to another EPUB chapter invalidates redo, but not Back.
    // An invalid/no-op jump is rejected above and leaves redo untouched.
    _forward.clear();
    _revision++;
    return true;
  }

  /// Call only after a successful, persisted backward source seek.
  ///
  /// With [departedFrom], keep the positions passed over, plus the
  /// destination of the old current position, in Forward travel order.
  /// Without it, retain the historical destructive consumption behavior
  /// for callers that deliberately do not provide a redo destination.
  bool consumeThrough(ReaderChapterVisit entry, {
    required int expectedRevision,
    ReaderChapterVisit? departedFrom,
  }) {
    if (expectedRevision != _revision) return false;
    final index = _entries.indexWhere((item) => identical(item, entry));
    if (index < 0) return false;
    if (departedFrom != null) {
      final later = [
        ..._entries.skip(index + 1),
        departedFrom,
      ];
      for (final visit in later.reversed) {
        _forward.add(visit);
      }
      _cap(_forward);
    }
    _entries.removeRange(index, _entries.length);
    _revision++;
    return true;
  }

  /// Call only after a successful, persisted forward source seek.
  /// Moving forward records the current location back into Back without
  /// clearing any remaining redo destinations.
  bool consumeForward(ReaderChapterVisit entry, {
    required int expectedRevision,
    required ReaderChapterVisit departedFrom,
  }) {
    if (expectedRevision != _revision || _forward.isEmpty ||
        !identical(_forward.last, entry)) return false;
    _forward.removeLast();
    _entries.add(departedFrom);
    _cap(_entries);
    _revision++;
    return true;
  }

  void _cap(List<ReaderChapterVisit> stack) {
    if (stack.length > maxDepth) {
      stack.removeRange(0, stack.length - maxDepth);
    }
  }

  void clear() {
    _entries.clear();
    _forward.clear();
    _revision++;
  }
}
