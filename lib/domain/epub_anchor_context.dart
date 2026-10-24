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
    final before = <int>[];
    for (var i = offset - 1; i >= start && before.length < contextUnits; i--) {
      final unit = text.codeUnitAt(i);
      if (!_space(unit)) before.add(unit);
    }
    final after = <int>[];
    for (var i = offset; i < end && after.length < contextUnits; i++) {
      final unit = text.codeUnitAt(i);
      if (!_space(unit)) after.add(unit);
    }
    // Stable binary representation, including raw surrogate code units.
    String digest(List<int> units, {required bool reversed}) {
      final bytes = <int>[];
      final values = reversed ? units.reversed : units;
      for (final unit in values) {
        bytes.add(unit >> 8);
        bytes.add(unit & 255);
      }
      return sha256.convert(bytes).toString().substring(0, 32);
    }
    return (
      before: digest(before, reversed: true),
      after: digest(after, reversed: false),
    );
  }

  static bool matches(String text, int start, int end,
      int offset, ReadingAnchor anchor) {
    if (!anchor.hasContext || offset < start || offset > end ||
        _splitsSurrogate(text, offset) ||
        (offset < end && _space(text.codeUnitAt(offset)))) return false;
    final c = capture(text, start, end, offset);
    return c.before == anchor.contextBefore && c.after == anchor.contextAfter;
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
      // Prefix check avoids hashing the suffix for most candidates.
      final c = capture(text, start, end, pos);
      if (c.before != anchor.contextBefore ||
          c.after != anchor.contextAfter) continue;
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
