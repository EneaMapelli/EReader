import 'dart:convert';

import 'package:ereader/data/plain_text_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> utf16Bytes(String input, {required bool littleEndian, bool bom = true}) {
  return <int>[
    if (bom) ...(littleEndian ? [0xff, 0xfe] : [0xfe, 0xff]),
    for (final unit in input.codeUnits) ...[
      if (littleEndian) unit & 0xff else unit >> 8,
      if (littleEndian) unit >> 8 else unit & 0xff,
    ],
  ];
}

void main() {
  test('normal UTF-8 remains unchanged, including punctuation and emoji', () {
    const source = '“Ciao,” disse Eva. 🐉\nLettura veloce.';
    expect(decodePlainTextBytes(utf8.encode(source)), source);
    expect(decodePlainTextBytes([0xef, 0xbb, 0xbf, ...utf8.encode(source)]),
        source);
    expect(decodePlainTextBytes([]), isEmpty);
    expect(decodePlainTextBytes([0x43, 0x69, 0x61, 0x6f]), 'Ciao');
  });

  test('UTF-16 BOM decodes both endiannesses and preserves UTF-16 offsets',
      () {
    const source = 'Ciao 🐉! “Buona lettura.”';
    for (final endian in [true, false]) {
      final decoded = decodePlainTextBytes(
          utf16Bytes(source, littleEndian: endian));
      expect(decoded, source);
      expect(decoded.indexOf('!'), 7);
      expect(decoded.codeUnits, source.codeUnits);
    }
  });

  test('BOM-less UTF-16 uses conservative alternating zero heuristic', () {
    const source = 'Una storia in lingua italiana e un capitolo';
    expect(decodePlainTextBytes(
        utf16Bytes(source, littleEndian: true, bom: false)), source);
    expect(decodePlainTextBytes(
        utf16Bytes(source, littleEndian: false, bom: false)), source);
  });

  test('old Windows-1252 letters and curly speech punctuation survive',
      () {
    // `L’été — “Ciao” … 20€` as Windows-1252.
    final data = <int>[
      0x4c, 0x92, 0xe9, 0x74, 0xe9, 0x20, 0x97, 0x20,
      0x93, 0x43, 0x69, 0x61, 0x6f, 0x94, 0x20, 0x85,
      0x20, 0x32, 0x30, 0x80,
    ];
    expect(decodePlainTextBytes(data), 'L’été — “Ciao” … 20€');
  });

  test('unmarked Latin-1 accented text uses the same CP1252 fallback', () {
    expect(decodePlainTextBytes(<int>[0x43, 0x61, 0x66, 0xe9]), 'Café');
  });

  test('declared UTF-8 with malformed sequence does not silently replace',
      () {
    expect(() => decodePlainTextBytes(<int>[
      0xef, 0xbb, 0xbf, 0x42, 0xc3, 0x28,
    ]), throwsFormatException);
  });

  test('incomplete UTF-16 and invalid surrogates fail closed', () {
    expect(() => decodePlainTextBytes([0xff, 0xfe, 0x43]),
        throwsFormatException);
    expect(() => decodePlainTextBytes([0xfe, 0xff, 0xd8, 0x3d]),
        throwsFormatException);
    expect(() => decodePlainTextBytes([0xff, 0xfe, 0x00, 0xdc]),
        throwsFormatException);
    expect(() => decodePlainTextBytes([0xff, 0xfe, 0x00, 0xd8, 0x43, 0x00]),
        throwsFormatException);
  });

  test('binary bytes masquerading as TXT are rejected', () {
    expect(() => decodePlainTextBytes(List.filled(35, 0)), throwsFormatException);
    expect(() => decodePlainTextBytes(<int>[0x50, 0x4b, ...List.filled(48, 1)]),
        throwsFormatException);
    expect(() => decodePlainTextBytes(
      [0x47, 0x49, 0x46, 0x38, 0x00, 0x01, 0x00, 0x80],
    ), throwsFormatException);
  });

  test('line breaks and form-feed remain usable in old TXT books', () {
    const source = 'Capitolo uno\r\n\r\nPagina due\f\tFine.';
    expect(decodePlainTextBytes(utf8.encode(source)), source);
  });
}
