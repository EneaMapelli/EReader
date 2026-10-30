import 'package:ereader/domain/library_full_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ranks two separated multiword passages and validates source jumps', () {
    final source = 'blue ${List.filled(18, 'valley ').join()}dragon. '
        + List.filled(48, 'unrelated ').join()
        + 'A blue dragon flies at sunrise.';
    final passages = findIndexedPassages(source, ['blue', 'dragon']);
    expect(passages.length, 2);
    expect(passages.first.jump.sourceOffset, source.lastIndexOf('blue'));
    expect(passages.last.jump.sourceOffset, 0);
    expect(passages.every((p) => p.allTermsNearby), isTrue);
    for (final passage in passages) {
      expect(passage.jump.validatedOffset(source),
          passage.jump.sourceOffset);
      expect(passage.excerpt.isNotEmpty, isTrue);
      expect(passage.excerpt.length, lessThan(460));
    }
  });

  test('adjacent repeated windows collapse without identical paragraphs',
      () {
    final source = 'blue dragon blue dragon blue dragon. '
        + List.filled(75, 'filler ').join()
        + 'blue dragon.';
    final passages = findIndexedPassages(source, ['blue', 'dragon']);
    expect(passages, hasLength(2));
    expect(passages.first.jump.sourceOffset, 0);
    expect(passages.last.jump.sourceOffset, source.lastIndexOf('blue'));
  });

  test('single-term hits produce capped alternative source locations', () {
    final source = List.filled(15, 'dragon and birds. ').join();
    final passages = findIndexedPassages(source, ['dragon'], limit: 3);
    expect(passages, hasLength(3));
    expect(passages.map((p) => p.jump.sourceOffset).toList(),
        orderedEquals([0, 18, 36]));
    expect(passages.every((p) => p.allTermsNearby), isTrue);
    expect(findIndexedPassages(source, ['dragon'], limit: 1), hasLength(1));
  });

  test('distant terms are explicitly labelled as a fallback', () {
    final source = 'dragon ' + List.filled(120, 'filler ').join() + 'blue';
    final passages = findIndexedPassages(source, ['dragon', 'blue']);
    expect(passages, hasLength(1));
    expect(passages.single.allTermsNearby, isFalse);
    expect(passages.single.jump.sourceOffset, 0);
    expect(findIndexedPassages(source, ['missing', 'blue']), isEmpty);
  });

  test('UTF-16 excerpt boundaries never split a surrogate pair', () {
    const source = '🐉 blue dragon 🐉';
    final passages = findIndexedPassages(source, ['blue', 'dragon'],
        contextChars: 2);
    expect(passages, hasLength(1));
    expect(passages.single.jump.sourceOffset, 3);
    expect(passages.single.excerpt, startsWith('🐉'));
    expect(passages.single.jump.validatedOffset(source), 3);
  });

  test('invalid limits and query dimensions fail closed', () {
    const source = 'blue dragon';
    expect(findIndexedPassages(source, ['blue'], limit: 0), isEmpty);
    expect(findIndexedPassages(source, ['blue'], limit: 11), isEmpty);
    expect(findIndexedPassages(source, ['blue'], contextChars: 161), isEmpty);
    expect(findIndexedPassages(source, ['blue'], maxSpanChars: 3000), isEmpty);
    expect(findIndexedPassages(source, []), isEmpty);
    expect(findIndexedPassages(source, List.filled(9, 'blue')), isEmpty);
    expect(findIndexedPassages(source, ['']), isEmpty);
  });
}
