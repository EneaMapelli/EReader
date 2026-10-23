import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'cast_span.dart';
import 'character_candidate.dart';

enum AliasCandidateStatus { proposed, accepted, rejected }

/// A literal mention proposed as an alternate name for an EXISTING character.
/// Neither a model-proposed identity nor the confidence is authoritative.
class AliasCandidate {
  const AliasCandidate({
    required this.id,
    required this.bookId,
    required this.alias,
    required this.targetCharacterId,
    required this.start,
    required this.end,
    required this.sourceDigest,
    required this.confidence,
    required this.status,
    this.evidence,
  });

  final String id;
  final String bookId;
  final String alias;
  final String? targetCharacterId;
  final int start;
  final int end;
  final String sourceDigest;
  final double confidence;
  final AliasCandidateStatus status;
  final CastSpanEvidence? evidence;

  static String fingerprint(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  String get normalizedAlias => CharacterCandidate.normalizeName(alias);

  bool matchesSource(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      fingerprint(source.substring(start, end)) == sourceDigest &&
      (evidence == null || evidence!.matchesSource(source));

  void validate() {
    if (id.isEmpty || id.length > 128 || bookId.isEmpty ||
        start < 0 || end <= start ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceDigest) ||
        alias.trim() != alias || alias.length < 2 || alias.length > 120 ||
        alias.contains(RegExp(r'[\r\n\t]')) ||
        !confidence.isFinite || confidence < 0 || confidence > 1 ||
        (targetCharacterId != null &&
         (targetCharacterId!.isEmpty || targetCharacterId!.length > 128))) {
      throw const FormatException('Invalid alias suggestion');
    }
    evidence?.validate();
    if (evidence != null && evidence!.end > start) {
      throw const FormatException('Alias evidence must precede the mention');
    }
  }
}
