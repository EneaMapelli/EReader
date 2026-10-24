import 'dart:typed_data';

import 'package:ereader/data/epub_embedded_content.dart';
import 'package:ereader/data/epub_structural_markup.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List samplePng({int width = 1, int height = 1}) {
  // Signature + IHDR start/width/height. The header validator does not
  // claim to replace the Flutter PNG decoder or validate image CRCs.
  final bytes = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10,
    0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1,
    8, 6, 0, 0, 0, 0, 0, 0, 0,
  ]);
  bytes[16] = width >> 24 & 255;
  bytes[17] = width >> 16 & 255;
  bytes[18] = width >> 8 & 255;
  bytes[19] = width & 255;
  bytes[20] = height >> 24 & 255;
  bytes[21] = height >> 16 & 255;
  bytes[22] = height >> 8 & 255;
  bytes[23] = height & 255;
  return bytes;
}

void main() {
  test('body image and fragment offsets agree with canonical UTF-16 text', () {
    const text = 'Before 📖 after';
    final result = extractEpubStructure(
      '<html><body><p id="top">Before 📖 '
      '<img src="../Images/figure.png" alt="Figure 1"/>'
      '<a href="#top">after</a></p></body></html>',
      text,
    );
    expect(result.images.length, 1);
    expect(result.images.single.offset, text.indexOf('after'));
    expect(result.images.single.alt, 'Figure 1');
    expect(result.targets.single.id, 'top');
    expect(result.targets.single.offset, 0);
    expect(result.links.single.start, text.indexOf('after'));
    expect(result.links.single.end, text.length);
    expect(result.links.single.href, '#top');
  });

  test('table rows are bounded and do not alter flattened TTS source', () {
    const text = 'Report\n\nNorth10South20';
    final info = extractEpubStructure(
      '<html><body><h2>Report</h2>'
      '<table><tr><th>North</th><td>10</td></tr>'
      '<tr><th>South</th><td>20</td></tr></table></body></html>',
      text,
    );
    expect(info.tables.length, 1);
    expect(info.tables.single.rows, [
      ['North', '10'],
      ['South', '20'],
    ]);
    expect(info.tables.single.start, text.indexOf('North'));
    expect(info.tables.single.end, text.length);
  });

  test('hidden nodes and mismatched source suppress every marker', () {
    const xhtml = '<html><body><nav><a href="#secret">Hidden</a></nav>'
        '<script><img src="evil.png"/></script>'
        '<p><a href="#actual">Read</a></p></body></html>';
    final good = extractEpubStructure(xhtml, 'Read');
    expect(good.links.length, 1);
    expect(good.images, isEmpty);
    final mismatched = extractEpubStructure(xhtml, 'Changed');
    expect(mismatched.links, isEmpty);
    expect(mismatched.targets, isEmpty);
  });

  test('structure projection accounts for removed pre-newline whitespace', () {
    const original = 'Before\nAfter';
    final info = extractEpubStructure(
      '<html><body><p>Before  \n</p>'
      '<p id="after"><a href="#after">After</a></p></body></html>',
      original,
    );
    expect(info.targets.single.offset, original.indexOf('After'));
    expect(info.links.single.start, original.indexOf('After'));
    expect(info.links.single.end, original.length);
  });

  test('raster allowlist enforces MIME, magic, pixel and byte limits', () {
    final good = samplePng();
    expect(isSafeEpubRaster(good, 'image/png'), isTrue);
    expect(isSafeEpubRaster(good, 'image/jpeg'), isFalse);
    expect(isSafeEpubRaster(samplePng(width: 10000), 'image/png'), isFalse);
    expect(isSafeEpubRaster(samplePng(width: 4096, height: 4096),
        'image/png'), isFalse);
    expect(isSafeEpubRaster(Uint8List(5), 'image/png'), isFalse);
    expect(isSafeEpubRaster(Uint8List(1024), 'image/png'), isFalse);
  });
}
