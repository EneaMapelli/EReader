import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'reading_anchor.dart';
import 'speech_segment.dart';
import 'voice_cast.dart';

/// Exact earlier passage cited in support of a suggested speaker.
/// This is provenance for review, not proof that the inference is correct.
class CastSpanEvidence {
  const CastSpanEvidence({
    required this.start,
    required this.end,
    required this.sourceDigest,
  });

  final int start;
  final int end;
  final String sourceDigest;

  void validate() {
    if (start < 0 || end <= start ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceDigest)) {
      throw const FormatException('Invalid speaker evidence reference');
    }
  }

  bool matchesSource(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      CastSpan.digest(source.substring(start, end)) == sourceDigest;

  Map<String, Object> toJson() => {
        'start': start,
        'end': end,
        'source_sha256': sourceDigest,
      };

  factory CastSpanEvidence.fromJson(Map<String, dynamic> json) {
    final evidence = CastSpanEvidence(
      start: json['start'] as int,
      end: json['end'] as int,
      sourceDigest: json['source_sha256'] as String,
    );
    evidence.validate();
    return evidence;
  }
}

enum CastSpanOrigin { user, llm }
enum CastSpanStatus { proposed, accepted, rejected }

/// Source-accurate speech assignment. A proposed LLM label cannot drive
/// narration until a user explicitly reviews and accepts it.
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
    this.evidence,
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
  final CastSpanEvidence? evidence;

  static String digest(String source) =>
      sha256.convert(utf8.encode(source)).toString();

  /// Dart offsets are UTF-16 code units. Never split a surrogate pair.
  static bool validUtf16Range(String source, int start, int end) {
    if (start < 0 || end <= start || end > source.length) return false;
    bool splitsPair(int at) =>
        at > 0 && at < source.length &&
        source.codeUnitAt(at - 1) >= 0xD800 &&
        source.codeUnitAt(at - 1) <= 0xDBFF &&
        source.codeUnitAt(at) >= 0xDC00 &&
        source.codeUnitAt(at) <= 0xDFFF;
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
    evidence?.validate();
    if (evidence != null && evidence!.end > start) {
      throw const FormatException('Speaker evidence must precede the quote');
    }
    if (origin == CastSpanOrigin.llm &&
        status != CastSpanStatus.proposed &&
        !lockedByUser) {
      throw const FormatException('LLM label requires explicit user review');
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
    final actualStart = resolvedStart(locate);
    if (actualStart == null ||
        !validUtf16Range(source, actualStart, actualStart + length)) {
      return false;
    }
    return digest(source.substring(actualStart, actualStart + length)) ==
        sourceDigest;
  }
}

class PreparedCastSpeech {
  const PreparedCastSpeech(this.segments, this.speakerByStart);

  final List<SpeechSegment> segments;
  /// A present null means the user explicitly selected narrator/unknown.
  final Map<int, String?> speakerByStart;
}

