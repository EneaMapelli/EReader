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
    if (resolved == null || resolved < 0 ||
        resolved + length > source.length) return false;
    return digest(source.substring(resolved, resolved + length))
        == sourceDigest;
  }
}

/// Pure output. The only role of a cast label is to choose a voice: no
/// rewriting, paraphrasing or reordering of original source text is allowed.
class PreparedCastSpeech {
  const PreparedCastSpeech(this.segments, this.speakerByStart);
  final List<SpeechSegment> segments;
  final Map<int, String> speakerByStart;
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
  final usable = <({int start, int end, String speaker})>[];
  for (final span in annotations) {
    if (span.status != CastSpanStatus.accepted ||
        span.speakerId == null ||
        !span.matchesSource(source, offsetFromAnchor)) continue;
    final start = span.resolvedStart(offsetFromAnchor)!;
    usable.add((start: start, end: start + span.length,
        speaker: span.speakerId!));
  }
  usable.sort((a, b) {
    final start = a.start.compareTo(b.start);
    return start == 0 ? a.end.compareTo(b.end) : start;
  });

  // Invalid, overlapping authoring data is safe-by-default. Do not give
  // precedence to an arbitrarily ordered conflicting character.
  final conflicts = <int>{};
  for (var i = 1; i < usable.length; i++) {
    if (usable[i].start < usable[i - 1].end) {
      conflicts.add(i);
      conflicts.add(i - 1);
    }
  }
  final accepted = <({int start, int end, String speaker})>[
    for (var i = 0; i < usable.length; i++)
      if (!conflicts.contains(i)) usable[i],
  ];

  final output = <SpeechSegment>[];
  final speakers = <int, String>{};
  for (final segment in base) {
    if (segment.start < 0 || segment.end > source.length ||
        segment.end <= segment.start ||
        source.substring(segment.start, segment.end) != segment.text) {
      throw const FormatException('Base segment is not source-aligned');
    }
    final cuts = <int>{segment.start, segment.end};
    for (final active in accepted) {
      if (active.start < segment.end && active.end > segment.start) {
        if (active.start > segment.start && active.start < segment.end) {
          cuts.add(active.start);
        }
        if (active.end > segment.start && active.end < segment.end) {
          cuts.add(active.end);
        }
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
      for (final active in accepted) {
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
