import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/narrative_reference.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/narrative_antecedent_finder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const finder = NarrativeAntecedentFinder();
  const mira = CastCharacter(
    id: 'mira', bookId: 'book', name: 'Mira',
    aliases: ['Captain Mira'],
  );
  const anna = CastCharacter(
    id: 'anna', bookId: 'book', name: 'Anna',
  );

  NarrativeAntecedentInspection search(
    String source, String token, {
    int scopeStart = 0,
    List<CastCharacter> cast = const [mira, anna],
    List<NarrativeReferenceCandidate> accepted = const [],
  }) {
    final at = source.lastIndexOf(token);
    expect(at, greaterThanOrEqualTo(0));
    return finder.inspect(
      bookId: 'book', source: source, scopeStart: scopeStart,
      referenceStart: at, referenceEnd: at + token.length,
      cast: cast, reviewedReferences: accepted,
    );
  }

  test('nearby different people remain competing cues, never a winner', () {
    const text = 'Mira entered. Anna followed. She started running.';
    final result = search(text, 'She');
    expect(result.cues, hasLength(2));
    expect(result.cues.first.characterId, 'anna');
    expect(result.cues.last.characterId, 'mira');
    expect(result.containsDifferentPeople, isTrue);
    expect(result.cues.every((cue) => cue.matchesOriginal(text)), isTrue);
    expect(result.cues.every((cue) => cue.end <= text.indexOf('She')), isTrue);
  });

  test('prior name and alias map to one most-recent cue per person', () {
    const text =
        'Mira watched carefully. Captain Mira answered. She nodded.';
    final result = search(text, 'She', cast: const [mira]);
    expect(result.cues, hasLength(1));
    expect(result.cues.single.characterId, 'mira');
    expect(result.cues.single.matchedText, 'Captain Mira');
    expect(result.cues.single.kind, AntecedentCueKind.explicitName);
  });

  test('whole word matching does not confuse Mira with Amira', () {
    const text = 'Amira spoke. She answered.';
    final result = search(text, 'She', cast: const [mira]);
    expect(result.cues, isEmpty);
    expect(result.containsDifferentPeople, isFalse);
  });

  test('scope beginning prevents using text from earlier chapter', () {
    const source = 'Mira left.\n\nShe entered a new chapter.';
    final secondChapter = source.indexOf('She');
    final result = search(source, 'She', scopeStart: secondChapter);
    expect(result.cues, isEmpty);
    expect(result.windowStart, secondChapter);
  });

  test('later book text can never become an antecedent cue', () {
    const text = 'She looked around. Mira arrived later.';
    final result = search(text, 'She');
    expect(result.cues, isEmpty);
    expect(result.windowEnd, 0);
  });

  test('bounded lookback ignores distant names and long excerpts', () {
    final source =
        'Mira talked.' +
        List.filled(NarrativeAntecedentFinder.maxLookback + 45, 'a').join() +
        ' She started walking.';
    final result = search(source, 'She');
    expect(result.cues, isEmpty);
    expect(result.windowEnd - result.windowStart,
      lessThanOrEqualTo(NarrativeAntecedentFinder.maxLookback));
  });

  test('accepted prior indirect link is shown but not a pending AI guess', () {
    const source = 'Mira walked. She waved. Her companion followed.';
    const priorText = 'She';
    final priorStart = source.indexOf(priorText);
    NarrativeReferenceCandidate prior(NarrativeReferenceStatus status) =>
        NarrativeReferenceCandidate(
          id: 'reviewed-1', bookId: 'book', start: priorStart,
          end: priorStart + priorText.length, referenceText: priorText,
          sourceDigest: CastSpan.digest(priorText),
          kind: NarrativeReferenceKind.pronoun, confidence: 0.55,
          proposedCharacterId: 'mira',
          approvedCharacterId: status == NarrativeReferenceStatus.accepted
              ? 'mira' : null,
          status: status,
        );
    final accepted = search(
      source, 'Her', cast: const [mira],
      accepted: [prior(NarrativeReferenceStatus.accepted)]);
    expect(accepted.cues, hasLength(1));
    expect(accepted.cues.single.matchedText, 'She');
    expect(accepted.cues.single.kind,
        AntecedentCueKind.reviewedNarrativeLink);
    final pending = search(
      source, 'Her', cast: const [mira],
      accepted: [prior(NarrativeReferenceStatus.proposed)]);
    expect(pending.cues.single.matchedText, 'Mira');
  });

  test('stale approved links are excluded; source fingerprint never lies',
      () {
    const source = 'Mira walked. She left.';
    const reference = 'She';
    final start = source.indexOf(reference);
    final reviewed = NarrativeReferenceCandidate(
      id: 'accepted', bookId: 'book', start: 0,
      end: 4, referenceText: 'Mira',
      sourceDigest: CastSpan.digest('Fake'),
      kind: NarrativeReferenceKind.titleOrDescription,
      confidence: 0.6, status: NarrativeReferenceStatus.accepted,
      approvedCharacterId: 'mira',
    );
    final cues = finder.inspect(
      bookId: 'book', source: source,
      scopeStart: 0, referenceStart: start, referenceEnd: start + 3,
      cast: const [mira], reviewedReferences: [reviewed],
    );
    expect(cues.cues, hasLength(1));
    expect(cues.cues.single.kind, AntecedentCueKind.explicitName);
    final forgedSource = source.replaceFirst('Mira', 'Nora');
    expect(cues.cues.single.matchesOriginal(forgedSource), isFalse);
  });

  test('Unicode and supplementary codepoint boundaries remain intact', () {
    const source = '😀 Mira 🐉 said hello. She smiled.';
    final hints = search(source, 'She', cast: const [mira]);
    expect(hints.cues, hasLength(1));
    final cue = hints.cues.single;
    expect(CastSpan.validUtf16Range(
        source, cue.contextStart, cue.contextEnd), isTrue);
    expect(cue.matchesOriginal(source), isTrue);
  });

  test('cross-book and duplicate cast identities are rejected', () {
    const source = 'Mira talked. She replied.';
    final at = source.indexOf('She');
    for (final roster in [
      const [CastCharacter(id: 'foreign', bookId: 'different', name: 'Mira')],
      const [mira, mira],
    ]) {
      expect(() => finder.inspect(
        bookId: 'book', source: source, scopeStart: 0,
        referenceStart: at, referenceEnd: at + 3, cast: roster,
      ), throwsFormatException);
    }
  });

  test('empty cast produces no verified antecedent even in named scene', () {
    const source = 'Mira said hello. She nodded.';
    final cues = search(source, 'She', cast: const []);
    expect(cues.cues, isEmpty);
  });
}
