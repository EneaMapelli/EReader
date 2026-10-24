import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_navigation.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fixture({
  required String opf,
  required String first,
  required String second,
  String? nav,
  String? ncx,
}) {
  final archive = Archive()
    ..add(ArchiveFile.noCompress('mimetype',
        'application/epub+zip'.length, utf8.encode('application/epub+zip')))
    ..add(ArchiveFile.string('META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/book.opf', opf))
    ..add(ArchiveFile.string('OPS/Text/first.xhtml', first))
    ..add(ArchiveFile.string('OPS/Text/second.xhtml', second));
  if (nav != null) archive.add(ArchiveFile.string('OPS/nav.xhtml', nav));
  if (ncx != null) archive.add(ArchiveFile.string('OPS/toc.ncx', ncx));
  return ZipEncoder().encodeBytes(archive);
}

const firstDoc = '<html><body><h1 id="intro">Introduction</h1>'
    '<p>Some introductory words.</p>'
    '<p><a epub:type="noteref" href="second.xhtml#note-1">[1]</a></p>'
    '</body></html>';
const secondDoc = '<html><body><h2 id="chapter">The Chapter</h2>'
    '<p>Actual content.</p><aside id="note-1" epub:type="footnote">'
    '<p>Note explanation.</p></aside></body></html>';

const epub3Opf = '''
<package version="3.0">
  <metadata><title>Navigation</title></metadata>
  <manifest>
    <item id="a" href="Text/first.xhtml" media-type="application/xhtml+xml"/>
    <item id="b" href="Text/second.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"
        properties="nav"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="a"/><itemref idref="b"/></spine>
</package>''';
const epub2Opf = '''
<package version="2.0">
  <metadata><title>Navigation</title></metadata>
  <manifest>
    <item id="a" href="Text/first.xhtml" media-type="application/xhtml+xml"/>
    <item id="b" href="Text/second.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="a"/><itemref idref="b"/></spine>
</package>''';
const nav = '''
<html xmlns:epub="http://www.idpf.org/2007/ops"><body>
  <nav epub:type="landmarks"><ol><li><a href="https://outside.example/">Bad</a></li></ol></nav>
  <nav epub:type="toc"><h2>Contents</h2><ol>
    <li><a href="Text/first.xhtml#intro">Introduction</a>
      <ol>
        <li><a href="Text/second.xhtml#chapter">Chapter 1</a></li>
        <li><a href="Text/second.xhtml#note-1">Notes</a></li>
      </ol>
    </li>
    <li><a href="Text/missing.xhtml#broken">Missing</a></li>
    <li><a href="https://example.org/">External</a></li>
  </ol></nav>
</body></html>''';
const ncx = '''
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <navMap>
    <navPoint id="one"><navLabel><text>Introduction</text></navLabel>
      <content src="Text/first.xhtml#intro"/>
      <navPoint id="two"><navLabel><text>Chapter 1</text></navLabel>
        <content src="Text/second.xhtml#chapter"/>
      </navPoint>
    </navPoint>
    <navPoint id="external"><navLabel><text>Outside</text></navLabel>
      <content src="https://example.org/"/>
    </navPoint>
  </navMap>
</ncx>''';