/// Split existing speech segments without changing any book content or
/// positions. Invalid or overlapping annotations do not take effect.
PreparedCastSpeech prepareCastSpeech({
  required String source,
  required List<SpeechSegment> base,
  required List<CastSpan> annotations,
  required int? Function(ReadingAnchor) offsetFromAnchor,
  String? bookId,
  List<SegmentCastAssignment> legacyAssignments = const [],
  Set<String>? knownCharacterIds,
}) {
  final usable = <({int start, int end, String? speaker})>[];
  for (final span in annotations) {
    if (span.status != CastSpanStatus.accepted ||
        !span.lockedByUser ||
        (bookId != null && span.bookId != bookId) ||
        (span.speakerId != null && knownCharacterIds != null &&
            !knownCharacterIds.contains(span.speakerId)) ||
        !span.matchesSource(source, offsetFromAnchor)) continue;
    final actualStart = span.resolvedStart(offsetFromAnchor)!;
    usable.add((
      start: actualStart,
      end: actualStart + span.length,
      speaker: span.speakerId,
    ));
  }
  usable.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.end.compareTo(b.end);
  });

  // Reject both sides of *every* overlap, including contained intervals.
  final conflicts = <int>{};
  for (var i = 0; i < usable.length; i++) {
    for (var j = i + 1; j < usable.length; j++) {
      if (usable[j].start >= usable[i].end) break;
      conflicts.add(i);
      conflicts.add(j);
    }
  }
  final accepted = [
    for (var i = 0; i < usable.length; i++)
      if (!conflicts.contains(i)) usable[i],
  ];
  // A disputed fine-grained human label is not a reason to resurrect
  // an older legacy speaker underneath it. Suppress legacy attribution
  // across all contested exact source intervals and keep narrator fallback.
  final blockedFine = [
    for (var i = 0; i < usable.length; i++)
      if (conflicts.contains(i)) usable[i],
  ];

  // Legacy manually attributed *ranges* are also source-hashed, not
  // tied to the current TTS chunk boundaries. A previously labelled long
  // quotation must retain its voice when the chunker splits it in two.
  final legacy = <({int start, int end, String speaker})>[];
  if (legacyAssignments.isNotEmpty && bookId == null) {
    throw const FormatException('Legacy speech casting needs a book ID');
  }
  for (final mark in legacyAssignments) {
    if (mark.bookId != bookId ||
        (knownCharacterIds != null &&
            !knownCharacterIds.contains(mark.characterId))) continue;
    final start = mark.anchor == null
        ? mark.start : offsetFromAnchor(mark.anchor!);
    if (start == null) continue;
    final end = start + mark.end - mark.start;
    if (!CastSpan.validUtf16Range(source, start, end) ||
        SegmentCastAssignment.fingerprint(
            source.substring(start, end)) != mark.sourceDigest) continue;
    legacy.add((start: start, end: end, speaker: mark.characterId));
  }
  legacy.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.end.compareTo(b.end);
  });
  // Conflicting or duplicated legacy intervals are not authority; precise
  // human-approved spans still win over every legacy assignment.
  final rejectedLegacy = <int>{};
  for (var i = 0; i < legacy.length; i++) {
    for (var j = i + 1; j < legacy.length; j++) {
      if (legacy[j].start >= legacy[i].end) break;
      rejectedLegacy.add(i);
      rejectedLegacy.add(j);
    }
  }
  final safeLegacy = [
    for (var i = 0; i < legacy.length; i++)
      if (!rejectedLegacy.contains(i)) legacy[i],
  ];

  final pieces = <SpeechSegment>[];
  final speakerByStart = <int, String?>{};
  var firstPossible = 0;
  var firstLegacy = 0;
  for (final baseSegment in base) {
    if (!CastSpan.validUtf16Range(
            source, baseSegment.start, baseSegment.end) ||
        source.substring(baseSegment.start, baseSegment.end) !=
            baseSegment.text) {
      throw const FormatException('Base speech segment is not source-aligned');
    }
    while (firstPossible < accepted.length &&
        accepted[firstPossible].end <= baseSegment.start) {
      firstPossible++;
    }
    final local = <({int start, int end, String? speaker})>[];
    final localLegacy = <({int start, int end, String speaker})>[];
    final localBlocked = <({int start, int end})>[];
    final boundaries = <int>{baseSegment.start, baseSegment.end};
    for (var j = firstPossible; j < accepted.length; j++) {
      final active = accepted[j];
      if (active.start >= baseSegment.end) break;
      local.add(active);
      if (active.start > baseSegment.start &&
          active.start < baseSegment.end) boundaries.add(active.start);
      if (active.end > baseSegment.start &&
          active.end < baseSegment.end) boundaries.add(active.end);
    }
    for (final active in blockedFine) {
      if (active.start >= baseSegment.end ||
          active.end <= baseSegment.start) continue;
      localBlocked.add((start: active.start, end: active.end));
      if (active.start > baseSegment.start &&
          active.start < baseSegment.end) boundaries.add(active.start);
      if (active.end > baseSegment.start &&
          active.end < baseSegment.end) boundaries.add(active.end);
    }
    while (firstLegacy < safeLegacy.length &&
        safeLegacy[firstLegacy].end <= baseSegment.start) {
      firstLegacy++;
    }
    for (var j = firstLegacy; j < safeLegacy.length; j++) {
      final active = safeLegacy[j];
      if (active.start >= baseSegment.end) break;
      localLegacy.add(active);
      if (active.start > baseSegment.start &&
          active.start < baseSegment.end) boundaries.add(active.start);
      if (active.end > baseSegment.start &&
          active.end < baseSegment.end) boundaries.add(active.end);
    }
    final sorted = boundaries.toList()..sort();
    for (var i = 0; i + 1 < sorted.length; i++) {
      var from = sorted[i], to = sorted[i + 1];
      while (from < to && _isWhitespace(source.codeUnitAt(from))) {
        from++;
      }
      while (to > from && _isWhitespace(source.codeUnitAt(to - 1))) {
        to--;
      }
      if (from >= to) continue;
      pieces.add(SpeechSegment(from, to, source.substring(from, to)));
      var assignedFine = false;
      for (final active in local) {
        if (from >= active.start && to <= active.end) {
          speakerByStart[from] = active.speaker;
          assignedFine = true;
          break;
        }
      }
      // An explicit narrator label is a present-null and masks the legacy
      // character assignment, including across multiple base chunks.
      // On contested fine-grained ranges, do not reinstate a stale
      // legacy character voice through the fallback layer.
      final disputed = localBlocked.any((active) =>
          from >= active.start && to <= active.end);
      if (!assignedFine && !disputed) {
        for (final active in localLegacy) {
          if (from >= active.start && to <= active.end) {
            speakerByStart[from] = active.speaker;
            break;
          }
        }
      }
    }
  }
  return PreparedCastSpeech(
    List.unmodifiable(pieces),
    Map.unmodifiable(speakerByStart),
  );
}

bool _isWhitespace(int c) =>
    c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0;
