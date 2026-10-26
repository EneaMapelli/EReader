import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

PreparedCastSpeech _narration(
  String source, {
  List<int> boundaries = const [],
  Map<int, String?> speakers = const {},
  int maxChars = 400,
  bool enabled = true,
}) {
  final quoted = splitQuotedSegmentsWithRegions(
    segmentSpeech(source, maxChars: 20),
  );
  return coalesceQuotedSpeech(
    source: source,
    chunks: [for (final part in quoted) part.segment],
    quotedChunks: quoted,
    speakerByStart: speakers,
    hardBoundaries: boundaries,
    maxChars: maxChars,
    coalesceNarration: enabled,
  );
}

void _assertSourceExact(String source, PreparedCastSpeech prepared) {
  var lastEnd = 0;
  for (final part in prepared.segments) {
    expect(part.start, greaterThanOrEqualTo(lastEnd));
    expect(source.substring(part.start, part.end), part.text);
    lastEnd = part.end;
  }
}

void main() {
  test('same-paragraph narrator sentences share one bounded utterance', () {
    const source = 'Morning came. The valley awoke. Birds sang.';
    final before = _narration(source, enabled: false);
    final after = _narration(source);
    expect(before.segments.length, greaterThan(1));
    expect(after.segments, hasLength(1));
    expect(after.segments.single.text, source);
    expect(after.speakerByStart, isEmpty);
    _assertSourceExact(source, after);
  });

  test('explicit EPUB paragraph and chapter boundaries are preserved', () {
    const source = 'Opening line. More prose.\n\n'
        'Next paragraph. More text.\n\n'
        'New chapter. Further words.';
    final paragraph = source.indexOf('Next paragraph.');
    final chapter = source.indexOf('New chapter.');
    final result = _narration(source, boundaries: [paragraph, chapter]);
    expect(result.segments, hasLength(3));
    expect(result.segments[0].text, 'Opening line. More prose.');
    expect(result.segments[1].text, 'Next paragraph. More text.');
    expect(result.segments[2].text, 'New chapter. Further words.');
    _assertSourceExact(source, result);
  });

  test('narrator never merges into quoted dialogue or back out of it', () {
    const source = 'Intro one. Intro two. «Hello actor. Next line.» '
        'Afterward one. Afterward two.';
    final result = _narration(source);
    expect(result.segments.first.text, 'Intro one. Intro two.');
    expect(result.segments.any((part) => part.text.contains('«') &&
        part.text.contains('Afterward')), isFalse);
    expect(result.segments.last.text, 'Afterward one. Afterward two.');
    _assertSourceExact(source, result);
  });

  test('user-confirmed narrator mask is not erased by narrator merging', () {
    const source = 'A sentence. Masked text. Then prose.';
    final marked = source.indexOf('Masked text.');
    final quoted = splitQuotedSegmentsWithRegions(
        segmentSpeech(source, maxChars: 20));
    final chunks = [for (final part in quoted) part.segment];
    expect(chunks.any((part) => part.start == marked), isTrue);
    final result = coalesceQuotedSpeech(
      source: source,
      chunks: chunks,
      quotedChunks: quoted,
      speakerByStart: {marked: null},
      coalesceNarration: true,
    );
    expect(result.speakerByStart.containsKey(marked), isTrue);
    expect(result.speakerByStart[marked], isNull);
    expect(result.segments.any((part) =>
        part.start < marked && part.end > marked), isFalse);
    _assertSourceExact(source, result);
  });

  test('notes remain independently skippable inside a single paragraph', () {
    const source = 'Normal intro. Note body. Back to prose.';
    final noteStart = source.indexOf('Note body.');
    final noteEnd = noteStart + 'Note body.'.length;
    final result = _narration(source,
        boundaries: [noteStart, noteEnd]);
    expect(result.segments, hasLength(3));
    expect(result.segments[0].text, 'Normal intro.');
    expect(result.segments[1].text, 'Note body.');
    expect(result.segments[2].text, 'Back to prose.');
    _assertSourceExact(source, result);
  });

  test('bounded utterances keep UTF-16 emoji and original source offsets', () {
    const source = 'A 🐉 arrived. A 😀 smiled. '
        'More narration followed. The ending was near.';
    final result = _narration(source, maxChars: 38);
    expect(result.segments.length, greaterThan(1));
    expect(result.segments.every((part) => part.text.length <= 38), isTrue);
    _assertSourceExact(source, result);
  });

  test('explicit voice assignment never merges with unlabelled narrator', () {
    const source = 'First words. Character words. Then narrative.';
    final changed = source.indexOf('Character words.');
    final quoted = splitQuotedSegmentsWithRegions(
        segmentSpeech(source, maxChars: 20));
    final chunks = [for (final part in quoted) part.segment];
    expect(chunks.any((part) => part.start == changed), isTrue);
    final result = coalesceQuotedSpeech(
      source: source,
      chunks: chunks,
      quotedChunks: quoted,
      speakerByStart: {changed: 'character-1'},
      coalesceNarration: true,
    );
    expect(result.speakerByStart[changed], 'character-1');
    expect(result.segments.any((part) =>
        part.start < changed && part.end > changed), isFalse);
    _assertSourceExact(source, result);
  });
}
