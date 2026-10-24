import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cast_span.dart';

enum CharacterCandidateStatus { proposed, accepted, rejected }

/// A new character *suggestion*, not an actual cast member. Every candidate
/// must cite one exact, unambiguous name mention in an authorized book window.
/// No voice or speaker assignments follow from accepting an identity.
class CharacterCandidate {
  const CharacterCandidate({
    required this.id,
    required this.bookId,
    required this.name,
    required this.start,
    required this.end,
    required this.sourceDigest,
    required this.confidence,
    required this.status,
    this.createdCharacterId,
  });

  final String id;
  final String bookId;
  final String name;
  final int start;
  final int end;
  final String sourceDigest;
  final double confidence;
  final CharacterCandidateStatus status;
  final String? createdCharacterId;

  static String fingerprint(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  bool matchesSource(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      fingerprint(source.substring(start, end)) == sourceDigest;

  void validate() {
    if (id.isEmpty || id.length > 128 || bookId.isEmpty ||
        start < 0 || end <= start ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest) ||
        name.trim().length < 2 || name.length > 120 ||
        name.contains(RegExp(r'[\r\n\t]')) ||
        !confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FormatException('Invalid character candidate');
    }
    if (createdCharacterId != null &&
        (status != CharacterCandidateStatus.accepted ||
         createdCharacterId!.isEmpty)) {
      throw const FormatException('Unreviewed character cannot have an ID');
    }
  }
}

/// Detect existing identities/aliases without changing their display names.
/// A case-insensitive match is conservative (may reject two genuinely distinct
/// people with identical names); such cases can still be added manually.
bool candidateConflictsWithCast(
    String candidateName, Iterable<String> existingNames) {
  final normalized = CharacterCandidate.normalizeName(candidateName);
  if (normalized.isEmpty) return true;
  return existingNames.any(
      (known) => CharacterCandidate.normalizeName(known) == normalized);
}
