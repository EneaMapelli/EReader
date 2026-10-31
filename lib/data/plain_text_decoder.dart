import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Local, deterministic TXT decoding shared by the visual reader and TTS.
/// Never uploads text, attempts network charset detection or silently replaces
/// damaged UTF-8 when an explicit UTF-8 BOM identifies the file.
///
/// Supported: UTF-8, UTF-8 BOM, UTF-16 LE/BE with BOM, strongly recognizable
/// BOM-less UTF-16 ASCII text, and Windows-1252 as an unmarked legacy fallback.
/// The result is one canonical UTF-16 Dart String for source anchors.
/// Its exact offsets must be preserved across reader/indexer decodes.
String decodePlainTextBytes(List<int> bytes) {
  if (bytes.isEmpty) return '';
  late final String text;
  if (_startsWith(bytes, const [0xef, 0xbb, 0xbf])) {
    try {
      text = utf8.decode(bytes.sublist(3));
    } on FormatException {
      throw const FormatException('Invalid UTF-8 text with a UTF-8 BOM');
    }
  } else if (_startsWith(bytes, const [0xff, 0xfe])) {
    text = _decodeUtf16(bytes, start: 2, littleEndian: true);
  } else if (_startsWith(bytes, const [0xfe, 0xff])) {
    text = _decodeUtf16(bytes, start: 2, littleEndian: false);
  } else {
    final endian = _likelyBomlessUtf16(bytes);
    if (endian != null) {
      text = _decodeUtf16(bytes, start: 0, littleEndian: endian);
    } else {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        // A great deal of older Windows TXT material uses CP1252 rather
        // than UTF-8; decoding with replacement characters loses the
        // dialogue punctuation the speech engines need to interpret.
        text = _decodeWindows1252(bytes);
      }
    }
  }
  _rejectBinaryText(text);
  return text;
}

/// Keep file IO and potentially large encoding work off the Flutter UI
/// isolate. The library import caps source files at 100 MiB, but callers
/// (including test adapters) must still fail safely on larger raw files.
String decodePlainTextFile(String path) {
  final file = File(path);
  if (file.lengthSync() > 100 * 1024 * 1024) {
    throw const FormatException('TXT exceeds the supported 100 MiB limit');
  }
  return decodePlainTextBytes(file.readAsBytesSync());
}

bool _startsWith(List<int> source, List<int> prefix) {
  if (source.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (source[i] != prefix[i]) return false;
  }
  return true;
}

/// Only infer BOM-less UTF-16 where the alternating null bytes make its
/// endianness unambiguous (primarily ASCII/Latin-script text). A UTF-16
/// language without such a pattern requires a BOM to avoid mis-decoding.
bool? _likelyBomlessUtf16(List<int> bytes) {
  if (bytes.length < 16 || bytes.length.isOdd) return null;
  final sample = bytes.length < 4096 ? bytes.length : 4096;
  final pairs = sample ~/ 2;
  var oddZeros = 0;
  var evenZeros = 0;
  for (var i = 0; i < pairs * 2; i += 2) {
    if (bytes[i] == 0) evenZeros++;
    if (bytes[i + 1] == 0) oddZeros++;
  }
  if (oddZeros * 5 >= pairs * 3 && evenZeros * 20 <= pairs) {
    return true;
  }
  if (evenZeros * 5 >= pairs * 3 && oddZeros * 20 <= pairs) {
    return false;
  }
  return null;
}

String _decodeUtf16(List<int> bytes, {
  required int start,
  required bool littleEndian,
}) {
  if ((bytes.length - start).isOdd) {
    throw const FormatException('Odd byte count in UTF-16 TXT');
  }
  // A typed 16-bit buffer uses substantially less transient memory than
  // List<int> for large TXT books. It is built inside a worker isolate.
  final units = Uint16List((bytes.length - start) ~/ 2);
  var pendingHighSurrogate = false;
  for (var unitIndex = 0; unitIndex < units.length; unitIndex++) {
    final offset = start + unitIndex * 2;
    final code = littleEndian
        ? bytes[offset] | (bytes[offset + 1] << 8)
        : (bytes[offset] << 8) | bytes[offset + 1];
    if (code >= 0xd800 && code <= 0xdbff) {
      if (pendingHighSurrogate) {
        throw const FormatException('Invalid UTF-16 surrogate pair');
      }
      pendingHighSurrogate = true;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      if (!pendingHighSurrogate) {
        throw const FormatException('Unexpected UTF-16 low surrogate');
      }
      pendingHighSurrogate = false;
    } else if (pendingHighSurrogate) {
      throw const FormatException('Invalid UTF-16 surrogate pair');
    }
    units[unitIndex] = code;
  }
  if (pendingHighSurrogate) {
    throw const FormatException('Incomplete UTF-16 surrogate pair');
  }
  return String.fromCharCodes(units);
}

const _windows1252C1 = <int>[
  0x20ac, 0x0081, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
  0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008d, 0x017d, 0x008f,
  0x0090, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
  0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x009d, 0x017e, 0x0178,
];

String _decodeWindows1252(List<int> bytes) {
  return String.fromCharCodes([
    for (final b in bytes)
      if (b >= 0x80 && b <= 0x9f)
        _windows1252C1[b - 0x80]
      else
        b,
  ]);
}

void _rejectBinaryText(String text) {
  if (text.isEmpty) return;
  var controlCount = 0;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (code == 0) {
      throw const FormatException('TXT contains binary NUL bytes');
    }
    if ((code < 32 && code != 9 && code != 10 &&
            code != 12 && code != 13) ||
        (code >= 0x7f && code <= 0x9f)) {
      controlCount++;
    }
  }
  // A few legacy control characters are tolerated. A block with >5%
  // non-text controls is almost certainly a mislabeled binary asset.
  if (controlCount * 20 > text.length) {
    throw const FormatException('File does not appear to contain plain text');
  }
}
