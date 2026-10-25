import 'package:crypto/crypto.dart';

import 'reading_anchor.dart';

/// Only hashed UTF-16 context is persisted, never raw book excerpts.
/// Deliberately ignore whitespace while comparing nearby text, because
/// EPUB renderer upgrades often change CR/LF or HTML paragraph separators.
class EpubAnchorContext {
  static const int contextUnits = 32;
  static const int maxSearchUnits = 160000;

  static ({String before, String after}) capture(
      String text, int start, int end, int offset) {
    if (start < 0 || end > text.length || start >= end ||
        offset < start || offset > end) {
      throw RangeError('Invalid EPUB anchor capture range');
    }
    return (
      before: _sideDigest(text, start, end, offset, before: true),
      after: _sideDigest(text, start, end, offset, before: false),
    );
  }

  /// Each side has an independently checkable v2 fingerprint. Checking
  /// the preceding context first avoids hashing the following context at
  /// essentially every wrong candidate in a very long chapter.
  static String _sideDigest(String text, int start, int end, int offset,
      {required bool before}) {
    final units = <int>[];
    if (before) {
      for (var i = offset - 1; i >= start && units.length < contextUnits; i--) {
        final unit = text.codeUnitAt(i);
        if (!_space(unit)) units.add(unit);
      }
    } else {
      for (var i = offset; i < end && units.length < contextUnits; i++) {
        final unit = text.codeUnitAt(i);
        if (!_space(unit)) units.add(unit);
      }
    }
    // Keep the exact v2 byte order: before is reversed after scanning
    // backwards, after is already in source order. No hash migration.
    final bytes = <int>[];
    final ordered = before ? units.reversed : units;
    for (final unit in ordered) {
      bytes.add(unit >> 8);
      bytes.add(unit & 255);
    }
    return sha256.convert(bytes).toString().substring(0, 32);
  }

  static bool matches(String text, int start, int end,
      int offset, ReadingAnchor anchor) {
    if (!anchor.hasContext || offset < start || offset > end ||
        _splitsSurrogate(text, offset) ||
        (offset < end && _space(text.codeUnitAt(offset)))) return false;
    if (_sideDigest(text, start, end, offset, before: true) !=
        anchor.contextBefore) return false;
    return _sideDigest(text, start, end, offset, before: false) ==
        anchor.contextAfter;
  }

  /// Return a location only when there is exactly ONE full fingerprint
  /// match in the entire bounded source item. Repeated phrases must not
  /// produce an arbitrary relocation based on proximity alone.
  static int? relocate(String text, int start, int end,
      ReadingAnchor anchor) {
    if (!anchor.hasContext || start < 0 || end > text.length ||
        start >= end || end - start > maxSearchUnits) return null;
    int? found;
    for (var pos = start; pos <= end; pos++) {
      // Whitespace-insensitive fingerprints are identical at every
      // position inside a run of spaces/newlines. Only test the start of
      // actual glyphs (or item end) to avoid phantom ambiguity.
      if ((pos < end && _space(text.codeUnitAt(pos))) ||
          _splitsSurrogate(text, pos)) continue;
      if (_sideDigest(text, start, end, pos, before: true) !=
          anchor.contextBefore) continue;
      if (_sideDigest(text, start, end, pos, before: false) !=
          anchor.contextAfter) continue;
      if (found != null) return null;
      found = pos;
    }
    return found;
  }

  static bool _space(int value) =>
      value == 0x20 || value == 0x09 || value == 0x0a ||
      value == 0x0d || value == 0x0c || value == 0x00a0;

  static bool _splitsSurrogate(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return false;
    final left = text.codeUnitAt(offset - 1);
    final right = text.codeUnitAt(offset);
    return left >= 0xd800 && left <= 0xdbff &&
        right >= 0xdc00 && right <= 0xdfff;
  }
}
