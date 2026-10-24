import 'dart:convert';
import 'dart:typed_data';

/// Strict, bounded text decoding for EPUB ZIP resources.
///
/// UTF-8 remains the default. Legacy Windows-1252/ISO-8859-1 are accepted
/// **only when explicitly declared** in XML or HTML metadata; never guessed
/// from failed UTF-8. UTF-16 requires a BOM or recognizable XML signature.
/// All output is Dart UTF-16 text, so downstream source offsets are computed
/// from the decoded string rather than the bytes inside the ZIP.
String decodeEpubTextResource(Uint8List bytes, {required int maxBytes}) {
  if (bytes.length > maxBytes) {
    throw const FormatException('EPUB resource exceeds decoding budget');
  }
  if (bytes.isEmpty) return '';

  var bom = '';
  var skip = 0;
  if (_startsWith(bytes, const [0xef, 0xbb, 0xbf])) {
    bom = 'utf-8';
    skip = 3;
  } else if (_startsWith(bytes, const [0xff, 0xfe])) {
    bom = 'utf-16le';
    skip = 2;
  } else if (_startsWith(bytes, const [0xfe, 0xff])) {
    bom = 'utf-16be';
    skip = 2;
  }

  // XML sometimes uses UTF-16 without a BOM but begins with "<?".
  // Do not infer UTF-16 from arbitrary binary content.
  var implicitUtf16 = false;
  if (bom.isEmpty && bytes.length >= 4) {
    if (_startsWith(bytes, const [0x3c, 0x00, 0x3f, 0x00])) {
      bom = 'utf-16le';
      implicitUtf16 = true;
    } else if (_startsWith(bytes, const [0x00, 0x3c, 0x00, 0x3f])) {
      bom = 'utf-16be';
      implicitUtf16 = true;
    }
  }

  String decoded;
  if (bom == 'utf-16le' || bom == 'utf-16be') {
    decoded = _decodeUtf16(bytes, offset: skip, bigEndian: bom == 'utf-16be');
  } else {
    // The Latin-1 decoding of a limited ASCII-compatible header lets us
    // inspect a declared charset without decoding arbitrary payload bytes.
    final prefix = latin1.decode(bytes.sublist(skip,
        bytes.length < 4096 ? bytes.length : 4096));
    final encoding = _declaredEncoding(prefix);
    if (encoding == null || encoding == 'utf-8') {
      decoded = utf8.decode(bytes.sublist(skip), allowMalformed: false);
    } else if (encoding == 'windows-1252') {
      decoded = _decodeWindows1252(bytes, skip);
    } else if (encoding == 'iso-8859-1') {
      decoded = latin1.decode(bytes.sublist(skip));
    } else {
      throw const FormatException('Unsupported EPUB text encoding');
    }
  }

  if (decoded.startsWith('\uFEFF')) decoded = decoded.substring(1);
  if (decoded.contains('\u0000')) {
    throw const FormatException('EPUB text resource contains NUL');
  }
  final declared = _declaredEncoding(decoded.length > 4096
      ? decoded.substring(0, 4096) : decoded);
  if (bom.isNotEmpty) {
    if (implicitUtf16 && declared == null) {
      throw const FormatException('Undeclared UTF-16 EPUB resource');
    }
    if (declared != null && !_compatible(bom, declared)) {
      throw const FormatException('EPUB BOM and charset declaration disagree');
    }
  }
  return decoded;
}

