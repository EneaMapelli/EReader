import 'package:ereader/domain/pronunciation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = PronunciationTransformer();

  test('word matching does not modify compound words or source text', () {
    const input = 'Ana incontrò Banana. Ana e ANA.';
    const rules = [
      PronunciationRule(id: 'r1', pattern: 'Ana', replacement: 'Anna'),
    ];
    final spoken = engine.apply(input, rules, bookId: 'book');
    expect(spoken, 'Anna incontrò Banana. Anna e Anna.');
    expect(input, 'Ana incontrò Banana. Ana e ANA.');
  });

  test('book-specific override wins over global pronunciation', () {
    const rules = [
      PronunciationRule(id: 'global', pattern: 'Aeryn',
          replacement: 'Erin'),
      PronunciationRule(id: 'local', bookId: 'book-1',
          pattern: 'Aeryn', replacement: 'Eirin'),
    ];
    expect(engine.apply('Aeryn', rules, bookId: 'book-1'), 'Eirin');
    expect(engine.apply('Aeryn', rules, bookId: 'book-2'), 'Erin');
  });

  test('literal punctuation is not treated as a regex expression', () {
    const rules = [
      PronunciationRule(id: 'dots', pattern: 'C++',
          replacement: 'C plus plus'),
    ];
    expect(engine.apply('C++ and CCC', rules, bookId: 'book'),
        'C plus plus and CCC');
  });

  test('replacements do not cascade or loop', () {
    const rules = [
      PronunciationRule(id: 'one', pattern: 'a', replacement: 'b'),
      PronunciationRule(id: 'two', pattern: 'b', replacement: 'a'),
    ];
    expect(engine.apply('a b', rules, bookId: 'book'), 'b a');
  });

  test('accents and Unicode letters honor whole-word boundaries', () {
    const rules = [
      PronunciationRule(id: 'accent', pattern: 'é',
          replacement: 'eh'),
    ];
    expect(engine.apply('café é élan', rules, bookId: 'book'),
        'café eh élan');
  });

  test('disabled rules and rules for another book are ignored', () {
    const rules = [
      PronunciationRule(id: 'disabled', pattern: 'X',
          replacement: 'Y', enabled: false),
      PronunciationRule(id: 'other', bookId: 'elsewhere',
          pattern: 'X', replacement: 'Z'),
    ];
    expect(engine.apply('X', rules, bookId: 'book'), 'X');
  });

  test('invalid empty replacements or long inputs are rejected', () {
    expect(
      () => const PronunciationRule(
        id: 'x', pattern: 'X', replacement: '',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => PronunciationRule(
        id: 'x', pattern: 'x' * 101, replacement: 'Y',
      ).validate(),
      throwsFormatException,
    );
  });
}
