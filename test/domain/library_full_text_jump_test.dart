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
      sourceOffset: 0, expectedText: 'a' * 121,
    ).validatedOffset('a' * 121), isNull);
  });
}
