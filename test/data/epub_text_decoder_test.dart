import 'dart:convert';
import 'dart:typed_data';

import 'package:ereader/data/epub_text_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List utf16Resource(String text, {required bool littleEndian,
    bool bom = true}) {
  final bytes = <int>[
    if (bom) ...(littleEndian ? const [0xff, 0xfe] : const [0xfe, 0xff]),
  ];
  for (final unit in text.codeUnits) {
    if (littleEndian) {
      bytes.addAll([unit & 0xff, unit >> 8]);
    } else {
      bytes.addAll([unit >> 8, unit & 0xff]);
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  String decode(List<int> value, {int max = 100000}) =>
      decodeEpubTextResource(Uint8List.fromList(value), maxBytes: max);

  test('UTF-8 remains the strict default, preserving emoji code units', () {
    const text = '<html><body>Città 📖 京都</body></html>';
    expect(decode(utf8.encode(text)), text);
    expect(decode([0xef, 0xbb, 0xbf, ...utf8.encode(text)]), text);
    expect(text.indexOf('京都'), greaterThan(text.indexOf('📖')));
  });

  test('Windows-1252 declaration decodes smart quotes and euro', () {
    const before = '<html><head><meta charset="windows-1252"></head>'
        '<body><p>';
    const after = '</p></body></html>';
    final result = decode([
      ...ascii.encode(before),
      0x93, ...ascii.encode('Here'), 0x94, 0x20, 0x80,
      ...ascii.encode(after),
    ]);
    expect(result, contains('“Here” €'));
    expect(result.contains('\uFFFD'), isFalse);
  });

  test('Windows-1252 XML encoding declaration works without BOM', () {
    const first = '<?xml version="1.0" encoding="cp1252"?>'
        '<html><body>';
    const end = '</body></html>';
    expect(decode([...ascii.encode(first), 0x97, ...ascii.encode(end)]),
        contains('—'));
  });

  test('ISO-8859-1 declared HTML remains Latin-1 rather than CP1252', () {
    const text = '<html><head><meta charset=ISO-8859-1></head>'
        '<body>Più città, café.</body></html>';
    expect(decode(latin1.encode(text)), text);
    final encodedControl = latin1.encode(
        '<meta charset="latin1"><body>'); 
    expect(decode([...encodedControl, 0x80, ...ascii.encode('</body>')])
        .codeUnits.contains(0x80), isTrue);
  });

  test('HTML http-equiv charset declaration is recognized', () {
    const head = '<html><head><meta http-equiv="Content-Type" '
        'content="text/html; charset=windows-1252"></head><body>';
    expect(decode([...ascii.encode(head), 0x99, ...ascii.encode('</body>')]),
        contains('™'));
  });

  test('UTF-16LE/BE BOMs decode supplementary-plane characters', () {
    const xhtml = '<?xml version="1.0" encoding="UTF-16"?>'
        '<html><body>É 📖</body></html>';
    expect(decode(utf16Resource(xhtml, littleEndian: true)), xhtml);
    expect(decode(utf16Resource(xhtml, littleEndian: false)), xhtml);
  });

  test('recognizable UTF-16 XML signature works with explicit declaration', () {
    const xhtml = '<?xml encoding="UTF-16LE"?>'
        '<html><body>你好</body></html>';
    expect(decode(utf16Resource(xhtml,
        littleEndian: true, bom: false)), xhtml);
    const noEncoding = '<?xml version="1.0"?><html/>';
    expect(() => decode(utf16Resource(noEncoding,
        littleEndian: true, bom: false)), throwsFormatException);
  });

  test('malformed UTF-8 and undefined Windows-1252 bytes fail closed', () {
    expect(() => decode([0x3c, 0x80, 0x3e]), throwsFormatException);
    const header = '<meta charset="windows-1252"><body>';
    expect(() => decode([...ascii.encode(header), 0x81]),
        throwsFormatException);
  });

  test('bad UTF-16 odd bytes and lone surrogates are rejected', () {
    expect(() => decode([0xff, 0xfe, 0x3c]), throwsFormatException);
    expect(() => decode([0xff, 0xfe, 0x00, 0xd8]),
        throwsFormatException);
    expect(() => decode([0xfe, 0xff, 0xdc, 0x00]),
        throwsFormatException);
  });

  test('contradictory BOM and declaration, or unknown charset, fail', () {
    const body = '<?xml encoding="windows-1252"?><html/>';
    expect(() => decode([0xef, 0xbb, 0xbf, ...ascii.encode(body)]),
        throwsFormatException);
    const unsupported = '<meta charset="shift_jis"><body>Text</body>';
    expect(() => decode(ascii.encode(unsupported)), throwsFormatException);
  });

  test('conflicting XML and HTML meta charsets do not guess', () {
    const bad = '<?xml encoding="utf-8"?>'
        '<html><head><meta charset="windows-1252"></head></html>';
    expect(() => decode(ascii.encode(bad)), throwsFormatException);
  });

  test('empty resource, byte budget, and NUL payload', () {
    expect(decode([]), '');
    expect(() => decode(ascii.encode('A too long body'), max: 5),
        throwsFormatException);
    expect(() => decode([60, 0, 62]), throwsFormatException);
  });
}
