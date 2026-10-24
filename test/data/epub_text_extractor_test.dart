import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeEpub({
  String? opf,
  String? first,
  String? second,
  String? extraEntry,
}) {
  final archive = Archive()
    ..add(ArchiveFile.noCompress(
      'mimetype',
      'application/epub+zip'.length,
      utf8.encode('application/epub+zip'),
    ))
    ..add(ArchiveFile.string('META-INF/container.xml', '''
      <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf"
          media-type="application/oebps-package+xml"/></rootfiles>
      </container>
    '''))
    ..add(ArchiveFile.string('OEBPS/content.opf', opf ?? '''
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Test Book</dc:title>
        </metadata>
        <manifest>
          <item id="z" href="Text/second%20chapter.xhtml"
                media-type="application/xhtml+xml"/>
          <item id="a" href="Text/first.xhtml"
                media-type="application/xhtml+xml"/>
          <item id="toc" href="nav.xhtml"
                media-type="application/xhtml+xml" properties="nav"/>
        </manifest>
        <spine><itemref idref="a"/><itemref idref="z"/></spine>
      </package>
    '''))
    ..add(ArchiveFile.string(
      'OEBPS/Text/first.xhtml',
      first ?? '<html><body><h1>First</h1><p>Hello reader.</p></body></html>',
    ))
    ..add(ArchiveFile.string(
      'OEBPS/Text/second chapter.xhtml',
      second ?? '<html><body><p>Second page.</p><script>evil()</script></body></html>',
    ))
    ..add(ArchiveFile.string(
      'OEBPS/nav.xhtml',
      '<html><body><nav>Navigation duplicate</nav></body></html>',
    ));
  if (extraEntry != null) {
    archive.add(ArchiveFile.string(extraEntry, 'unsafe'));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  const extractor = EpubTextExtractor();

  test('respects OPF spine instead of manifest file order', () {
    final result = extractor.extract(makeEpub());
    expect(result.title, 'Test Book');
    expect(result.text.indexOf('First'), lessThan(result.text.indexOf('Second')));
    expect(result.text.contains('evil()'), isFalse);
    expect(result.text.contains('Navigation duplicate'), isFalse);
    expect(result.ranges.map((e) => e.idref).toList(), ['a', 'z']);
    for (final range in result.ranges) {
      final snippet = result.text.substring(range.start, range.end);
      expect(snippet.trim(), isNotEmpty);
    }
    expect(result.ranges.first.href, 'OEBPS/Text/first.xhtml');
    expect(result.ranges.last.href, 'OEBPS/Text/second chapter.xhtml');
  });

  test('spine labels use XHTML body headings, not navigation or head', () {
    final archive = makeEpub(
      first: '''
        <html>
          <head><title>Private metadata title</title></head>
          <body>
            <nav><h1>Ignore navigation heading</h1></nav>
            <script><h1>Do not expose script title</h1></script>
            <h2>  A Chapter   with  Spaces </h2>
            <p>Real words for the reader.</p>
          </body>
        </html>
      ''',
    );
    final result = extractor.extract(archive);
    expect(result.ranges.first.title, 'A Chapter with Spaces');
    expect(result.ranges.last.title, 'Chapter 2');
    expect(result.text, contains('Real words for the reader.'));
    expect(result.text, isNot(contains('Private metadata title')));
    expect(result.text, isNot(contains('Ignore navigation heading')));
    expect(result.text, isNot(contains('Do not expose script title')));
  });

  test('chapter headings are bounded and leave source offsets untouched', () {
    final veryLongHeading = List.filled(40, 'Readers').join(' ');
    final result = extractor.extract(makeEpub(
      first: '<html><body><h1>$veryLongHeading</h1><p>Content.</p></body></html>',
    ));
    expect(result.ranges.first.title.length, lessThanOrEqualTo(120));
    expect(result.ranges.first.title, endsWith('…'));
    for (final range in result.ranges) {
      final excerpt = result.text.substring(range.start, range.end);
      expect(excerpt, isNotEmpty);
    }
    expect(result.text, contains(veryLongHeading),
      reason: 'Display-only TOC truncation must not rewrite book text');
  });

  test('semantic XHTML styles map onto unchanged EPUB source text', () {
    final result = extractor.extract(makeEpub(
      first: '<html><body><h1>Prelude</h1><p>A <em>soft '
          '<strong>voice</strong></em> in the dark.</p></body></html>',
      second: '<html><body><p>Second <b>bold</b>.</p></body></html>',
    ));
    final source = result.text;
    expect(source, 'Prelude\n\nA soft voice in the dark.\n\nSecond bold.');
    final heading = result.styles.firstWhere((span) =>
        span.start <= source.indexOf('Prelude') &&
        span.end >= 'Prelude'.length);
    expect(heading.headingLevel, 1);

    final softAt = source.indexOf('soft');
    final soft = result.styles.firstWhere((span) =>
        span.start <= softAt && span.end >= softAt + 4);
    expect(soft.italic, isTrue);
    expect(soft.bold, isFalse);
    final voiceAt = source.indexOf('voice');
    final voice = result.styles.firstWhere((span) =>
        span.start <= voiceAt && span.end >= voiceAt + 5);
    expect(voice.italic, isTrue);
    expect(voice.bold, isTrue);

    final lastBoldAt = source.lastIndexOf('bold');
    final lastBold = result.styles.firstWhere((span) =>
        span.start <= lastBoldAt && span.end >= lastBoldAt + 4);
    expect(lastBold.bold, isTrue);
    expect(lastBold.start, greaterThan(result.ranges.last.start));
    for (final span in result.styles) {
      expect(span.start, greaterThanOrEqualTo(0));
      expect(span.end, lessThanOrEqualTo(source.length));
      expect(span.end, greaterThan(span.start));
    }
  });

  test('repeated words only style the actual tagged occurrence', () {
    final result = extractor.extract(makeEpub(
      first: '<html><body><p>same <i>same</i> same</p></body></html>',
    ));
    final first = result.ranges.first;
    expect(result.text.substring(first.start, first.end), 'same same same');
    final matches = RegExp('same').allMatches(result.text).toList();
    expect(matches.length, 3);
    final italicStarts = result.styles
        .where((span) => span.italic)
        .map((span) => span.start).toList();
    expect(italicStarts, [matches[1].start]);
    expect(italicStarts, isNot(contains(matches[0].start)));
    expect(italicStarts, isNot(contains(matches[2].start)));
  });

  test('scripts, NAV and metadata never become styled reading content', () {
    final result = extractor.extract(makeEpub(
      first: '<html><head><h1>Secret title</h1></head><body>'
          '<nav><h2>Fake navigation</h2></nav>'
          '<style>strong{color:red}</style>'
          '<script><h1>Danger</h1></script>'
          '<p>Safe <strong>content</strong> only.</p>'
          '</body></html>',
    ));
    expect(result.text, isNot(contains('Secret title')));
    expect(result.text, isNot(contains('Fake navigation')));
    expect(result.text, isNot(contains('Danger')));
    final marked = result.styles.where((span) => span.bold).toList();
    expect(marked.length, 1);
    expect(result.text.substring(marked.single.start, marked.single.end),
        'content');
  });

  test('normalization projects markup through stripped whitespace', () {
    final result = extractor.extract(makeEpub(
      first: '<html><body><p>  Before  '
          '<em>text   \n</em><strong>After</strong>  </p></body></html>',
    ));
    final spineText = result.text.substring(
        result.ranges.first.start, result.ranges.first.end);
    expect(spineText, 'Before  text\nAfter');
    final em = result.styles.firstWhere((span) => span.italic);
    final strong = result.styles.firstWhere((span) => span.bold);
    expect(result.text.substring(em.start, em.end), 'text');
    expect(result.text.substring(strong.start, strong.end), 'After');
  });

  test('fails with missing XHTML resource instead of skipping a chapter', () {
    final zip = makeEpub(opf: '''
      <package><manifest>
        <item id="missing" href="missing.xhtml"
              media-type="application/xhtml+xml"/>
      </manifest><spine><itemref idref="missing"/></spine></package>
    ''');
    expect(() => extractor.extract(zip), throwsFormatException);
  });

  test('rejects OPF href escaping ZIP logical root', () {
    final zip = makeEpub(opf: '''
      <package><manifest>
        <item id="attack" href="../../../outside.xhtml"
              media-type="application/xhtml+xml"/>
      </manifest><spine><itemref idref="attack"/></spine></package>
    ''');
    expect(() => extractor.extract(zip), throwsFormatException);
  });

  test('rejects traversal in ZIP archive filenames', () {
    expect(
      () => extractor.extract(makeEpub(extraEntry: '../escape.txt')),
      throwsFormatException,
    );
  });

  test('rejects XML DTDs and entities in OPF', () {
    final zip = makeEpub(opf: '''
      <!DOCTYPE package [ <!ENTITY example "unsafe"> ]>
      <package><metadata><title>&example;</title></metadata></package>
    ''');
    expect(() => extractor.extract(zip), throwsFormatException);
  });

  test('rejects malformed non-ZIP input', () {
    expect(() => extractor.extract(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });
}
