import 'cast_span.dart';

enum NarrativeReferenceStatus { proposed, accepted, rejected }
enum NarrativeReferenceKind { pronoun, titleOrDescription }

/// Model suggestions cannot assign a voice or edit a cast identity.
/// A null suggested person means UNKNOWN or AMBIGUOUS, not narrator speech.
/// The reviewer chooses a confirmed identity in a separate explicit step.
class NarrativeReferenceCandidate {
  const NarrativeReferenceCandidate({
    required this.id,
    required this.bookId,
    required this.start,
    required this.end,
    required this.referenceText,
    required this.sourceDigest,
    required this.kind,
    required this.status,
    required this.confidence,
    this.proposedCharacterId,
    this.approvedCharacterId,
    this.ambiguous = false,
    this.evidence,
  });

  final String id;
  final String bookId;
  final int start;
  final int end;
  final String referenceText;
  final String sourceDigest;
  final NarrativeReferenceKind kind;
  final NarrativeReferenceStatus status;
  final String? proposedCharacterId;
  final String? approvedCharacterId;
  final double confidence;
  final bool ambiguous;
  final CastSpanEvidence? evidence;

  static final RegExp _pronoun = RegExp(
    r'^(?:he|him|his|himself|she|her|hers|herself|they|them|their|theirs|'
    r'themselves|lui|lei|loro|egli|ella|esso|essa|essi|esse|'
    r'lo|la|gli|le|elle|ils|elles|sie|er|ihm|'
    r'él|ellos|ellas|se|su)$',
    caseSensitive: false, unicode: true,
  );

  static NarrativeReferenceKind classify(String exactText) =>
      _pronoun.hasMatch(exactText.trim())
          ? NarrativeReferenceKind.pronoun
          : NarrativeReferenceKind.titleOrDescription;

  bool matchesSource(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      source.substring(start, end) == referenceText &&
      CastSpan.digest(referenceText) == sourceDigest &&
      (evidence == null || evidence!.matchesSource(source));

  void validate() {
    if (id.isEmpty || id.length > 128 || bookId.isEmpty ||
        !CastSpan.validUtf16Range(referenceText, 0, referenceText.length) ||
        start < 0 || end != start + referenceText.length ||
        referenceText.trim() != referenceText ||
        referenceText.length < 2 || referenceText.length > 100 ||
        referenceText.contains(RegExp(r'[\n\r\t]')) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceDigest) ||
        CastSpan.digest(referenceText) != sourceDigest ||
        !confidence.isFinite || confidence < 0 || confidence > 1 ||
        (proposedCharacterId != null && proposedCharacterId!.isEmpty) ||
        (approvedCharacterId != null &&
            (approvedCharacterId!.isEmpty ||
             status != NarrativeReferenceStatus.accepted))) {
      throw const FormatException('Invalid indirect reference proposal');
    }
    evidence?.validate();
    if (evidence != null && evidence!.end > start) {
      throw const FormatException('Reference evidence must be earlier');
    }
    if (ambiguous && proposedCharacterId != null) {
      throw const FormatException('Ambiguous references cannot have a winner');
    }
  }
}
