import 'package:ereader/domain/library_full_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Any word builds a literal OR FTS5 query without raw operators', () {
    expect(libraryFullTextMatchExpression('blue dragon',
        mode: LibraryFullTextMatchMode.anyWord), '"blue" OR "dragon"');
    expect(libraryFullTextMatchExpression('dragon blue',
        mode: LibraryFullTextMatchMode.allWords), '"dragon" AND "blue"');
    expect(libraryFullTextMatchExpression('dragon blue',
        mode: LibraryFullTextMatchMode.exactPhrase), '"dragon blue"');
    expect(libraryFullTextMatchExpression('wolf" OR "dragon',
        mode: LibraryFullTextMatchMode.anyWord), '"wolf" OR "OR" OR "dragon"');
    expect(libraryFullTextMatchExpression('"""',
        mode: LibraryFullTextMatchMode.anyWord), isNull);
  });

  test('Any word jumps to first whole-word match even if first query is absent',
      () {
    const source = 'An owl watched the dragon near the lake.';
    final jump = firstIndexedAnyWord(source, ['missing', 'dragon']);
    expect(jump?.sourceOffset, source.indexOf('dragon'));
    expect(jump?.expectedText, 'dragon');
    expect(jump?.validatedOffset(source), source.indexOf('dragon'));
    expect(jump?.validatedOffset(
        'An owl watched the dracon near the lake.'), isNull);
    expect(firstIndexedAnyWord('dragonfly nearby', ['dragon']), isNull);
    expect(firstIndexedAnyWord(source, ['absent', 'missing']), isNull);
  });

  test('Any word groups nearby hits into bounded separate previews', () {
    final source = 'blue dragon. ' +
        List.filled(40, 'filler ').join() +
        'green dragon sleeps. ' +
        List.filled(40, 'other ').join() +
        'blue sky.';
    final hits = findIndexedAnyWordPassages(source, ['blue', 'green']);
    expect(hits, hasLength(3));
    expect(hits.map((hit) => hit.jump.sourceOffset).toList(),
        orderedEquals([
          0,
          source.indexOf('green'),
          source.lastIndexOf('blue'),
        ]));
    expect(hits.every((hit) => !hit.allTermsNearby), isTrue);
    expect(hits.every((hit) =>
        hit.jump.validatedOffset(source) == hit.jump.sourceOffset), isTrue);
    expect(findIndexedAnyWordPassages(source, ['blue', 'green'], limit: 2),
        hasLength(2));
  });

  test('Any word preserves UTF-16 source offsets and exact-word boundaries',
      () {
    const source = '🐉 dragonfly and blue dragons, finally a dragon.';
    final hits = findIndexedAnyWordPassages(source, ['dragon', 'blue'],
        minSeparationChars: 0);
    expect(hits, hasLength(2));
    expect(hits.first.jump.sourceOffset, source.indexOf('blue'));
    expect(hits.last.jump.sourceOffset, source.lastIndexOf('dragon'));
    expect(firstIndexedAnyWord(source, ['dragon'])?.sourceOffset,
        source.lastIndexOf('dragon'));
    expect(hits.first.jump.validatedOffset(source),
        hits.first.jump.sourceOffset);
  });

  test('malformed input and limits are fail-closed', () {
    expect(firstIndexedAnyWord('blue dragon', []), isNull);
    expect(firstIndexedAnyWord('blue', ['']), isNull);
    expect(firstIndexedAnyWord('blue', List.filled(9, 'blue')), isNull);
    expect(findIndexedAnyWordPassages('blue dragon', ['blue'],
        limit: 0), isEmpty);
    expect(findIndexedAnyWordPassages('blue dragon', ['blue'],
        limit: 11), isEmpty);
    expect(findIndexedAnyWordPassages('blue dragon', ['blue'],
        contextChars: 161), isEmpty);
    expect(findIndexedAnyWordPassages('blue dragon', ['blue'],
        minSeparationChars: 1025), isEmpty);
  });
}
