import 'package:ereader/domain/character_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bookText = 'Anna entered. Captain Mira greeted her.';
  final start = bookText.indexOf('Captain Mira');
  final end = start + 'Captain Mira'.length;

  CharacterCandidate grounded({
    CharacterCandidateStatus status = CharacterCandidateStatus.proposed,
  }) => CharacterCandidate(
    id: 'candidate-1',
    bookId: 'book-1',
    name: 'Captain Mira',
    start: start,
    end: end,
    sourceDigest: CharacterCandidate.fingerprint('Captain Mira'),
    confidence: 0.7,
    status: status,
  );

  test('a new candidate refers to exact UTF-16 source text', () {
    final candidate = grounded();
    expect(() => candidate.validate(), returnsNormally);
    expect(candidate.matchesSource(bookText), isTrue);
    expect(candidate.matchesSource(
        bookText.replaceFirst('Mira', 'Nora')), isFalse);
  });

  test('detects existing names and aliases ignoring case/extra spaces', () {
    expect(candidateConflictsWithCast('  captain   MIRA ',
        ['Anna', 'Captain Mira']), isTrue);
    expect(candidateConflictsWithCast('MIRA', ['Mira']), isTrue);
    expect(candidateConflictsWithCast('Mira', ['Anna', 'Jane']), isFalse);
  });

  test('rejects invalid confidence or false approval without a person', () {
    final bad = CharacterCandidate(
      id: 'candidate',
      bookId: 'book',
      name: 'Mira',
      start: 0,
      end: 4,
      sourceDigest: CharacterCandidate.fingerprint('Mira'),
      confidence: double.nan,
      status: CharacterCandidateStatus.proposed,
    );
    expect(() => bad.validate(), throwsFormatException);
    final unreviewed = CharacterCandidate(
      id: 'candidate',
      bookId: 'book',
      name: 'Mira',
      start: 0,
      end: 4,
      sourceDigest: CharacterCandidate.fingerprint('Mira'),
      confidence: 0.8,
      status: CharacterCandidateStatus.proposed,
      createdCharacterId: 'person-1',
    );
    expect(() => unreviewed.validate(), throwsFormatException);
  });
}
