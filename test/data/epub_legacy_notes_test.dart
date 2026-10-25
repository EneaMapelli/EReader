import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List legacyBook({
  required String chapter,
  required String destination,
  bool aux = false,
  bool declared = true,
}) {
  final items = <String>[
    '<item id="a" href="Text/chapter.xhtml" '
        'media-type="application/xhtml+xml"/>',
    if (!aux) '<item id="b" href="Text/endnotes.xhtml" '
        'media-type="application/xhtml+xml"/>',
    if (aux && declared) '<item id="notes" href="Text/endnotes.xhtml" '
        'media-type="application/xhtml+xml"/>',
  ].join();
  final opf = '<package><metadata><title>Legacy notes</title></metadata>'
      '<manifest>$items</manifest><spine>'
      '<itemref idref="a"/>'
      '${aux ? "" : "<itemref idref=\"b\"/>"}'
      '</spine></package>';
  final archive = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
        '</rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/book.opf', opf))
    ..add(ArchiveFile.string('OPS/Text/chapter.xhtml', chapter))
    ..add(ArchiveFile.string('OPS/Text/endnotes.xhtml', destination));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  const extractor = EpubTextExtractor();

  test('EPUB2 superscript and classed in-spine note are paired', () {
    const chapter = '<html><body><p>A reference '
        '<sup><a href="endnotes.xhtml#fn1">1</a></sup>.</p></body></html>';
    const endnotes = '<html><body><div class="footnote" id="fn1">'
        'A legacy note body.</div></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes));
    expect(result.links.length, 1);
    expect(result.links.single.isFootnote, isTrue);
    expect(result.links.single.targetOffset, isNotNull);
    expect(result.footnotePreviews.length, 1);
    expect(result.footnotePreviews.single.text, 'A legacy note body.');
    expect(result.footnotePreviews.single.targetOffset,
        result.links.single.targetOffset);
    expect(result.ranges.length, 2);
  });

  test('EPUB2 classed note-ref opens declared auxiliary list note only', () {
    const chapter = '<html><body><p>See '
        '<a class="footnote-ref" href="endnotes.xhtml#n1">[1]</a>.</p>'
        '</body></html>';
    const endnotes = '<html><body><ol class="footnotes">'
        '<li id="n1">A note outside the reading order.</li>'
        '</ol></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true));
    expect(result.text, 'See [1].');
    expect(result.ranges.length, 1);
    expect(result.links.length, 1);
    expect(result.links.single.isFootnote, isTrue);
    expect(result.links.single.targetOffset, isNull);
    expect(result.links.single.auxiliaryFootnoteKey,
        'OPS/Text/endnotes.xhtml#n1');
    expect(result.auxiliaryFootnotePreviews.single.text,
        'A note outside the reading order.');
    expect(result.text, isNot(contains('outside the reading order')));
  });

  test('leading EPUB2 named anchor identifies a verified classed note', () {
    const chapter = '<html><body><p>Read '
        '<sup><a href="endnotes.xhtml#note1">[1]</a></sup>.</p>'
        '</body></html>';
    const endnotes = '<html><body><p class="footnote">'
        '<a name="note1"></a>Explanation with 📖 Unicode.'
        '</p></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true));
    expect(result.links.length, 1);
    expect(result.links.single.auxiliaryFootnoteKey,
        'OPS/Text/endnotes.xhtml#note1');
    expect(result.auxiliaryFootnotePreviews.single.text,
        'Explanation with 📖 Unicode.');
    expect(result.text, 'Read [1].');
  });

  test('ordinary numbered superscript to non-note paragraph stays a link', () {
    const chapter = '<html><body><p>Chapter '
        '<sup><a href="endnotes.xhtml#section2">2</a></sup>.'
        '</p></body></html>';
    const other = '<html><body><p id="section2">Ordinary text.</p>'
        '</body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: other));
    expect(result.links.length, 1);
    expect(result.links.single.isFootnote, isFalse);
    expect(result.links.single.targetOffset, isNotNull);
    expect(result.footnotePreviews, isEmpty);
  });

  test('ordinary unmarked link cannot turn into auxiliary note reference', () {
    const chapter = '<html><body><p>See '
        '<a href="endnotes.xhtml#n1">Details</a>.</p>'
        '</body></html>';
    const endnotes = '<html><body><div id="n1" class="footnote">'
        'A real note.</div></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true));
    expect(result.links, isEmpty);
    expect(result.auxiliaryFootnotePreviews, isEmpty);
  });

  test('class substring likeness cannot masquerade as footnote markup', () {
    const chapter = '<html><body><p>'
        '<a class="footnote-references-extra" href="endnotes.xhtml#n1">'
        '[1]</a></p></body></html>';
    const endnotes = '<html><body><p class="footnoteish" id="n1">'
        'Not a note.</p></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true));
    expect(result.links, isEmpty);
    expect(result.auxiliaryFootnotePreviews, isEmpty);
  });

  test('named anchor after unrelated prose is not a note target', () {
    const chapter = '<html><body><p>'
        '<a class="fnref" href="endnotes.xhtml#late">[1]</a>'
        '</p></body></html>';
    const endnotes = '<html><body><div class="footnote">'
        'Unrelated preface. <a name="late"></a>note text.'
        '</div></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true));
    expect(result.auxiliaryFootnotePreviews, isEmpty);
    expect(result.links, isEmpty);
  });

  test('manifest declaration is required even for correctly marked notes', () {
    const chapter = '<html><body><p><a class="fnref" '
        'href="endnotes.xhtml#n1">[1]</a></p></body></html>';
    const endnotes = '<html><body><div id="n1" class="footnote">'
        'Not allowed without a manifest.</div></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true, declared: false));
    expect(result.links, isEmpty);
    expect(result.auxiliaryFootnotePreviews, isEmpty);
  });

  test('multiple legacy references never duplicate auxiliary speech text', () {
    const chapter = '<html><body><p>'
        '<sup><a href="endnotes.xhtml#n1">1</a></sup> and '
        '<a rel="footnote" href="endnotes.xhtml#n1">[1]</a>.'
        '</p></body></html>';
    const endnotes = '<html><body><div class="endnote" id="n1">'
        'One shared note.</div></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter, destination: endnotes, aux: true));
    expect(result.links.length, 2);
    expect(result.auxiliaryFootnotePreviews.length, 1);
    expect(result.text, '1 and [1].');
    expect(result.ranges.length, 1);
  });

  test('oversized legacy auxiliary note fails closed, main book still opens', () {
    final huge = List.filled(400, 'word ').join();
    const chapter = '<html><body><p><a class="fnref" '
        'href="endnotes.xhtml#n1">[1]</a></p></body></html>';
    final result = extractor.extract(legacyBook(
        chapter: chapter,
        destination: '<html><body><div id="n1" class="footnote">'
            '$huge</div></body></html>',
        aux: true));
    expect(result.text, '[1]');
    expect(result.auxiliaryFootnotePreviews, isEmpty);
    expect(result.links, isEmpty);
  });
}
