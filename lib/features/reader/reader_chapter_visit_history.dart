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
/// an older entry from a sheet. Returning to an older entry discards that
/// entry and all newer entries, preserving older history. A canceled,
/// superseded or failed return does not mutate the stack.
///
/// This history is independent of percentage Go and EPUB note/link return,
/// and is never persisted as a reading bookmark.
class ReaderChapterVisitHistory {
  ReaderChapterVisitHistory({this.maxDepth = 20}) : assert(maxDepth > 0);

  final int maxDepth;
  final List<ReaderChapterVisit> _entries = [];
  int _revision = 0;

  int get length => _entries.length;
  int get revision => _revision;
  bool get canReturn => _entries.isNotEmpty;
  ReaderChapterVisit? get latest =>
      _entries.isEmpty ? null : _entries.last;

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
    _revision++;
    return true;
  }

  /// The revision prevents an old asynchronous return from consuming a
  /// different, newer visit even when both share the same source offset.
  bool consumeThrough(ReaderChapterVisit entry, {
    required int expectedRevision,
  }) {
    if (expectedRevision != _revision) return false;
    final index = _entries.indexWhere((item) => identical(item, entry));
    if (index < 0) return false;
    _entries.removeRange(index, _entries.length);
    _revision++;
    return true;
  }

  void clear() {
    _entries.clear();
    _revision++;
  }
}