bool _startsWith(Uint8List data, List<int> prefix) {
  if (data.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}

String? _normalizeEncoding(String raw) {
  final label = raw.trim().toLowerCase().replaceAll('_', '-');
  switch (label) {
    case 'utf8':
    case 'utf-8':
      return 'utf-8';
    case 'utf-16':
    case 'utf16':
      return 'utf-16';
    case 'utf-16le':
    case 'utf16le':
      return 'utf-16le';
    case 'utf-16be':
    case 'utf16be':
      return 'utf-16be';
    case 'windows-1252':
    case 'windows1252':
    case 'cp1252':
    case 'x-cp1252':
      return 'windows-1252';
    case 'iso-8859-1':
    case 'iso8859-1':
    case 'latin1':
    case 'latin-1':
      return 'iso-8859-1';
    default:
      return label; // Reject unknown declarations instead of guessing.
  }
}

bool _compatible(String effective, String declared) =>
    effective == declared ||
    declared == 'utf-16' &&
        (effective == 'utf-16le' || effective == 'utf-16be');

String? _declaredEncoding(String prefix) {
  // XML encoding declaration is authoritative when present.
  final xml = RegExp(r'''<\?xml\b[^>]*\bencoding\s*=\s*(?:"([^"]+)"|'([^']+)')''',
      caseSensitive: false, dotAll: true).firstMatch(prefix);
  final xmlEncoding = xml == null ? null
      : _normalizeEncoding(xml.group(1) ?? xml.group(2)!);

  String? htmlEncoding;
  for (final tag in RegExp(r'<meta\b[^>]*>', caseSensitive: false,
      dotAll: true).allMatches(prefix)) {
    final meta = tag.group(0)!;
    final match = RegExp(
      r'''(?:^|[\s;])charset\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s"';/>]+))''',
      caseSensitive: false,
    ).firstMatch(meta);
    if (match == null) continue;
    final detected = _normalizeEncoding(
        match.group(1) ?? match.group(2) ?? match.group(3)!);
    if (htmlEncoding != null && htmlEncoding != detected) {
      throw const FormatException('Conflicting EPUB meta charsets');
    }
    htmlEncoding = detected;
  }
  if (xmlEncoding != null && htmlEncoding != null &&
      xmlEncoding != htmlEncoding) {
    throw const FormatException('Conflicting EPUB XML/HTML charsets');
  }
  return xmlEncoding ?? htmlEncoding;
}

// Windows-1252 byte range 0x80..0x9f; undefined entries are invalid,
// never replacement characters that would silently rewrite book text.
const _cp1252 = <int>[
  0x20ac, -1, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
  0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, -1, 0x017d, -1,
  -1, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
  0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, -1, 0x017e, 0x0178,
];

String _decodeWindows1252(Uint8List bytes, int offset) {
  final result = StringBuffer();
  for (var i = offset; i < bytes.length; i++) {
    final byte = bytes[i];
    final codepoint = byte >= 0x80 && byte <= 0x9f
        ? _cp1252[byte - 0x80] : byte;
    if (codepoint < 0) {
      throw const FormatException('Undefined Windows-1252 character');
    }
    result.writeCharCode(codepoint);
  }
  return result.toString();
}

String _decodeUtf16(Uint8List bytes, {required int offset,
    required bool bigEndian}) {
  if ((bytes.length - offset).isOdd) {
    throw const FormatException('Odd UTF-16 EPUB byte count');
  }
  final result = StringBuffer();
  int unit(int pos) => bigEndian
      ? bytes[pos] << 8 | bytes[pos + 1]
      : bytes[pos + 1] << 8 | bytes[pos];
  for (var pos = offset; pos < bytes.length; pos += 2) {
    final current = unit(pos);
    if (current >= 0xd800 && current <= 0xdbff) {
      if (pos + 3 >= bytes.length) {
        throw const FormatException('Truncated UTF-16 surrogate');
      }
      final next = unit(pos + 2);
      if (next < 0xdc00 || next > 0xdfff) {
        throw const FormatException('Malformed UTF-16 surrogate pair');
      }
      final codepoint = 0x10000 +
          ((current - 0xd800) << 10) + (next - 0xdc00);
      result.writeCharCode(codepoint);
      pos += 2;
    } else if (current >= 0xdc00 && current <= 0xdfff) {
      throw const FormatException('Lone UTF-16 low surrogate');
    } else {
      result.writeCharCode(current);
    }
  }
  return result.toString();
}
