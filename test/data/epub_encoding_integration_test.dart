import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List epubWithChapter(Uint8List chapterBytes) {
  final archive = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/>'
      '</rootfiles></container>'))
    ..add(ArchiveFile.string('OEBPS/content.opf',
      '<package><metadata><title>Encoding fixtures</title></metadata>'
      '<manifest><item id="a" href="Text/chapter.xhtml" '
      'media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="a"/></spine></package>'))
    ..add(ArchiveFile('OEBPS/Text/chapter.xhtml',
      chapterBytes.length, chapterBytes));
  return ZipEncoder().encodeBytes(archive);
}

Uint8List utf16Xhtml(String source, {bool bigEndian = false}) {
  final bytes = <int>[if (bigEndian) ...[0xfe, 0xff] else ...[0xff, 0xfe]];
  for (final ch in source.codeUnits) {
    if (bigEndian) {
      bytes.addAll([ch >> 8, ch & 0xff]);
    } else {
      bytes.addAll([ch & 0xff, ch >> 8]);
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  const extractor = EpubTextExtractor();

  test('declared Windows-1252 chapter keeps punctuation and style offsets', () {
    const first = '<html><head><meta charset="windows-1252"></head><body>'
        '<h1>Legacy ';
    const rest = '</h1><p>See <em>price';
    const finish = '</em> now.</p></body></html>';
    final chapter = Uint8List.fromList([
      ...ascii.encode(first), 0x80, ...ascii.encode(rest),
      0x97, ...ascii.encode(finish),
    ]);
    final result = extractor.extract(epubWithChapter(chapter));
    expect(result.ranges.single.title, 'Legacy €');
    expect(result.text, 'Legacy €\n\nSee price— now.');
    final offset = result.text.indexOf('price');
    expect(result.styles.any((style) =>
        style.italic && style.start <= offset &&
        style.end >= offset + 5), isTrue);
    expect(result.text.contains('\uFFFD'), isFalse);
    expect(result.ranges.single.end, result.text.length);
  });

  test('declared Latin-1 EPUB preserves accented Unicode positions', () {
    const html = '<html><head><meta charset="ISO-8859-1"></head><body>'
        '<p>Città, caffè e più.</p></body></html>';
    final result = extractor.extract(
        epubWithChapter(Uint8List.fromList(latin1.encode(html))));
    expect(result.text, 'Città, caffè e più.');
    expect(result.text.indexOf('caffè'), 7);
    expect(result.ranges.single.start, 0);
  });

  test('UTF-16LE and BE XHTML chapters yield the same spoken source', () {
    const html = '<?xml version="1.0" encoding="UTF-16"?>'
        '<html><body><h2>世界 📖</h2><p>Un testo.</p></body></html>';
    final left = extractor.extract(
        epubWithChapter(utf16Xhtml(html)));
    final right = extractor.extract(
        epubWithChapter(utf16Xhtml(html, bigEndian: true)));
    expect(left.text, right.text);
    expect(left.text, '世界 📖\n\nUn testo.');
    expect(left.ranges.single.title, '世界 📖');
    final emoji = left.text.indexOf('📖');
    expect(left.text.substring(emoji, emoji + 2), '📖',
        reason: 'Original UTF-16 source indices include surrogate pairs');
    expect(right.ranges.single.end, left.ranges.single.end);
  });

  test('attributed XHTML br shares exact offsets across voice and styles', () {
    const html = '<html><body>'
        '<p>First<br clear="all" title="greater > sign"/>'
        'Second <strong>bold</strong> '
        '<a href="#target">jump</a>.</p>'
        '<p id="target">Target.</p>'
        '</body></html>';
    final result = extractor.extract(
        epubWithChapter(Uint8List.fromList(utf8.encode(html))));
    expect(result.text, 'First\nSecond bold jump.\n\nTarget.');
    final boldAt = result.text.indexOf('bold');
    expect(result.styles.any((style) =>
      style.bold && style.start <= boldAt &&
      style.end >= boldAt + 4), isTrue);
    final link = result.links.single;
    expect(result.text.substring(link.start, link.end), 'jump');
    expect(link.targetOffset, result.text.indexOf('Target.'));
    expect(result.ranges.single.end, result.text.length);
  });

  test('malformed legacy chapter never inserts replacement characters', () {
    const start = '<html><head><meta charset="windows-1252"></head>'
        '<body><p>';
    final bytes = Uint8List.fromList([
      ...ascii.encode(start), 0x81, ...ascii.encode('</p></body></html>'),
    ]);
    expect(() => extractor.extract(epubWithChapter(bytes)),
        throwsFormatException);
  });

  test('malformed UTF-16 encoding fails even when spine manifest is valid', () {
    expect(() => extractor.extract(epubWithChapter(
      Uint8List.fromList([0xff, 0xfe, 0x00, 0xd8]))),
      throwsFormatException);
  });
}
