/// Session-only return point for an explicit, successfully committed
/// "Go to book position" jump. Never write this navigation aid to SQLite.
///
/// Recording a new jump replaces the previous one. A return consumes the
/// saved origin only after the reader confirms its source seek succeeded.
class ReaderProgressReturnPoint {
  int? _origin;
  String? _originSpineIdref;
  int _revision = 0;

  int? get origin => _origin;
  /// The visual-only EPUB spine ID disambiguates multiple sections whose
  /// source offsets are identical (for example, a cover without speech).
  String? get originSpineIdref => _originSpineIdref;
  bool get canReturn => _origin != null;
  int get revision => _revision;

  /// A canceled/failed/no-op jump must not replace an earlier return point.
  bool recordCommittedJump({
    required int fromOffset,
    required int toOffset,
    required int sourceLength,
    String? originSpineIdref,
    String? destinationSpineIdref,
  }) {
    if (sourceLength <= 0 ||
        fromOffset < 0 || fromOffset > sourceLength ||
        toOffset < 0 || toOffset > sourceLength ||
        (originSpineIdref != null && originSpineIdref.isEmpty) ||
        (destinationSpineIdref != null && destinationSpineIdref.isEmpty) ||
        (fromOffset == toOffset &&
            originSpineIdref == destinationSpineIdref)) {
      return false;
    }
    _origin = fromOffset;
    _originSpineIdref = originSpineIdref;
    _revision++;
    return true;
  }

  /// Do not consume a newly-recorded jump on a stale async return.
  bool consumeIfOrigin(int expectedOrigin, {int? expectedRevision}) {
    if (_origin != expectedOrigin ||
        (expectedRevision != null && _revision != expectedRevision)) {
      return false;
    }
    _origin = null;
    _originSpineIdref = null;
    _revision++;
    return true;
  }

  void clear() {
    _origin = null;
    _originSpineIdref = null;
    _revision++;
  }
}
