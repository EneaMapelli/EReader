import 'package:ereader/domain/alias_candidate.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = 'Mira was addressed as the Captain.';
  final start = source.indexOf('the Captain');
  final end = start + 'the Captain'.length;

  AliasCandidate makeAlias({int? startAt, CastSpanEvidence? evidence}) =>
      AliasCandidate(
        id: 'suggestion', bookId: 'book',
        alias: 'the Captain', targetCharacterId: 'mira',
        start: startAt ?? start, end: end,
        sourceDigest: AliasCandidate.fingerprint('the Captain'),
        confidence: 0.77, status: AliasCandidateStatus.proposed,
        evidence: evidence,
      );

  test('alias is a source-grounded pending proposition only', () {
    final alias = makeAlias();
    expect(() => alias.validate(), returnsNormally);
    expect(alias.matchesSource(source), isTrue);
    expect(alias.status, AliasCandidateStatus.proposed);
    expect(alias.targetCharacterId, 'mira');
    expect(alias.matchesSource(source.replaceFirst(
        'the Captain', 'the Admiral')), isFalse);
  });

  test('previous-context evidence must precede the alias', () {
    final prior = CastSpanEvidence(
      start: 0, end: 4,
      sourceDigest: CastSpan.digest('Mira'),
    );
    final candidate = makeAlias(evidence: prior);
    expect(candidate.matchesSource(source), isTrue);
    final invalid = makeAlias(evidence: CastSpanEvidence(
      start: start, end: end,
      sourceDigest: CastSpan.digest('the Captain'),
    ));
    expect(() => invalid.validate(), throwsFormatException);
  });

  test('invalid model confidence and half-surrogate offsets rejected', () {
    final invalid = AliasCandidate(
      id: 'bad', bookId: 'book', alias: 'Captain',
      targetCharacterId: 'mira', start: 0, end: 7,
      sourceDigest: CastSpan.digest('Captain'),
      confidence: double.infinity, status: AliasCandidateStatus.proposed);
    expect(() => invalid.validate(), throwsFormatException);
    const unicode = '😀 Captain';
    final halfEmoji = AliasCandidate(
      id: 'bad-offset', bookId: 'book', alias: 'emoji',
      targetCharacterId: 'mira', start: 1, end: 6,
      sourceDigest: AliasCandidate.fingerprint(
          unicode.substring(1, 6)),
      confidence: 0.5, status: AliasCandidateStatus.proposed);
    expect(halfEmoji.matchesSource(unicode), isFalse);
  });
}
