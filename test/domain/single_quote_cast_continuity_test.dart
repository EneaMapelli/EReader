import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void _assertSourceExact(String source, List<SpeechSegment> chunks) {
  var lastEnd = 0;
  for (final chunk in chunks) {
    expect(chunk.start, greaterThanOrEqualTo(lastEnd));
    expect(source.substring(chunk.start, chunk.end), chunk.text);
    lastEnd = chunk.end;
  }
}

void main() {
  test('approved curly single dialogue persists across TTS chunk boundaries',
      () {
    final quoted = '‘' +
        List.filled(18, 'I’m staying right here').join(' ') + '.’';
    final source = 'A narrator began. ' + quoted + ' She then left.';
    final start = source.indexOf('‘');
    final end = start + quoted.length;
    final base = segmentSpeech(source, maxChars: 36);
    final pieces = splitQuotedSegmentsWithRegions(base);
    final marked = CastSpan(
      id: 'accepted-quote', bookId: 'book',
      start: start, end: end,
      sourceDigest: CastSpan.digest(source.substring(start, end)),
      speakerId: 'actor',
      origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted,
      lockedByUser: true,
    );
    final prepared = prepareCastSpeech(
      source: source,
      base: [for (final part in pieces) part.segment],
      annotations: [marked],
      bookId: 'book',
      knownCharacterIds: {'actor'},
      offsetFromAnchor: (_) => null,
    );
    final joined = coalesceQuotedSpeech(
      source: source,
      chunks: prepared.segments,
      quotedChunks: pieces,
      speakerByStart: prepared.speakerByStart,
      maxChars: 220,
    );
    final actorChunks = joined.segments
        .where((chunk) => chunk.start >= start && chunk.end <= end)
        .toList();
    expect(actorChunks.length, greaterThan(1));
    expect(actorChunks.every((chunk) =>
        joined.speakerByStart[chunk.start] == 'actor'), isTrue);
    expect(joined.segments.first.text, 'A narrator began.');
    expect(joined.segments.last.text, 'She then left.');
    expect(joined.speakerByStart.containsKey(joined.segments.first.start),
        isFalse);
    expect(joined.speakerByStart.containsKey(joined.segments.last.start),
        isFalse);
    _assertSourceExact(source, joined.segments);
  });

  test('nested quote does not grant a second speaker automatically',
      () {
    const source = '«Lei disse ‘rimani’ e sorrise.» Tornarono a casa.';
    final original = splitQuotedSegmentsWithRegions(
      segmentSpeech(source, maxChars: 30),
    );
    final outer = source.indexOf('«');
    final end = source.indexOf('»') + 1;
    final accepted = CastSpan(
      id: 'outer-turn', bookId: 'book',
      start: outer, end: end,
      sourceDigest: CastSpan.digest(source.substring(outer, end)),
      speakerId: 'mira',
      origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted,
      lockedByUser: true,
    );
    final prepared = prepareCastSpeech(
      source: source,
      base: [for (final piece in original) piece.segment],
      annotations: [accepted],
      bookId: 'book',
      knownCharacterIds: {'mira', 'unknown-inner'},
      offsetFromAnchor: (_) => null,
    );
    final collected = prepared.segments.where(
        (chunk) => chunk.start >= outer && chunk.end <= end).toList();
    expect(collected, isNotEmpty);
    expect(collected.every((chunk) =>
        prepared.speakerByStart[chunk.start] == 'mira'), isTrue);
    expect(prepared.speakerByStart.values.contains('unknown-inner'), isFalse);
    _assertSourceExact(source, prepared.segments);
  });
}
