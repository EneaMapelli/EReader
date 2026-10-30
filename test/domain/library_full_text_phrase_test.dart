import 'package:ereader/domain/library_full_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query modes produce only quoted, bounded FTS expressions', () {
    expect(libraryFullTextMatchExpression('blue dragon'),
        '"blue" AND "dragon"');
    expect(libraryFullTextMatchExpression('blue dragon',
        mode: LibraryFullTextMatchMode.exactPhrase), '"blue dragon"');
    expect(libraryFullTextMatchExpression('blue, dragon',
        mode: LibraryFullTextMatchMode.exactPhrase), '"blue dragon"');
    expect(libraryFullTextMatchExpression('foo" OR "bar',
        mode: LibraryFullTextMatchMode.exactPhrase), '"foo OR bar"');
    expect(libraryFullTextMatchExpression('  '), isNull);
    expect(libraryFullTextMatchExpression('"""'), isNull);
    expect(libraryFullTextMatchExpression(List.filled(121, 'x').join()),
        isNull);
    expect(libraryFullTextMatchExpression(
        List.filled(9, 'word').join(' ')), isNull);
  });

  test('exact phrase requires consecutive whole tokens in source order', () {
    const source = 'blue dragon. blue, dragon. blue and dragon. '
        'dragon blue. blue dragonfly.';
    final hits = findIndexedExactPhrases(source, ['blue', 'dragon']);
    expect(hits, hasLength(2));
    expect(hits[0].jump.sourceOffset, 0);
    expect(hits[1].jump.sourceOffset, source.indexOf('blue, dragon'));
    expect(hits.every((p) => p.allTermsNearby), isTrue);
    for (final hit in hits) {
      expect(hit.jump.validatedOffset(source), hit.jump.sourceOffset);
    }
    expect(findIndexedExactPhrases(source, ['dragon', 'blue']), hasLength(1));
    expect(findIndexedExactPhrases(source, ['blue', 'and', 'dragon']),
        hasLength(1));
    expect(findIndexedExactPhrases(source, ['blue', 'dragonfly']),
        hasLength(1));
    expect(findIndexedExactPhrases(source, ['dragon', 'dragon']), isEmpty);
  });

  test('repeated terms must occur repeatedly in the requested order', () {
    const source = 'echo echo. echo over echo. echo echo echo.';
    final hits = findIndexedExactPhrases(source, ['echo', 'echo']);
    expect(hits.map((h) => h.jump.sourceOffset).toList(),
        orderedEquals([0, source.indexOf('echo echo echo'),
            source.indexOf('echo echo echo') + 5]));
  });

  test('phrase source offsets are UTF-16 and validate surrounding context',
      () {
    const source = '🐉 blue dragon, then green dragon.';
    final hit = findIndexedExactPhrases(source, ['blue', 'dragon']).single;
    expect(hit.jump.sourceOffset, 3);
    expect(hit.jump.validatedOffset(source), 3);
    expect(hit.jump.validatedOffset('🐉 blue dracon, then green dragon.'),
        isNull);
    expect(hit.excerpt, contains('🐉'));
  });

  test('phrase results and source spans are capped and fail closed', () {
    const source = 'blue dragon. blue dragon. blue dragon.';
    expect(findIndexedExactPhrases(source, ['blue', 'dragon'], limit: 2),
        hasLength(2));
    expect(findIndexedExactPhrases(source, ['blue'], limit: 0), isEmpty);
    expect(findIndexedExactPhrases(source, ['blue'], limit: 11), isEmpty);
    expect(findIndexedExactPhrases(source, []), isEmpty);
    expect(findIndexedExactPhrases(source, List.filled(9, 'blue')), isEmpty);
    final veryDistant = 'blue ' + List.filled(200, ' ').join() + 'dragon';
    expect(findIndexedExactPhrases(veryDistant, ['blue', 'dragon']),
        isEmpty);
    expect(findIndexedExactPhrases('blue, dragon', ['blue', 'dragon']),
        hasLength(1));
  });
}
