import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/conversation_speaker_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const inspector = ConversationSpeakerInspector();
  const mira = CastCharacter(id: 'mira', bookId: 'book', name: 'Mira');
  const anna = CastCharacter(id: 'anna', bookId: 'book', name: 'Anna');

  CastSpan span(
    String source, String quote, String person, {
    CastSpanStatus status = CastSpanStatus.accepted,
    String bookId = 'book',
    ReadingAnchor? anchor,
  }) {
    final start = source.indexOf(quote);
    expect(start, greaterThanOrEqualTo(0));
    return CastSpan(
      id: person + ':' + quote,
      bookId: bookId, start: start, end: start + quote.length,
      sourceDigest: CastSpan.digest(quote),
      speakerId: person, origin: status == CastSpanStatus.proposed
        ? CastSpanOrigin.llm : CastSpanOrigin.user,
      status: status, lockedByUser: status == CastSpanStatus.accepted,
      anchor: anchor,
    );
  }

  ConversationSpeakerInspection inspect(
    String source, String marker, {
    int scopeStart = 0,
    List<CastSpan> fine = const [],
    List<SegmentCastAssignment> legacy = const [],
    List<CastCharacter> cast = const [mira, anna],
    int? Function(ReadingAnchor)? locate,
  }) {
    final from = source.lastIndexOf(marker);
    expect(from, greaterThanOrEqualTo(0));
    return inspector.inspect(
      bookId: 'book', source: source,
      scopeStart: scopeStart,
      referenceStart: from, referenceEnd: from + marker.length,
      cast: cast, reviewedSpans: fine, manualSegments: legacy,
      offsetFromAnchor: locate ?? (_) => null,
    );
  }

  test('two preceding speakers remain distinct, not proposed referents', () {
    const text = '«Welcome» Mira said. «Go!» Anna replied. She frowned.';
    final first = span(text, '«Welcome»', 'mira');
    final second = span(text, '«Go!»', 'anna');
    final got = inspect(text, 'She', fine: [first, second]);
    expect(got.turns, hasLength(2));
    expect(got.turns.map((t) => t.speakerId), ['anna', 'mira']);
    expect(got.hasMultipleSpeakers, isTrue);
    expect(got.conflictingLabels, isFalse);
    expect(got.turns.every((t) => t.matchesSource(text)), isTrue);
    expect(got.turns.every((t) => t.end <= text.indexOf('She')), isTrue);
  });

  test('a nominally accepted but non-locked label is never trusted', () {
    const text = '«Perhaps» She answered.';
    final unsafe = CastSpan(
      id: 'not-reviewed', bookId: 'book',
      start: 0, end: '«Perhaps»'.length,
      sourceDigest: CastSpan.digest('«Perhaps»'),
      speakerId: 'mira', origin: CastSpanOrigin.llm,
      status: CastSpanStatus.accepted, lockedByUser: false,
    );
    final got = inspect(text, 'She', fine: [unsafe]);
    expect(got.turns, isEmpty);
  });

  test('pending LLM speaker guesses never enter confirmed dialogue', () {
    const text = '«Hello» he guessed. She nodded.';
    final guess = span(text, '«Hello»', 'mira',
      status: CastSpanStatus.proposed);
    final got = inspect(text, 'She', fine: [guess]);
    expect(got.turns, isEmpty);
  });

  test('stale hashes and future voice labels are never shown', () {
    const text = '«Old» Mira said. She left. «Later» Anna replied.';
    final wrong = CastSpan(
      id: 'wrong', bookId: 'book',
      start: 0, end: 5,
      sourceDigest: CastSpan.digest('Other'),
      speakerId: 'mira', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true);
    final later = span(text, '«Later»', 'anna');
    final got = inspect(text, 'She', fine: [wrong, later]);
    expect(got.turns, isEmpty);
  });

  test('a currently speaking character does not become pronoun referent',
      () {
    const text = '«She is not here», said Mira.';
    final speakingLabel = span(text, '«She is not here»', 'mira');
    // The label legitimately describes the SPEAKER of this ongoing quote.
    // Because it has not ended before the pronoun, it is not a historical
    // antecedent, nor permission to infer who "She" refers to.
    final review = inspect(text, 'She', fine: [speakingLabel]);
    expect(review.turns, isEmpty);
    expect(review.conflictingLabels, isFalse);
  });

  test('manual legacy segment is accepted only with exact source digest', () {
    const text = 'Mira: «Stop!» Then she turned.';
    final start = text.indexOf('«Stop!»');
    SegmentCastAssignment legacy(String hash) => SegmentCastAssignment(
      bookId: 'book',
      start: start, end: start + '«Stop!»'.length,
      sourceDigest: hash, characterId: 'mira');
    final verified = inspect(text, 'she',
      legacy: [legacy(SegmentCastAssignment.fingerprint('«Stop!»'))]);
    expect(verified.turns.single.origin,
        ConversationTurnOrigin.manualSegment);
    final rejected = inspect(text, 'she',
      legacy: [legacy(SegmentCastAssignment.fingerprint('Fake'))]);
    expect(rejected.turns, isEmpty);
  });

  test('a precise and a legacy label for the same words are deduplicated',
      () {
    const text = '«Hello!» She said.';
    final quote = '«Hello!»';
    final fine = span(text, quote, 'mira');
    final old = SegmentCastAssignment(
      bookId: 'book', start: 0, end: quote.length,
      sourceDigest: SegmentCastAssignment.fingerprint(quote),
      characterId: 'mira');
    final got = inspect(text, 'She', fine: [fine], legacy: [old]);
    expect(got.turns, hasLength(1));
    expect(got.turns.single.origin, ConversationTurnOrigin.reviewedSpan);
  });

  test('conflicting accepted labels on overlapping words are both hidden',
      () {
    const text = '«Hello, stop!» He whispered.';
    final first = span(text, '«Hello, stop!»', 'mira');
    final second = span(text, 'stop', 'anna');
    final got = inspect(text, 'He', fine: [first, second]);
    expect(got.conflictingLabels, isTrue);
    expect(got.turns, isEmpty);
  });

  test('prior scope and future material are excluded', () {
    const text = '«Before»\n\nShe talked. «After»';
    final scopeStart = text.indexOf('She');
    final first = span(text, '«Before»', 'mira');
    final future = span(text, '«After»', 'anna');
    final got = inspect(text, 'She',
      scopeStart: scopeStart, fine: [first, future]);
    expect(got.turns, isEmpty);
    expect(got.lookbackStart, scopeStart);
  });

  test('anchors must resolve to source accurate original quotes', () {
    const text = '«Anchor» He replied.';
    final at = text.indexOf('«Anchor»');
    const anchor = ReadingAnchor(
      kind: AnchorKind.text, sourceId: 'book', localOffset: 2);
    final good = CastSpan(
      id: 'anchored', bookId: 'book', start: 100,
      end: 100 + '«Anchor»'.length,
      sourceDigest: CastSpan.digest('«Anchor»'),
      speakerId: 'mira', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
      anchor: anchor);
    final yes = inspect(text, 'He', fine: [good],
      locate: (_) => at);
    expect(yes.turns.single.excerpt, '«Anchor»');
    final no = inspect(text, 'He', fine: [good],
      locate: (_) => null);
    expect(no.turns, isEmpty);
  });

  test('long utterance preview truncated but retains source fingerprint',
      () {
    final quote = '«' +
        List.filled(ConversationSpeakerInspector.maxExcerptCharacters + 25,
          'w').join() + '»';
    final text = quote + ' She listened.';
    final got = inspect(text, 'She', fine: [span(text, quote, 'mira')]);
    expect(got.turns, hasLength(1));
    final cue = got.turns.single;
    expect(cue.excerpt.length,
        lessThanOrEqualTo(ConversationSpeakerInspector.maxExcerptCharacters));
    expect(cue.attributionStart, 0);
    expect(cue.attributionEnd, quote.length);
    expect(cue.matchesSource(text), isTrue);
  });

  test('foreign book, unknown speaker and duplicate cast identities fail safe',
      () {
    const text = '«Hi» He answered.';
    final wrongBook = span(text, '«Hi»', 'mira', bookId: 'other');
    final unknown = span(text, '«Hi»', 'unknown');
    expect(inspect(text, 'He', fine: [wrongBook, unknown]).turns, isEmpty);
    expect(() => inspect(text, 'He', cast: const [mira, mira]),
        throwsFormatException);
    expect(() => inspect(text, 'He',
      cast: const [
        CastCharacter(id: 'foreign', bookId: 'another', name: 'Visitor'),
      ]), throwsFormatException);
  });

  test('empty cast and no accepted turns never imply the narrator spoke',
      () {
    const text = '«Something» She replied.';
    final got = inspect(text, 'She', cast: const [], fine: const []);
    expect(got.turns, isEmpty);
    expect(got.hasMultipleSpeakers, isFalse);
    expect(got.conflictingLabels, isFalse);
  });
}
