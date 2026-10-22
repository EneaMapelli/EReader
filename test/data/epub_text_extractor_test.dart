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
      <?xml version="1.0"?>
      <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf"
          media-type="application/oebps-package+xml"/></rootfiles>
      </container>
    '''))
    ..add(ArchiveFile.string('OEBPS/content.opf', opf ?? '''
      <?xml version="1.0" encoding="UTF-8"?>
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
