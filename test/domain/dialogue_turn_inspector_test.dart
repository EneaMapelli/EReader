import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/dialogue_turn_inspector.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const inspector = DialogueTurnInspector();
  const mira = CastCharacter(id: 'mira', bookId: 'book', name: 'Mira');
  const anna = CastCharacter(id: 'anna', bookId: 'book', name: 'Anna');

  CastSpan label(String source, String quote, String? speaker, {
    CastSpanStatus status = CastSpanStatus.accepted,
    String bookId = 'book',
    String? fakeDigest,
    ReadingAnchor? anchor,
  }) {
    final at = source.indexOf(quote);
    expect(at, greaterThanOrEqualTo(0));
    return CastSpan(
      id: 'label-' + at.toString() + '-' + (speaker ?? 'narrator'),
      bookId: bookId, start: at, end: at + quote.length,
      sourceDigest: fakeDigest ?? CastSpan.digest(quote),
      speakerId: speaker,
      origin: status == CastSpanStatus.accepted
          ? CastSpanOrigin.user : CastSpanOrigin.llm,
      status: status,
      lockedByUser: status == CastSpanStatus.accepted,
      anchor: anchor,
    );
  }

  DialogueTurnReport check(String source, {
    List<CastSpan> fine = const [],
    List<SegmentCastAssignment> old = const [],
    List<CastCharacter> cast = const [mira, anna],
    int start = 0,
    int? end,
    int? Function(ReadingAnchor)? resolve,
  }) => inspector.inspect(
    bookId: 'book', source: source,
    scopeStart: start, scopeEnd: end ?? source.length,
    characters: cast, fineLabels: fine, legacyLabels: old,
    offsetFromAnchor: resolve ?? (_) => null,
  );

  test('quoted turns keep source text/offsets without inventing speakers',
      () {
    const source = 'Mira disse: «Vai!» Anna rispose: «No!»';
    final report = check(source);
    expect(report.turns.map((t) => t.text), ['«Vai!»', '«No!»']);
    expect(report.turns.every((t) => t.matchesSource(source)), isTrue);
    expect(report.turns.every((t) =>
        t.flags.contains(DialogueTurnFlag.missingAttribution)), isTrue);
    expect(report.turns.every((t) => t.speakerId == null), isTrue);
    expect(report.turns.last.flags, contains(DialogueTurnFlag.adjacentTurn));
  });

  test('two independently approved turns can have different speakers',
      () {
    const source = '«Ciao!» Mira rispose. «No!» Anna gridò.';
    final report = check(source, fine: [
      label(source, '«Ciao!»', 'mira'),
      label(source, '«No!»', 'anna'),
    ]);
    expect(report.turns.map((t) => t.speakerId), ['mira', 'anna']);
    expect(report.turns.every((t) =>
        t.attribution == DialogueAttributionState.confirmed), isTrue);
    expect(report.turns.last.flags, contains(DialogueTurnFlag.adjacentTurn));
  });

  test('unfinished quote is flagged without synthesizing a closing mark',
      () {
    const source = 'Mira disse: «Non andare';
    final report = check(source);
    expect(report.turns, hasLength(1));
    expect(report.turns.single.closed, isFalse);
    expect(report.turns.single.flags,
      contains(DialogueTurnFlag.unclosedQuote));
    expect(report.turns.single.text, '«Non andare');
    expect(report.turns.single.matchesSource(source), isTrue);
  });

  test('interrupted and trailing-off lines are marked for human review',
      () {
    const source = '«Non posso—» disse lui. «Aspetta…» gridò lei.';
    final report = check(source);
    expect(report.turns, hasLength(2));
    for (final turn in report.turns) {
      expect(turn.flags, contains(DialogueTurnFlag.interruptedUtterance));
    }
  });

  test('multiline quoted dialogue is flagged without dropping characters',
      () {
    const source = '«Prima riga\nseconda riga» disse Mira.';
    final report = check(source);
    expect(report.turns.single.flags,
        contains(DialogueTurnFlag.multilineQuote));
    expect(report.turns.single.text,
        '«Prima riga\nseconda riga»');
  });

  test('partially attributed quote is not credited as fully confirmed',
      () {
    const source = '«Buongiorno, Anna!» disse Mira.';
    final report = check(source, fine: [
      label(source, 'Buongiorno', 'mira'),
    ]);
    expect(report.turns.single.attribution,
        DialogueAttributionState.partial);
    expect(report.turns.single.speakerId, isNull);
    expect(report.turns.single.flags,
        contains(DialogueTurnFlag.partialAttribution));
  });

  test('two adjacent precise labels may jointly cover one turn', () {
    const source = '«Ciao!»';
    final report = check(source, fine: [
      label(source, '«Cia', 'mira'),
      label(source, 'o!»', 'mira'),
    ]);
    expect(report.turns.single.attribution,
        DialogueAttributionState.confirmed);
    expect(report.turns.single.speakerId, 'mira');
  });

  test('overlapping different accepted people produce a conflict, not winner',
      () {
    const source = '«Vieni subito!»';
    final report = check(source, fine: [
      label(source, '«Vieni subito!»', 'mira'),
      label(source, 'subito', 'anna'),
    ]);
    expect(report.turns.single.attribution,
        DialogueAttributionState.conflicting);
    expect(report.turns.single.speakerId, isNull);
    expect(report.turns.single.flags,
        contains(DialogueTurnFlag.conflictingAttributions));
  });

  test('explicit narrator/unknown is distinct from missing attribution',
      () {
    const source = '«Nessuno sa»';
    final report = check(source, fine: [
      label(source, source, null),
    ]);
    expect(report.turns.single.attribution,
        DialogueAttributionState.narrator);
    expect(report.turns.single.flags,
        contains(DialogueTurnFlag.explicitNarrator));
    expect(report.turns.single.flags,
        isNot(contains(DialogueTurnFlag.missingAttribution)));
  });

  test('pending and stale annotations do not become authoritative', () {
    const source = '«Vai!»';
    final report = check(source, fine: [
      label(source, source, 'mira', status: CastSpanStatus.proposed),
      label(source, source, 'anna',
        fakeDigest: CastSpan.digest('different')),
    ]);
    expect(report.turns.single.speakerId, isNull);
    expect(report.turns.single.attribution,
        DialogueAttributionState.none);
  });

  test('legacy source-exact manual segments count but stale ones do not',
      () {
    const source = 'Mira disse: «Basta!»';
    final at = source.indexOf('«Basta!»');
    SegmentCastAssignment make(String hash) => SegmentCastAssignment(
      bookId: 'book', start: at,
      end: at + '«Basta!»'.length,
      sourceDigest: hash, characterId: 'mira',
    );
    expect(check(source, old: [
      make(SegmentCastAssignment.fingerprint('«Basta!»')),
    ]).turns.single.speakerId, 'mira');
    expect(check(source, old: [
      make(SegmentCastAssignment.fingerprint('irrelevant')),
    ]).turns.single.speakerId, isNull);
  });

  test('surrogate pairs remain unmodified at quoted boundaries', () {
    const source = '😀 «Salve 🐉!» Anna salutò.';
    final report = check(source, fine: [
      label(source, '«Salve 🐉!»', 'anna'),
    ]);
    expect(report.turns.single.speakerId, 'anna');
    expect(report.turns.single.matchesSource(source), isTrue);
    expect(CastSpan.validUtf16Range(source,
      report.turns.single.start, report.turns.single.end), isTrue);
  });

  test('long scope cutoff does not pretend an interrupted quote is unclosed',
      () {
    final prefix = List.filled(
        DialogueTurnInspector.maxScanChars - 18, 'x').join();
    final source = prefix + ' «Starts here and continues beyond cutoff ' +
        List.filled(250, 'q').join() + '»';
    final report = check(source);
    expect(report.truncated, isTrue);
    expect(report.turns, hasLength(1));
    expect(report.turns.single.closed, isFalse);
    expect(report.turns.single.flags,
        contains(DialogueTurnFlag.scanBoundary));
    expect(report.turns.single.flags,
        isNot(contains(DialogueTurnFlag.unclosedQuote)));
  });

  test('scope and read cap prevent future quote inspection', () {
    const source = '«Old»\n\n«Current»\n\n«Future»';
    final from = source.indexOf('«Current»');
    final to = from + '«Current»'.length;
    final report = check(source, start: from, end: to);
    expect(report.turns.map((t) => t.text), ['«Current»']);
    expect(report.scannedStart, from);
    expect(report.scannedEnd, to);
  });

  test('invalid source scope and foreign cast are refused', () {
    const source = '«Hello!»';
    expect(() => check(source, start: 0, end: source.length + 2),
        throwsFormatException);
    expect(() => check(source, cast: const [
      CastCharacter(id: 'other', bookId: 'different', name: 'Visitor'),
    ]), throwsFormatException);
  });

  test('ASCII double quotes are separate turns, not implicit same voice',
      () {
    const source = 'He said "Go." She answered "No."';
    final report = check(source);
    expect(report.turns.map((t) => t.text), ['"Go."', '"No."']);
    expect(report.turns.every((t) => t.speakerId == null), isTrue);
  });
}
