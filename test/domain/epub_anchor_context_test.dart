import 'package:ereader/domain/epub_anchor_context.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingAnchor anchorAt(String text, int offset) {
  final fingerprint = EpubAnchorContext.capture(
      text, 0, text.length, offset);
  return ReadingAnchor(
    kind: AnchorKind.epubSpine, sourceId: 'a', localOffset: offset,
    contextBefore: fingerprint.before, contextAfter: fingerprint.after,
  );
}

void main() {
  test('fingerprints match the original UTF-16 source but contain no prose',
      () {
    const source = 'Private 📖 source text with an unusual paragraph.';
    final at = source.indexOf('unusual');
    final anchor = anchorAt(source, at);
    expect(anchor.contextBefore, hasLength(32));
    expect(anchor.contextAfter, hasLength(32));
    expect(anchor.contextBefore, isNot(contains('source')));
    expect(anchor.contextAfter, isNot(contains('paragraph')));
    expect(EpubAnchorContext.matches(source, 0, source.length, at, anchor),
        isTrue);
    expect(EpubAnchorContext.matches(source, 0, source.length, at + 1, anchor),
        isFalse);
  });

  test('optimized per-side digest remains identical to persisted v2 hashes',
      () {
    const source = 'Private 📖 source text with an unusual paragraph.';
    final offset = source.indexOf('unusual');
    expect(offset, 31);
    final fingerprint = EpubAnchorContext.capture(
        source, 0, source.length, offset);
    // Fixed legacy v2 digests. Changing these would invalidate older
    // saved SQLite progress/bookmark fingerprints.
    expect(fingerprint.before, '9425681be3a57c35b00d6644c95a9339');
    expect(fingerprint.after, 'f3bc0de8f4b51db79b4f5a6d999c33a3');
    final anchor = anchorAt(source, offset);
    expect(EpubAnchorContext.matches(
        source, 0, source.length, offset, anchor), isTrue);
  });

  test('recovery tolerates inserted XHTML whitespace before a note', () {
    const original = 'Beginning. A stable note starts right here.';
    const current = 'Beginning.\n\nA stable note starts right here.';
    final saved = anchorAt(original, original.indexOf('note'));
    expect(EpubAnchorContext.relocate(
        current, 0, current.length, saved), current.indexOf('note'));
  });

  test('identical repeated text is ambiguous, never proximity-selected', () {
    final section = List.filled(90, 'A').join() +
        ' note ' + List.filled(90, 'B').join();
    final original = 'Intro. $section';
    final saved = anchorAt(original, original.indexOf('note'));
    final repeated = 'Preface. $section\n\n$section';
    expect(EpubAnchorContext.relocate(
        repeated, 0, repeated.length, saved), isNull);
  });

  test('emoji half-surrogate offsets are excluded from matching', () {
    const text = 'Before 📖 after';
    final start = text.indexOf('📖');
    final anchor = anchorAt(text, start);
    expect(EpubAnchorContext.matches(
        text, 0, text.length, start + 1, anchor), isFalse);
    expect(EpubAnchorContext.matches(
        text, 0, text.length, start, anchor), isTrue);
  });

  test('long chapters avoid unbounded full-scan relocation', () {
    final content = List.filled(
        EpubAnchorContext.maxSearchUnits + 1, 'a').join();
    final anchor = anchorAt(content, 10);
    expect(EpubAnchorContext.relocate(
        content, 0, content.length, anchor), isNull);
  });

  test('malformed old or new persisted anchor data fail closed', () {
    const common = {
      'kind': 'epubSpine', 'sourceId': 'a', 'localOffset': 4,
    };
    expect(() => ReadingAnchor.fromJson({
      ...common, 'version': 2,
      'contextBefore': 12, 'contextAfter': 'invalid',
    }), throwsFormatException);
    expect(() => ReadingAnchor.fromJson({
      ...common, 'version': 2,
      'contextBefore': List.filled(32, 'a').join(),
      'contextAfter': 'not-hex',
    }), throwsFormatException);
    expect(() => ReadingAnchor.fromJson({
      ...common, 'version': 3,
    }), throwsFormatException);
    final legacy = ReadingAnchor.fromJson({
      ...common, 'version': 1,
    });
    expect(legacy.hasContext, isFalse);
    expect(legacy.toJson()['version'], 1);
  });
}
