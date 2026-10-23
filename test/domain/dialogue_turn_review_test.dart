import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/dialogue_turn_review.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = DialogueTurnReviewPlanner();
  const book = 'story';

  List<DialogueReviewTurn> parse(
    String text, {
    int from = 0,
    int? end,
    bool scopeEnd = true,
    List<CastSpan> precise = const [],
    List<SegmentCastAssignment> legacy = const [],
    int? Function(ReadingAnchor)? locate,
  }) => planner.build(
    bookId: book, source: text,
    from: from, to: end ?? text.length,
    reachesScopeEnd: scopeEnd,
    precise: precise, legacy: legacy,
    offsetFromAnchor: locate ?? (_) => null,
  );

  CastSpan label(String text, String phrase, String? speaker, {
    CastSpanStatus status = CastSpanStatus.accepted,
    bool locked = true,
    String sourceBook = book,
    ReadingAnchor? anchor,
  }) {
    final at = text.indexOf(phrase);
    expect(at, greaterThanOrEqualTo(0));
    return CastSpan(
      id: phrase + (speaker ?? 'narrator'),
      bookId: sourceBook, start: at, end: at + phrase.length,
      sourceDigest: CastSpan.digest(phrase), speakerId: speaker,
      origin: locked && status == CastSpanStatus.accepted
          ? CastSpanOrigin.user : CastSpanOrigin.llm,
      status: status, lockedByUser: locked, anchor: anchor,
    );
  }

  test('separate sequential quoted turns and preserve all original offsets',
      () {
    const text = 'Mira: «Ciao!» Anna: “Pronto?” disse. "Bye".';
    final turns = parse(text);
    expect(turns, hasLength(3));
    expect(turns.map((t) => t.delimiter), [
      DialogueDelimiter.guillemets,
      DialogueDelimiter.curlyQuotes,
      DialogueDelimiter.doubleQuotes,
    ]);
    expect(turns.map((t) => t.text), ['«Ciao!»', '“Pronto?”', '"Bye"']);
    for (final turn in turns) {
      expect(text.substring(turn.start, turn.end), turn.text);
      expect(turn.ending, DialogueEnd.complete);
      expect(turn.hasUnknown, isTrue);
    }
  });

  test('dash-led turn boundaries and interrupted trailing dash are distinct',
      () {
    const text = '— Prima battuta\n— Aspetta—\nIl narratore risponde.';
    final turns = parse(text);
    expect(turns, hasLength(2));
    expect(turns.map((t) => t.delimiter),
        [DialogueDelimiter.dashLine, DialogueDelimiter.dashLine]);
    expect(turns[0].ending, DialogueEnd.complete);
    expect(turns[1].ending, DialogueEnd.interrupted);
    expect(turns[1].text, '— Aspetta—');
  });

  test('ellipses and em dash before closer mark interruptions, not identities',
      () {
    const text = '«Io…» «Non posso—» «Finito.»';
    final turns = parse(text);
    expect(turns.map((t) => t.ending), [
      DialogueEnd.interrupted,
      DialogueEnd.interrupted,
      DialogueEnd.complete,
    ]);
    expect(turns.every((t) => t.hasUnknown), isTrue);
  });

  test('unclosed quote or truncated review window is never complete', () {
    const text = '«Non lo so. Sono ancora qui';
    expect(parse(text).single.ending, DialogueEnd.openOrTruncated);
    const truncated = '«Longer line» the rest of this passage.';
    final end = truncated.indexOf('»');
    final turns = parse(truncated, end: end, scopeEnd: false);
    expect(turns.single.ending, DialogueEnd.openOrTruncated);
    expect(turns.single.text, truncated.substring(0, end));
  });

  test('partial precise label preserves unknown source on both sides', () {
    const text = '«Ciao, aspetta qui!»';
    final span = label(text, 'aspetta', 'mira');
    final turn = parse(text, precise: [span]).single;
    expect(turn.isPartiallyAttributed, isTrue);
    expect(turn.fullyAttributed, isFalse);
    expect(turn.labels.any((p) => p.state == DialogueLabelState.confirmed),
        isTrue);
    expect(turn.labels.any((p) => p.state == DialogueLabelState.unknown),
        isTrue);
    for (final piece in turn.labels) {
      expect(text.substring(piece.start, piece.end).trim(), isNotEmpty);
    }
  });

  test('two separately confirmed parts of one quote reveal speaker switch',
      () {
    const text = '«Prima parte, seconda parte.»';
    final first = label(text, 'Prima parte', 'mira');
    final second = label(text, 'seconda parte', 'anna');
    final turn = parse(text, precise: [first, second]).single;
    expect(turn.hasMultipleConfirmedSpeakers, isTrue);
    expect(turn.hasUnknown, isTrue); // punctuation and quotes unlabelled
    expect(turn.hasConflicts, isFalse);
  });

  test('overlapping disagreeing labels are explicitly conflict, not winner',
      () {
    const text = '«Ciao, amica!»';
    final first = label(text, 'Ciao, amica', 'mira');
    final second = label(text, 'amica', 'anna');
    final turn = parse(text, precise: [first, second]).single;
    expect(turn.hasConflicts, isTrue);
    expect(turn.labels.where((p) => p.state == DialogueLabelState.conflict),
        isNotEmpty);
    expect(turn.fullyAttributed, isFalse);
  });

  test('explicit narrator/unknown manual selection differs from missing',
      () {
    const text = '«La voce fuori campo.»';
    final narrator = label(text, text, null);
    final turn = parse(text, precise: [narrator]).single;
    expect(turn.labels.map((p) => p.state),
        [DialogueLabelState.narrator]);
    expect(turn.fullyAttributed, isTrue);
    expect(turn.hasUnknown, isFalse);
  });

  test('legacy source hash must be exact and can complete whole quote',
      () {
    const text = '«The bell rang!» She listened.';
    final quote = '«The bell rang!»';
    final old = SegmentCastAssignment(
      bookId: book, start: 0, end: quote.length,
      sourceDigest: SegmentCastAssignment.fingerprint(quote),
      characterId: 'mira');
    final fresh = parse(text, legacy: [old]).single;
    expect(fresh.fullyAttributed, isTrue);
    expect(fresh.labels.single.speakerId, 'mira');
    final invalid = SegmentCastAssignment(
      bookId: book, start: 0, end: quote.length,
      sourceDigest: SegmentCastAssignment.fingerprint('Different!'),
      characterId: 'mira');
    expect(parse(text, legacy: [invalid]).single.hasUnknown, isTrue);
  });

  test('LLM pending, unlocked and other-book annotations are ignored', () {
    const text = '«Attenzione!»';
    final pending = label(text, text, 'mira',
      status: CastSpanStatus.proposed, locked: false);
    final foreign = label(text, text, 'mira', sourceBook: 'other');
    expect(parse(text, precise: [pending, foreign]).single.hasUnknown, isTrue);
  });

  test('anchored precise labels use resolved position and text fingerprints',
      () {
    const text = 'Intro. «Oggi!»';
    const anchor = ReadingAnchor(
      kind: AnchorKind.text, sourceId: 'book', localOffset: 0);
    final labelFromOldExtraction = CastSpan(
      id: 'moved', bookId: book, start: 80,
      end: 80 + '«Oggi!»'.length,
      sourceDigest: CastSpan.digest('«Oggi!»'),
      speakerId: 'anna', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
      anchor: anchor);
    final resolved = parse(text, precise: [labelFromOldExtraction],
        locate: (_) => text.indexOf('«'));
    expect(resolved.single.fullyAttributed, isTrue);
    expect(resolved.single.labels.single.speakerId, 'anna');
    expect(parse(text, precise: [labelFromOldExtraction]).single.hasUnknown,
        isTrue);
  });

  test('emoji offsets and separate quote delimiting are UTF-16 safe', () {
    const text = '🐉 «Ciao 😀» e «Ancora!»';
    final turns = parse(text);
    expect(turns, hasLength(2));
    for (final t in turns) {
      expect(CastSpan.validUtf16Range(text, t.start, t.end), isTrue);
      expect(t.text, text.substring(t.start, t.end));
    }
    final emojiAt = text.indexOf('😀');
    expect(() => parse(text, from: emojiAt + 1), throwsFormatException);
  });

  test('window cannot exceed fixed cap or inspect malformed source ranges',
      () {
    final tooLong = List.filled(DialogueTurnReviewPlanner.maxWindowChars + 1,
        'a').join();
    expect(() => parse(tooLong), throwsFormatException);
    expect(() => parse('Hello', from: -1), throwsFormatException);
    expect(() => parse('Hello', end: 100), throwsFormatException);
  });

  test('truncated dash line signals incomplete window without auto speaker',
      () {
    const source = '— The unfinished sentence keeps going.';
    final windowEnd = source.indexOf('keeps');
    final turns = parse(source, end: windowEnd, scopeEnd: false);
    expect(turns.single.ending, DialogueEnd.openOrTruncated);
    expect(turns.single.labels.single.state, DialogueLabelState.unknown);
  });
}
