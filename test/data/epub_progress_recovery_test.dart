import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_progress_recovery.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentContent oneChapter(String text, {String id = 'a'}) =>
    DocumentContent(title: 'Test', text: text, epubSpineRanges: [
      EpubSpineRange(idref: id, href: '$id.xhtml',
          start: 0, end: text.length),
    ]);

void main() {
  test('v2 exact source resumes at the same UTF-16 offset', () {
    const text = 'Opening the story. The unique chapter begins 📖 here.';
    final doc = oneChapter(text);
    final offset = text.indexOf('unique');
    final saved = doc.anchorAt(BookFormat.epub, offset);
    expect(saved.hasContext, isTrue);
    final result = resolveEpubReadingProgress(
        doc, anchor: saved, legacyOffset: 0);
    expect(result.status, EpubProgressRecoveryStatus.exact);
    expect(result.offset, offset);
    expect(result.shouldPersist, isFalse);
  });

  test('new paragraph breaks relocate a unique reference in same spine', () {
    const original = 'The morning starts. A unique paragraph continues.';
    const changed = 'The morning starts.\n\nA unique paragraph continues.';
    final previous = oneChapter(original);
    final next = oneChapter(changed);
    final saved = previous.anchorAt(
        BookFormat.epub, original.indexOf('unique'));
    final result = resolveEpubReadingProgress(
        next, anchor: saved, legacyOffset: original.indexOf('unique'));
    expect(result.status, EpubProgressRecoveryStatus.relocated);
    expect(result.offset, changed.indexOf('unique'));
    expect(result.shouldPersist, isTrue);
    expect(next.offsetOf(saved), isNull,
        reason: 'Generic source-anchor lookup never guesses a new position');
    final refreshed = next.anchorAt(BookFormat.epub, result.offset);
    expect(next.offsetOf(refreshed), result.offset);
  });

  test('changes in a preceding chapter preserve later spine anchor', () {
    const old = DocumentContent(
      title: 'Book',
      text: 'First.\n\nA later chapter starts after a sunrise.',
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: 'first.xhtml',
            start: 0, end: 6),
        EpubSpineRange(idref: 'second', href: 'second.xhtml',
            start: 8, end: 47),
      ],
    );
    const changed = DocumentContent(
      title: 'Book',
      text: 'Much longer opening.\n\nA later chapter starts after a sunrise.',
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: 'first.xhtml',
            start: 0, end: 20),
        EpubSpineRange(idref: 'second', href: 'second.xhtml',
            start: 22, end: 61),
      ],
    );
    final saved = old.anchorAt(BookFormat.epub,
        old.text.indexOf('sunrise'));
    final actual = changed.text.indexOf('sunrise');
    expect(resolveEpubReadingProgress(changed,
        anchor: saved, legacyOffset: 0).offset, actual);
  });

  test('repeated equivalent context cannot choose arbitrary occurrence', () {
    final snippet = 'A' * 80 + ' UNIQUE ' + 'B' * 80;
    final oldText = 'Intro text. $snippet';
    final old = oneChapter(oldText);
    final saved = old.anchorAt(BookFormat.epub, oldText.indexOf('UNIQUE'));
    final current = oneChapter('Different preface. $snippet\n\n$snippet');
    final result = resolveEpubReadingProgress(current,
        anchor: saved, legacyOffset: 500);
    expect(result.status, EpubProgressRecoveryStatus.needsReview);
    expect(result.offset, 0);
    expect(result.shouldPersist, isFalse);
  });

  test('missing section or out-of-bounds v2 progress needs user review', () {
    const text = 'The new single chapter contents.';
    final doc = oneChapter(text);
    final saved = oneChapter(
        'A different earlier edition with extensive textual details.',
        id: 'removed').anchorAt(BookFormat.epub, 10);
    final result = resolveEpubReadingProgress(
        doc, anchor: saved, legacyOffset: 9999);
    expect(result.status, EpubProgressRecoveryStatus.needsReview);
    expect(result.offset, 0);
    expect(result.shouldPersist, isFalse);
  });

  test('v1 anchors and offset-only old library entries remain compatible', () {
    final doc = oneChapter('Some legacy text is still readable.');
    final v1 = ReadingAnchor.fromJson({
      'version': 1, 'kind': 'epubSpine',
      'sourceId': 'a', 'localOffset': 6,
    });
    final result = resolveEpubReadingProgress(
        doc, anchor: v1, legacyOffset: 0);
    expect(result.offset, 6);
    expect(result.status, EpubProgressRecoveryStatus.legacyUnverified);
    final offsetOnly = resolveEpubReadingProgress(
        doc, anchor: null, legacyOffset: 11);
    expect(offsetOnly.offset, 11);
    expect(offsetOnly.status, EpubProgressRecoveryStatus.legacyUnverified);
  });

  test('out-of-range v1 local offset starts at its original chapter', () {
    final doc = oneChapter('A short edition.');
    final result = resolveEpubReadingProgress(
      doc, anchor: const ReadingAnchor(
          kind: AnchorKind.epubSpine, sourceId: 'a', localOffset: 600),
      legacyOffset: 12,
    );
    expect(result.offset, 0);
    expect(result.status, EpubProgressRecoveryStatus.needsReview);
  });

  test('new v2 anchors round-trip using existing anchor JSON column', () {
    final doc = oneChapter('Source text from the book 📖 is private.');
    final original = doc.anchorAt(BookFormat.epub, 22);
    final data = original.toJson();
    expect(data['version'], 2);
    expect(data.values.join(' '), isNot(contains('private')));
    final restored = ReadingAnchor.fromJson(data);
    expect(restored.contextBefore, original.contextBefore);
    expect(restored.contextAfter, original.contextAfter);
    expect(doc.offsetOf(restored), 22);
  });
}
