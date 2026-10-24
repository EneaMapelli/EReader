import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EPUB spine anchor survives offset shifts in preceding chapter', () {
    const original = DocumentContent(
      title: 'Book',
      text: 'First...\n\nHello world',
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: '1.xhtml', start: 0, end: 8),
        EpubSpineRange(idref: 'second', href: '2.xhtml', start: 10, end: 21),
      ],
    );
    final anchor = original.anchorAt(BookFormat.epub, 16);
    expect(anchor.kind, AnchorKind.epubSpine);
    expect(anchor.sourceId, 'second');
    expect(anchor.localOffset, 6);

    const changed = DocumentContent(
      title: 'Book',
      text: 'A much longer first chapter\n\nHello world',
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: '1.xhtml', start: 0, end: 27),
        EpubSpineRange(idref: 'second', href: '2.xhtml', start: 29, end: 40),
      ],
    );
    expect(changed.offsetOf(anchor), 35);
    expect(changed.offsetOf(
      const ReadingAnchor(kind: AnchorKind.epubSpine,
        sourceId: 'missing', localOffset: 5),
    ), isNull);
  });

  test('stale EPUB anchor offset beyond its spine item fails closed', () {
    const doc = DocumentContent(
      title: 'Book',
      text: 'Short\n\nAnother',
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: 'first.xhtml',
            start: 0, end: 5),
        EpubSpineRange(idref: 'second', href: 'second.xhtml',
            start: 7, end: 14),
      ],
    );
    expect(doc.offsetOf(const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'first', localOffset: 999,
    )), isNull);
    expect(doc.offsetOf(const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'first', localOffset: 5,
    )), 5);
    expect(doc.offsetOf(const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'second', localOffset: 1,
    )), 8);
  });

  test('EPUB anchor may not resume in the middle of a surrogate pair', () {
    const doc = DocumentContent(
      title: 'Book', text: 'A 📖!',
      epubSpineRanges: [
        EpubSpineRange(idref: 'only', href: 'one.xhtml',
            start: 0, end: 5),
      ],
    );
    expect(doc.offsetOf(const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'only', localOffset: 3,
    )), isNull);
    expect(doc.offsetOf(const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'only', localOffset: 2,
    )), 2);
  });

  test('PDF page anchor retains local offset', () {
    const data = DocumentContent(
      title: 'PDF',
      text: 'ABC\n\nOne two',
      pdfPageRanges: [
        PdfPageRange(1, 0, 3),
        PdfPageRange(2, 5, 12),
      ],
    );
    final anchor = data.anchorAt(BookFormat.pdf, 9);
    expect(anchor.sourceId, '2');
    expect(anchor.localOffset, 4);
    expect(data.offsetOf(anchor), 9);
  });

  test('anchors are versioned and reject invalid positions', () {
    const anchor = ReadingAnchor(
      kind: AnchorKind.text,
      sourceId: 'body',
      localOffset: 13,
    );
    expect(ReadingAnchor.fromJson(anchor.toJson()).localOffset, 13);
    expect(() => ReadingAnchor.fromJson({
      'version': 2, 'kind': 'text',
      'sourceId': 'body', 'localOffset': 13,
    }), throwsFormatException);
    expect(() => ReadingAnchor.fromJson({
      'version': 1, 'kind': 'text',
      'sourceId': 'body', 'localOffset': -1,
    }), throwsFormatException);
    const txt = DocumentContent(title: 'TXT', text: 'Short');
    expect(txt.offsetOf(anchor), 5);
  });
}
