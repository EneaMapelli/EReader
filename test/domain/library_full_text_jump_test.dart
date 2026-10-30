import 'package:ereader/domain/library_full_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a source-exact offset survives case-only changes', () {
    const source = 'Intro. The dragon sleeps.';
    const jump = LibraryFullTextJump(
      sourceOffset: 11, expectedText: 'dragon',
    );
    expect(jump.validatedOffset(source), 11);
    expect(jump.validatedOffset('Intro. The Dragon sleeps.'), 11);
    expect(jump.validatedOffset('Intro. The dracon sleeps.'), isNull);
    expect(jump.validatedOffset('New chapter. Intro. The dragon sleeps.'),
        isNull);
  });

  test('FTS first word uses UTF-16 offsets and never matches word prefixes',
      () {
    const source = '🐉 dragonfly and a dragon roam.';
    final hit = firstExactIndexedWord(source, 'dragon');
    expect(hit, isNotNull);
    expect(hit!.sourceOffset, source.lastIndexOf('dragon'));
    expect(hit.expectedText, 'dragon');
    expect(hit.validatedOffset(source), hit.sourceOffset);
    expect(firstExactIndexedWord(source, 'dragonfly')?.sourceOffset, 3);
    expect(firstExactIndexedWord(source, 'missing'), isNull);
  });

  test('multiple words open their nearest complete passage', () {
    final source = 'dragon on the first page. '
        '${List.filled(90, 'filler').join(' ')} '
        'A brilliant blue dragon appeared at sunset.';
    final chosen = bestIndexedPassage(source, ['dragon', 'blue']);
    expect(chosen, isNotNull);
    expect(chosen!.sourceOffset, source.lastIndexOf('blue'));
    expect(chosen.expectedText, 'blue');
    expect(chosen.validatedOffset(source), source.lastIndexOf('blue'));
  });

  test('multiword phrases may occur in reverse order and ties pick earliest',
      () {
    const source = 'blue dragon. Much later, dragon blue.';
    final closest = bestIndexedPassage(source, ['dragon', 'blue']);
    expect(closest?.sourceOffset, 0);
    expect(closest?.expectedText, 'blue');
    const tie = 'red fox. red fox.';
    expect(bestIndexedPassage(tie, ['fox', 'red'])?.sourceOffset, 0);
  });

  test('long-distance matches fall back to first exact whole word', () {
    final source = 'dragon ' + List.filled(300, 'x ').join() + 'blue';
    final chosen = bestIndexedPassage(source, ['dragon', 'blue']);
    expect(chosen?.sourceOffset, 0);
    expect(chosen?.expectedText, 'dragon');
    expect(bestIndexedPassage(source, ['missing', 'blue']), isNull);
    expect(bestIndexedPassage(source, ['dragon', 'blue'],
        maxSpanChars: 5)?.sourceOffset, 0);
  });

  test('repeated query words are deduplicated, surrogates keep UTF-16 offsets',
      () {
    const source = '🐉 blue dragon rests by the river.';
    final hit = bestIndexedPassage(source, ['dragon', 'blue', 'dragon']);
    expect(hit?.sourceOffset, 3);
    expect(hit?.validatedOffset(source), 3);
    expect(bestIndexedPassage(source, ['blue'])?.sourceOffset, 3);
    expect(bestIndexedPassage(source, []), isNull);
    expect(bestIndexedPassage(source, List.filled(9, 'dragon')), isNull);
    expect(bestIndexedPassage(source, ['blue', 'dragon'],
        maxSpanChars: 3000), isNull);
  });

  test('term boundaries reject partial matches and respect Unicode words', () {
    const source = 'dragonfly flies, then the dragon lands.';
    final hit = bestIndexedPassage(source, ['dragon', 'lands']);
    expect(hit?.sourceOffset, source.lastIndexOf('dragon'));
    expect(bestIndexedPassage('dragonfly', ['dragon']), isNull);
  });

  test('captured context detects edits around an unchanged matching word',
      () {
    const original = 'The blue dragon sleeps in the castle.';
    final jump = bestIndexedPassage(original, ['blue', 'dragon']);
    expect(jump, isNotNull);
    expect(jump!.validatedOffset(original), original.indexOf('blue'));
    // The same word remains at the same UTF-16 offset, but another query
    // word and the surrounding passage changed. Do not jump to stale text.
    expect(jump.validatedOffset('The blue dracon sleeps in the castle.'),
        isNull);
    expect(jump.validatedOffset('The blue dragon sleeps in the cradle.'),
        isNull);
    expect(jump.validatedOffset('The Blue dragon sleeps in the castle.'),
        original.indexOf('blue'));
    expect(jump.contextAfter, contains('dragon'));
  });

  test('single-word candidates also verify nearby unchanged source', () {
    const source = 'A red dragon arrived at the gate.';
    final jump = firstExactIndexedWord(source, 'dragon')!;
    expect(jump.validatedOffset(source), source.indexOf('dragon'));
    expect(jump.validatedOffset('A new dragon arrived at the gate.'), isNull);
    expect(jump.validatedOffset('A red dragon arrived at the lake.'), isNull);
  });

  test('empty or out of range matches reject stale targets', () {
    expect(const LibraryFullTextJump(
      sourceOffset: -1, expectedText: 'a',
    ).validatedOffset('a'), isNull);
    expect(const LibraryFullTextJump(
      sourceOffset: 0, expectedText: '',
    ).validatedOffset('a'), isNull);
    expect(const LibraryFullTextJump(
      sourceOffset: 6, expectedText: 'a',
    ).validatedOffset('a'), isNull);
    expect(LibraryFullTextJump(
      sourceOffset: 0, expectedText: List.filled(121, 'a').join(),
    ).validatedOffset(List.filled(121, 'a').join()), isNull);
  });
}
