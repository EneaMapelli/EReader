import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:flutter_test/flutter_test.dart';

const bookId = 'book-1';

CastSpan accepted(
  String source, int start, int end, String? speaker, {
  ReadingAnchor? anchor,
}) => CastSpan(
  id: 'confirmed-' + start.toString(),
  bookId: bookId,
  start: start, end: end,
  sourceDigest: CastSpan.digest(source.substring(start, end)),
  speakerId: speaker, origin: CastSpanOrigin.user,
  status: CastSpanStatus.accepted, lockedByUser: true, anchor: anchor,
);

SegmentCastAssignment legacy(
  String source, int start, int end, {
  String speaker = 'mira',
  ReadingAnchor? anchor,
}) => SegmentCastAssignment(
  bookId: bookId,
  start: start, end: end, characterId: speaker,
  sourceDigest: SegmentCastAssignment.fingerprint(
      source.substring(start, end)),
  anchor: anchor,
);

({PreparedCastSpeech prepared, PreparedCastSpeech coalesced,
    List<QuotedSpeechChunk> quoteParts}) plan(
  String source, {
  List<CastSpan> labels = const [],
  List<SegmentCastAssignment> old = const [],
  int baseMax = 22,
  int coalesceMax = 400,
  int? Function(ReadingAnchor)? locate,
}) {
  final quoted = splitQuotedSegmentsWithRegions(
    segmentSpeech(source, maxChars: baseMax),
  );
  final prepared = prepareCastSpeech(
    source: source,
    base: [for (final part in quoted) part.segment],
    annotations: labels,
    legacyAssignments: old,
    bookId: bookId,
    knownCharacterIds: {'mira', 'anna'},
    offsetFromAnchor: locate ?? (_) => null,
  );
  return (
    quoteParts: quoted,
    prepared: prepared,
    coalesced: coalesceQuotedSpeech(
      source: source,
      chunks: prepared.segments,
      quotedChunks: quoted,
      speakerByStart: prepared.speakerByStart,
      maxChars: coalesceMax,
    ),
  );
}