void main() {
  const decoder = EpubTextExtractor();

  test('EPUB3 nested NAV TOC parses in editorial order with depth', () {
    final raw = parseEpub3Navigation(nav);
    expect(raw.map((e) => e.label).toList(), [
      'Introduction', 'Chapter 1', 'Notes', 'Missing', 'External',
    ]);
    expect(raw.map((e) => e.depth).toList(), [0, 1, 1, 0, 0]);
    expect(raw.any((e) => e.label == 'Bad'), isFalse,
        reason: 'landmarks is not the TOC');
  });

  test('EPUB3 NAV resolves only fragments in the readable OPF spine', () {
    final result = decoder.extract(fixture(
      opf: epub3Opf, first: firstDoc, second: secondDoc,
      nav: nav, ncx: ncx,
    ));
    expect(result.navigation.map((e) => e.label).toList(),
        ['Introduction', 'Chapter 1', 'Notes']);
    expect(result.navigation.map((e) => e.depth).toList(), [0, 1, 1]);
    expect(result.navigation[0].offset, result.ranges[0].start);
    expect(result.navigation[1].offset, result.ranges[1].start);
    expect(result.text.substring(result.navigation[2].offset),
        contains('Note explanation.'));
    expect(result.links.length, 1);
    expect(result.links.single.isFootnote, isTrue);
    expect(result.links.single.targetOffset,
        greaterThan(result.ranges[1].start));
  });

  test('semantic in-spine footnote creates source-exact plain text preview', () {
    final result = decoder.extract(fixture(
      opf: epub3Opf, first: firstDoc, second: secondDoc,
      nav: nav,
    ));
    expect(result.footnotePreviews.length, 1);
    final note = result.footnotePreviews.single;
    expect(note.targetOffset, result.links.single.targetOffset);
    expect(note.text, 'Note explanation.');
    expect(result.text.substring(note.targetOffset),
        contains(note.text));
    expect(result.links.single.isFootnote, isTrue);
  });

  test('ordinary internal link without semantic note offers no preview', () {
    final result = decoder.extract(fixture(
      opf: epub2Opf,
      first: '<html><body><p>Read '
        '<a href="second.xhtml#chapter">more</a>.</p></body></html>',
      second: '<html><body><p id="chapter">A plain paragraph.</p></body></html>',
    ));
    expect(result.links.length, 1);
    expect(result.links.single.isFootnote, isFalse);
    expect(result.footnotePreviews, isEmpty);
  });

  test('oversize note falls back to safe link navigation and preserves source', () {
    final longNote = List.filled(300, 'word ').join();
    final source = '<html><body><aside id="big" epub:type="footnote">'
        '<p>$longNote</p></aside></body></html>';
    final result = decoder.extract(fixture(
      opf: epub2Opf,
      first: '<html><body><p>See '
        '<a epub:type="noteref" href="second.xhtml#big">[1]</a>.</p></body></html>',
      second: source,
    ));
    expect(result.footnotePreviews, isEmpty);
    expect(result.links.single.isFootnote, isTrue);
    expect(result.text, contains(longNote));
  });

  test('EPUB2 NCX navPoint nesting maps to the same source anchors', () {
    final parsed = parseEpub2Ncx(ncx);
    expect(parsed.map((e) => e.label).toList(),
        ['Introduction', 'Chapter 1', 'Outside']);
    expect(parsed.map((e) => e.depth).toList(), [0, 1, 0]);
    final result = decoder.extract(fixture(
      opf: epub2Opf, first: firstDoc, second: secondDoc, ncx: ncx,
    ));
    expect(result.navigation.map((e) => e.label).toList(),
        ['Introduction', 'Chapter 1']);
    expect(result.navigation.map((e) => e.offset).toList(),
        [result.ranges[0].start, result.ranges[1].start]);
  });

  test('broken EPUB3 NAV falls back to valid EPUB2 NCX', () {
    final result = decoder.extract(fixture(
      opf: epub3Opf, first: firstDoc, second: secondDoc,
      nav: '<html><body><nav epub:type="landmarks"></nav></body></html>',
      ncx: ncx,
    ));
    expect(result.navigation.map((e) => e.label).toList(),
        ['Introduction', 'Chapter 1']);
  });

  test('missing optional NAV/NCX yields no editor entries, not import failure', () {
    final result = decoder.extract(fixture(
      opf: epub3Opf, first: firstDoc, second: secondDoc,
    ));
    expect(result.navigation, isEmpty);
    expect(result.text, contains('Some introductory words.'));
    expect(result.ranges.length, 2);
  });

  test('NCX DTD and external entities are rejected without network fetch', () {
    expect(parseEpub2Ncx('<!DOCTYPE ncx [<!ENTITY x SYSTEM '
        '"https://outside.example/a">]><ncx>&x;</ncx>'), isEmpty);
    expect(parseEpub2Ncx('<ncx><navMap>'), isEmpty);
  });

  test('current editorial section uses nearest preceding source offset', () {
    const entries = [
      EpubNavigationEntry('Later', 120, 0),
      EpubNavigationEntry('Start', 0, 0),
      EpubNavigationEntry('Middle', 40, 1),
      EpubNavigationEntry('Duplicate', 40, 2),
    ];
    expect(navigationIndexForOffset(entries, 0), 1);
    expect(navigationIndexForOffset(entries, 65), 2);
    expect(navigationIndexForOffset(entries, 180), 0);
    expect(navigationIndexForOffset(entries, -5), 0);
    expect(navigationIndexForOffset(const [], 10), -1);
  });

  test('path-only TOC anchors select the start of the target spine file', () {
    final custom = nav.replaceFirst('Text/second.xhtml#chapter',
        'Text/second.xhtml');
    final result = decoder.extract(fixture(
      opf: epub3Opf, first: firstDoc, second: secondDoc,
      nav: custom,
    ));
    expect(result.navigation[1].offset, result.ranges[1].start);
  });

  test('hostile URL schemes and traversal are ignored from NAV', () {
    const malicious = '''
      <html><body><nav epub:type="toc"><ol>
        <li><a href="javascript:alert(1)">Script</a></li>
        <li><a href="file:///secret">File</a></li>
        <li><a href="../../../../etc/passwd">Escape</a></li>
        <li><a href="Text/first.xhtml#intro">Valid</a></li>
      </ol></nav></body></html>''';
    final result = decoder.extract(fixture(
      opf: epub3Opf, first: firstDoc, second: secondDoc,
      nav: malicious,
    ));
    expect(result.navigation.map((e) => e.label).toList(), ['Valid']);
  });

  test('source content and speech offsets are unchanged by TOC extraction', () {
    final without = decoder.extract(fixture(
      opf: epub2Opf, first: firstDoc, second: secondDoc,
    ));
    final withToc = decoder.extract(fixture(
      opf: epub2Opf, first: firstDoc, second: secondDoc, ncx: ncx,
    ));
    expect(withToc.text, without.text);
    expect(withToc.ranges.map((r) => [r.start, r.end]).toList(),
        without.ranges.map((r) => [r.start, r.end]).toList());
  });
}
