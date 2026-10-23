import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

CastSpan manual({
  required String text,
  required int start,
  required int end,
  String id = 'manual-1',
  String? speaker = 'character-1',
  ReadingAnchor? anchor,
}) => CastSpan(
  id: id,
  bookId: 'book-hash',
  start: start,
  end: end,
  sourceDigest: CastSpan.digest(text.substring(start, end)),
  speakerId: speaker,
  origin: CastSpanOrigin.user,
  status: CastSpanStatus.accepted,
  lockedByUser: true,
  anchor: anchor,
);

void main() {
  const source = 'Anna disse: «Ciao!» e sorrise.';

  test('tags only a selected quoted phrase; narrator remains unchanged', () {
    final first = source.indexOf('«');
    final end = source.indexOf('»') + 1;
    final prepared = prepareCastSpeech(
      source: source,
      base: [SpeechSegment(0, source.length, source)],
      annotations: [manual(text: source, start: first, end: end)],
      offsetFromAnchor: (_) => null,
    );
    expect(prepared.segments.map((e) => e.text).toList(),
        ['Anna disse:', '«Ciao!»', 'e sorrise.']);
    expect(prepared.speakerByStart[prepared.segments[0].start], isNull);
    expect(prepared.speakerByStart[prepared.segments[1].start],
        'character-1');
    expect(prepared.speakerByStart[prepared.segments[2].start], isNull);
    for (final part in prepared.segments) {
      expect(source.substring(part.start, part.end), part.text);
    }
  });

  test('a pending LLM suggestion never changes the spoken voice', () {
    final from = source.indexOf('«'), until = source.indexOf('»') + 1;
    final draft = CastSpan(
      id: 'proposal',
      bookId: 'book-hash',
      start: from,
      end: until,
      sourceDigest: CastSpan.digest(source.substring(from, until)),
      speakerId: 'character-1',
      origin: CastSpanOrigin.llm,
      status: CastSpanStatus.proposed,
      lockedByUser: false,
      confidence: 0.99,
    );
    final prepared = prepareCastSpeech(
      source: source,
      base: [SpeechSegment(0, source.length, source)],
      annotations: [draft],
      offsetFromAnchor: (_) => null,
    );
    expect(prepared.speakerByStart, isEmpty);
  });

  test('source digest rejects stale annotations even if offsets still match',
      () {
    final original = manual(text: source, start: 0, end: 4);
    final changed = source.replaceFirst('Anna', 'Elsa');
    final prepared = prepareCastSpeech(
      source: changed,
      base: [SpeechSegment(0, changed.length, changed)],
      annotations: [original],
      offsetFromAnchor: (_) => null,
    );
    expect(prepared.speakerByStart, isEmpty);
  });

  test('source anchor shifts after earlier chapter text grows', () {
    const original = 'Head. Dialogue.';
    const changed = 'A longer heading. Dialogue.';
    final start = original.indexOf('Dialogue');
    final newer = changed.indexOf('Dialogue');
    final span = manual(
      text: original,
      start: start,
      end: original.length,
      anchor: const ReadingAnchor(
        kind: AnchorKind.epubSpine,
        sourceId: 'chapter-2',
        localOffset: 0,
      ),
    );
    final prepared = prepareCastSpeech(
      source: changed,
      base: [SpeechSegment(0, changed.length, changed)],
      annotations: [span],
      offsetFromAnchor: (_) => newer,
    );
    expect(prepared.speakerByStart[newer], 'character-1');
  });

  test('all nested conflicting labels are discarded, not just neighbors', () {
    const text = 'one two three four five';
    final spans = [
      manual(text: text, start: 0, end: text.length, id: 'wide'),
      manual(text: text, start: 4, end: 7, id: 'middle'),
      manual(text: text, start: 14, end: 18, id: 'right'),
    ];
    final prepared = prepareCastSpeech(
      source: text,
      base: [SpeechSegment(0, text.length, text)],
      annotations: spans,
      offsetFromAnchor: (_) => null,
    );
    expect(prepared.speakerByStart, isEmpty);
  });

  test('invalid confidence cannot be mistaken for accepted authority', () {
    expect(() => CastSpan(
      id: 'invalid', bookId: 'book', start: 0, end: 4,
      sourceDigest: CastSpan.digest('abcd'),
      speakerId: 'character',
      origin: CastSpanOrigin.llm,
      status: CastSpanStatus.accepted,
      lockedByUser: false,
      confidence: 3,
    ).validate(), throwsFormatException);
  });
}