void main() {
  const story = 'Mira said: «First sentence. Another sentence. '
      'A third sentence.» Then the narrator replied.';
  final from = story.indexOf('«');
  final to = story.indexOf('»') + 1;

  // Narrator speech remains source-exact and unlabelled even when the
  // fixed-size TTS chunker splits it into several utterances. The last
  // chunk is not obliged to contain the entire narrator sentence.
  void expectNarratorTail(PreparedCastSpeech speech) {
    final narrator = speech.segments.where((chunk) =>
        chunk.start >= to).toList();
    expect(narrator, isNotEmpty);
    expect(story.substring(narrator.first.start, narrator.last.end),
        story.substring(to).trim());
    for (var i = 0; i < narrator.length; i++) {
      final chunk = narrator[i];
      expect(story.substring(chunk.start, chunk.end), chunk.text);
      expect(speech.speakerByStart.containsKey(chunk.start), isFalse,
          reason: 'A finished character turn must never label a '
              'later narrator chunk');
      if (i > 0) {
        expect(story.substring(narrator[i - 1].end, chunk.start).trim(),
            isEmpty, reason: 'Narration may skip whitespace, not words');
      }
    }
  }

  test('one approved long quote retains voice across multiple TTS chunks', () {
    final result = plan(story, labels: [accepted(story, from, to, 'mira')]);
    final quoteChunks = result.prepared.segments.where(
        (chunk) => chunk.start >= from && chunk.end <= to).toList();
    expect(quoteChunks.length, greaterThan(1));
    for (final chunk in quoteChunks) {
      expect(result.prepared.speakerByStart[chunk.start], 'mira');
    }
    expect(result.coalesced.segments.any(
      (chunk) => chunk.start == from && chunk.end == to &&
          chunk.text == story.substring(from, to)), isTrue);
    expect(result.coalesced.speakerByStart[from], 'mira');
    for (final chunk in result.coalesced.segments) {
      expect(story.substring(chunk.start, chunk.end), chunk.text);
    }
    expectNarratorTail(result.coalesced);
  });

  test('legacy whole-quote tag survives new segment boundaries', () {
    final result = plan(story, old: [legacy(story, from, to)]);
    final before = result.prepared.segments.where(
        (chunk) => chunk.start >= from && chunk.end <= to).toList();
    expect(before.length, greaterThan(1));
    expect(before.every((chunk) =>
        result.prepared.speakerByStart[chunk.start] == 'mira'), isTrue);
    expect(result.coalesced.speakerByStart[from], 'mira');
  });

  test('explicit narrator mask splits a legacy tagged quote exactly', () {
    final start = story.indexOf('Another');
    final end = start + 'Another sentence.'.length;
    final result = plan(story, old: [legacy(story, from, to)],
        labels: [accepted(story, start, end, null)]);
    final marked = result.coalesced.segments.firstWhere(
        (chunk) => chunk.start == start);
    expect(marked.text, 'Another sentence.');
    expect(result.coalesced.speakerByStart.containsKey(marked.start), isTrue);
    expect(result.coalesced.speakerByStart[marked.start], isNull);
    expect(result.coalesced.segments.firstWhere(
        (chunk) => chunk.start == from).end, lessThanOrEqualTo(start));
    expect(result.coalesced.segments.any((chunk) =>
        chunk.start >= end &&
        result.coalesced.speakerByStart[chunk.start] == 'mira'), isTrue);
  });

  test('another confirmed speaker takes priority over legacy source range',
      () {
    final start = story.indexOf('Another');
    final end = start + 'Another sentence.'.length;
    final result = plan(story, old: [legacy(story, from, to)],
      labels: [accepted(story, start, end, 'anna')]);
    expect(result.coalesced.speakerByStart[start], 'anna');
    expect(result.coalesced.speakerByStart[from], 'mira');
    expect(result.coalesced.segments.any((chunk) =>
        chunk.start > end &&
        result.coalesced.speakerByStart[chunk.start] == 'mira'), isTrue);
  });

  test('unknown tags are never inherited across quote/narrator boundaries',
      () {
    final result = plan(story, baseMax: 22);
    final groups = result.quoteParts
        .where((chunk) => chunk.quoteGroup != null)
        .map((chunk) => chunk.quoteGroup).toSet();
    expect(groups.length, 1);
    expect(result.coalesced.segments.first.text,
        isNot(contains('First sentence')));
    expectNarratorTail(result.coalesced);
    expect(result.coalesced.speakerByStart, isEmpty);
  });

  test('two confirmed turns have separate voices with narrator between',
      () {
    const source =
        '«Hello from Mira.» The narrator paused. '
        '«Hello from Anna.» Then the narrator continued.';
    final first = source.indexOf('«');
    final firstEnd = source.indexOf('»') + 1;
    final second = source.lastIndexOf('«');
    final secondEnd = source.lastIndexOf('»') + 1;
    final result = plan(source, baseMax: 18, labels: [
      accepted(source, first, firstEnd, 'mira'),
      accepted(source, second, secondEnd, 'anna'),
    ]);
    final actual = result.coalesced;
    expect(actual.speakerByStart[first], 'mira');
    expect(actual.speakerByStart[second], 'anna');
    expect(actual.segments.any((chunk) =>
        chunk.start == first && chunk.end == firstEnd), isTrue);
    expect(actual.segments.any((chunk) =>
        chunk.start == second && chunk.end == secondEnd), isTrue);

    for (final chunk in actual.segments) {
      expect(chunk.text, source.substring(chunk.start, chunk.end));
      if (chunk.start >= firstEnd && chunk.end <= second) {
        expect(actual.speakerByStart.containsKey(chunk.start), isFalse,
            reason: 'Intervening narration cannot inherit Mira');
      }
      if (chunk.start >= secondEnd) {
        expect(actual.speakerByStart.containsKey(chunk.start), isFalse,
            reason: 'Final narration cannot inherit Anna');
      }
    }
    expect(source.substring(firstEnd, second),
        contains('The narrator paused.'));
    expect(source.substring(secondEnd),
        contains('Then the narrator continued.'));
  });

  test('more than provider chunk limit stays split but every part cast',
      () {
    final quoted = '«' +
        List.filled(230, 'word').join(' ') + '»';
    final source = 'Start. ' + quoted + ' End.';
    final a = source.indexOf('«');
    final b = source.indexOf('»') + 1;
    final result = plan(source,
      baseMax: 80, coalesceMax: 400,
      labels: [accepted(source, a, b, 'mira')]);
    final spoken = result.coalesced.segments.where(
        (chunk) => chunk.start >= a && chunk.end <= b).toList();
    expect(spoken.length, greaterThan(1));
    expect(spoken.every((chunk) => chunk.text.length <= 400), isTrue);
    expect(spoken.every((chunk) =>
        result.coalesced.speakerByStart[chunk.start] == 'mira'), isTrue);
  });

  test('invalid source fingerprints or wrong book never propagate voices',
      () {
    final stale = SegmentCastAssignment(
      bookId: bookId, start: from, end: to, characterId: 'mira',
      sourceDigest: SegmentCastAssignment.fingerprint('invented'),
    );
    final foreign = SegmentCastAssignment(
      bookId: 'other-book', start: from, end: to, characterId: 'mira',
      sourceDigest: SegmentCastAssignment.fingerprint(
          story.substring(from, to)),
    );
    final unknown = legacy(story, from, to, speaker: 'unlisted');
    expect(plan(story, old: [stale, foreign, unknown])
        .coalesced.speakerByStart, isEmpty);
  });

  test('overlapping legacy records are dropped rather than guessed', () {
    final shorter = legacy(story, from + 1, to - 1, speaker: 'anna');
    final result = plan(story, old: [
      legacy(story, from, to), shorter,
    ]);
    expect(result.coalesced.speakerByStart, isEmpty);
  });

  test('relocated chapter anchor resolves source-hashed legacy range', () {
    const original = 'A «Short talk. Then more talk.»';
    const current = 'A longer preface. «Short talk. Then more talk.»';
    final a = original.indexOf('«');
    final b = original.indexOf('»') + 1;
    final newer = current.indexOf('«');
    const anchor = ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'chapter-a', localOffset: 0);
    final result = plan(current, baseMax: 18,
      old: [legacy(original, a, b, anchor: anchor)],
      locate: (_) => newer);
    expect(result.coalesced.speakerByStart[newer], 'mira');
    expect(plan(current, baseMax: 18,
      old: [legacy(original, a, b, anchor: anchor)])
        .coalesced.speakerByStart, isEmpty);
  });

  test('different quote groups are never merged into one TTS utterance', () {
    const source = '«First.» «Second.»';
    final result = plan(source);
    expect(result.coalesced.segments.map((p) => p.text),
        ['«First.»', '«Second.»']);
  });

  test('UTF-16 emoji remain complete when joining quote pieces', () {
    const source = 'She said «Hello 🐉 friend. And 😀 again.» quickly.';
    final qstart = source.indexOf('«');
    final qend = source.indexOf('»') + 1;
    final result = plan(source, baseMax: 18,
        labels: [accepted(source, qstart, qend, 'mira')]);
    for (final seg in result.coalesced.segments) {
      expect(CastSpan.validUtf16Range(source, seg.start, seg.end), isTrue);
      expect(seg.text, source.substring(seg.start, seg.end));
    }
  });

  test('disputed precise voices cannot revive a legacy character voice',
      () {
    const source = '«One voice and another voice are overlapping.»';
    final start = source.indexOf('voice');
    final first = accepted(source, start, start + 'voice and another'.length,
        'mira');
    final second = accepted(source, start + 'voice and '.length,
        start + 'voice and another voice'.length, 'anna');
    final result = plan(source,
      old: [legacy(source, 0, source.length)],
      labels: [first, second]);
    final disputedChunks = result.coalesced.segments.where(
      (chunk) => chunk.start >= first.start &&
          chunk.end <= second.end).toList();
    expect(disputedChunks, isNotEmpty);
    expect(disputedChunks.every((chunk) =>
        result.coalesced.speakerByStart[chunk.start] == null), isTrue);
  });


}
