import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'reading_anchor.dart';
import 'speech_segment.dart';

/// A source-accurate, provider-independent speaker label. LLM output may
/// only create proposed spans; only a user action can accept them.
/// Null speaker means "unknown" and always uses the narrator voice.
enum CastSpanOrigin { user, llm }
enum CastSpanStatus { proposed, accepted, rejected }

class CastSpan {
  const CastSpan({
    required this.id,
    required this.bookId,
    required this.start,
    required this.end,
    required this.sourceDigest,
    required this.speakerId,
    required this.origin,
    required this.status,
    required this.lockedByUser,
    this.confidence,
    this.anchor,
  });

  final String id;
  final String bookId;
  final int start;
  final int end;
  final String sourceDigest;
  final String? speakerId;
  final CastSpanOrigin origin;
  final CastSpanStatus status;
  final bool lockedByUser;
  final double? confidence;
  final ReadingAnchor? anchor;

  static String digest(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// A text selection must not split a UTF-16 surrogate pair in half.
  /// Offsets are Dart String code units, not grapheme-cluster indices.
  static bool validUtf16Range(String source, int start, int end) {
    if (start < 0 || end <= start || end > source.length) return false;
    bool splitsPair(int index) =>
        index > 0 && index < source.length &&
        source.codeUnitAt(index - 1) >= 0xD800 &&
        source.codeUnitAt(index - 1) <= 0xDBFF &&
        source.codeUnitAt(index) >= 0xDC00 &&
        source.codeUnitAt(index) <= 0xDFFF;
    return !splitsPair(start) && !splitsPair(end);
  }

  int get length => end - start;

  void validate() {
    if (id.isEmpty || id.length > 128 || bookId.isEmpty ||
        start < 0 || end <= start ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceDigest)) {
      throw const FormatException('Invalid source cast span');
    }
    if (speakerId != null &&
        (speakerId!.isEmpty || speakerId!.length > 128)) {
      throw const FormatException('Invalid speaker ID');
    }
    if (confidence != null &&
        (!confidence!.isFinite || confidence! < 0 || confidence! > 1)) {
      throw const FormatException('Cast confidence must be 0–1');
    }
    if (origin == CastSpanOrigin.llm &&
        status != CastSpanStatus.proposed &&
        !lockedByUser) {
      throw const FormatException(
          'LLM suggestion needs explicit user approval');
    }
    if (origin == CastSpanOrigin.user &&
        (status != CastSpanStatus.accepted || !lockedByUser)) {
      throw const FormatException('Manual labels must be accepted and locked');
    }
  }

  int? resolvedStart(int? Function(ReadingAnchor) locate) =>
      anchor == null ? start : locate(anchor!);

  bool matchesSource(
    String source,
    int? Function(ReadingAnchor) locate,
  ) {
    final resolved = resolvedStart(locate);
    if (resolved == null ||
        !validUtf16Range(source, resolved, resolved + length)) return false;
    return digest(source.substring(resolved, resolved + length))
        == sourceDigest;
  }
}

/// Pure output. The only role of a cast label is to choose a voice: no
/// rewriting, paraphrasing or reordering of original source text is allowed.
class PreparedCastSpeech {
  const PreparedCastSpeech(this.segments, this.speakerByStart);
  final List<SpeechSegment> segments;
  final Map<int, String?> speakerByStart;
}

/// Break base narration into original-text slices at manual speaker edges.
/// Validate SHA-256 and source anchors first. Stale or overlapping labels
/// revert to narrator. A future LLM proposal is never used until approved.
PreparedCastSpeech prepareCastSpeech({
  required String source,
  required List<SpeechSegment> base,
  required List<CastSpan> annotations,
  required int? Function(ReadingAnchor) offsetFromAnchor,
}) {
  final usable = <({int start, int end, String? speaker})>[];
  for (final span in annotations) {
    if (span.status != CastSpanStatus.accepted ||
        !span.matchesSource(source, offsetFromAnchor)) continue;
    final start = span.resolvedStart(offsetFromAnchor)!;
    usable.add((start: start, end: start + span.length,
        speaker: span.speakerId));
  }
  usable.sort((a, b) {
    final start = a.start.compareTo(b.start);
    return start == 0 ? a.end.compareTo(b.end) : start;
  });

  // Invalid, overlapping authoring data is safe-by-default. Do not give
  // precedence to an arbitrarily ordered conflicting character.
  final conflicts = <int>{};
  // Check every interval overlapped by a long label, not just neighbors.
  // The inner loop exits immediately for ordinary nonoverlapping turns.
  for (var i = 0; i < usable.length; i++) {
    for (var j = i + 1; j < usable.length; j++) {
      if (usable[j].start >= usable[i].end) break;
      conflicts.add(i);
      conflicts.add(j);
    }
  }
  final accepted = <({int start, int end, String? speaker})>[
    for (var i = 0; i < usable.length; i++)
      if (!conflicts.contains(i)) usable[i],
  ];

  final output = <SpeechSegment>[];
  final speakers = <int, String?>{};
  var firstPossible = 0;
  for (final segment in base) {
    if (segment.start < 0 || segment.end > source.length ||
        segment.end <= segment.start ||
        source.substring(segment.start, segment.end) != segment.text) {
      throw const FormatException('Base segment is not source-aligned');
    }
    while (firstPossible < accepted.length &&
        accepted[firstPossible].end <= segment.start) {
      firstPossible++;
    }
    final nearby = <({int start, int end, String? speaker})>[];
    final cuts = <int>{segment.start, segment.end};
    for (var candidate = firstPossible; candidate < accepted.length;
        candidate++) {
      final active = accepted[candidate];
      if (active.start >= segment.end) break;
      nearby.add(active);
      if (active.start > segment.start && active.start < segment.end) {
        cuts.add(active.start);
      }
      if (active.end > segment.start && active.end < segment.end) {
        cuts.add(active.end);
      }
    }
    final sorted = cuts.toList()..sort();
    for (var i = 0; i + 1 < sorted.length; i++) {
      var from = sorted[i], to = sorted[i + 1];
      while (from < to && _whitespace(source.codeUnitAt(from))) {
        from++;
      }
      while (to > from && _whitespace(source.codeUnitAt(to - 1))) {
        to--;
      }
      if (from >= to) continue;
      final part = SpeechSegment(from, to, source.substring(from, to));
      output.add(part);
      for (final active in nearby) {
        if (from >= active.start && to <= active.end) {
          speakers[from] = active.speaker;
          break;
        }
      }
    }
  }
  return PreparedCastSpeech(
      List.unmodifiable(output), Map.unmodifiable(speakers));
}

bool _whitespace(int c) => c == 32 || c == 9 || c == 10 ||
    c == 13 || c == 0xA0;
