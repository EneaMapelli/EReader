import 'package:ereader/data/epub_anchor_integrity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void verify({
    required String source,
    required List<({String id, int start, int end})> spine,
    List<({int start, int end, int? target})> links = const [],
    List<int> nav = const [],
    List<int> notes = const [],
  }) => verifyEpubSourceIntegrity(
    text: source, spine: spine, links: links,
    navigationTargets: nav, noteTargets: notes,
  );

  test('valid spine, Unicode, links and editorial targets pass unchanged', () {
    const source = 'A 📖.\n\nSecond!';
    verify(
      source: source,
      spine: const [
        (id: 'first', start: 0, end: 5),
        (id: 'second', start: 7, end: 14),
      ],
      links: const [(start: 2, end: 4, target: 7)],
      nav: const [0, 7, 8],
      notes: const [7],
    );
    expect(source.substring(2, 4), '📖');
  });

  test('leading, middle and trailing empty OPF items are navigation-only',
      () {
    verify(
      source: 'One\n\nTwo',
      spine: const [
        (id: 'cover', start: 0, end: 0),
        (id: 'a', start: 0, end: 3),
        (id: 'middle', start: 3, end: 3),
        (id: 'another-image', start: 3, end: 3),
        (id: 'b', start: 5, end: 8),
        (id: 'appendix', start: 8, end: 8),
      ],
      links: const [(start: 1, end: 2, target: 5)],
      nav: const [0, 5],
    );
  });

  test('silent OPF positions cannot hide holes or corrupt separators', () {
    const source = 'One\n\nTwo';
    for (final invalid in [
      const [
        (id: 'a', start: 0, end: 3),
        (id: 'silent', start: 4, end: 4),
        (id: 'b', start: 5, end: 8),
      ],
      const [
        (id: 'a', start: 0, end: 3),
        (id: 'silent', start: 3, end: 3),
        (id: 'b', start: 6, end: 8),
      ],
      const [
        (id: 'a', start: 0, end: 3),
        (id: 'b', start: 5, end: 8),
        (id: 'silent', start: 7, end: 7),
      ],
      const [
        (id: 'a', start: 0, end: 3),
        (id: 'a', start: 3, end: 3),
        (id: 'b', start: 5, end: 8),
      ],
    ]) {
      expect(() => verify(source: source, spine: invalid),
          throwsFormatException);
    }
    expect(() => verify(
      source: 'One', spine: const [(id: 'only', start: 0, end: 0)]),
      throwsFormatException);
  });

  test('duplicate spine IDs cannot be used for stable saved anchors', () {
    expect(() => verify(
      source: 'One\n\nTwo',
      spine: const [
        (id: 'one', start: 0, end: 3),
        (id: 'one', start: 5, end: 8),
      ],
    ), throwsFormatException);
  });

  test('overlap, holes and missing separators all fail', () {
    for (final ranges in [
      const [(id: 'a', start: 0, end: 3),
             (id: 'b', start: 4, end: 8)],
      const [(id: 'a', start: 0, end: 3),
             (id: 'b', start: 6, end: 8)],
      const [(id: 'a', start: 0, end: 7)],
      const [(id: 'a', start: 1, end: 3),
             (id: 'b', start: 5, end: 8)],
    ]) {
      expect(() => verify(source: 'One\n\nTwo', spine: ranges),
          throwsFormatException);
    }
  });

  test('links must be ordered, non-overlapping and wholly in one item', () {
    const source = 'One\n\nTwo';
    const spine = [
      (id: 'a', start: 0, end: 3),
      (id: 'b', start: 5, end: 8),
    ];
    expect(() => verify(
      source: source, spine: spine,
      links: const [(start: 1, end: 6, target: 5)],
    ), throwsFormatException);
    expect(() => verify(
      source: source, spine: spine,
      links: const [
        (start: 0, end: 2, target: 5),
        (start: 1, end: 3, target: 5),
      ],
    ), throwsFormatException);
  });

  test('targets in synthetic separators or beyond end are rejected', () {
    const source = 'One\n\nTwo';
    const spine = [
      (id: 'a', start: 0, end: 3),
      (id: 'b', start: 5, end: 8),
    ];
    expect(() => verify(
        source: source, spine: spine, nav: const [3]), throwsFormatException);
    expect(() => verify(
        source: source, spine: spine, notes: const [8]), throwsFormatException);
    expect(() => verify(
      source: source, spine: spine,
      links: const [(start: 0, end: 3, target: 4)],
    ), throwsFormatException);
  });

  test('UTF-16 source positions cannot split emoji surrogate pairs', () {
    const source = 'A 📖.';
    expect(() => verify(
      source: source,
      spine: const [(id: 'a', start: 0, end: 5)],
      nav: const [3], // low surrogate, not a character boundary
    ), throwsFormatException);
    expect(() => verify(
      source: source,
      spine: const [(id: 'a', start: 0, end: 5)],
      links: const [(start: 2, end: 3, target: 0)],
    ), throwsFormatException);
    // The complete surrogate pair is still a valid linked word.
    verify(
      source: source,
      spine: const [(id: 'a', start: 0, end: 5)],
      links: const [(start: 2, end: 4, target: 0)],
    );
  });

  test('empty source/spine cannot be silently imported', () {
    expect(() => verify(source: '', spine: const []),
        throwsFormatException);
  });
}
