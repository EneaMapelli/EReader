import 'dart:typed_data';

/// Local, bounded raster content; there is no URL/network fallback.
class EpubEmbeddedImage {
  const EpubEmbeddedImage({
    required this.offset,
    required this.bytes,
    required this.alt,
    required this.resourcePath,
    this.spineIdref,
  });
  final int offset;
  final Uint8List bytes;
  final String alt;
  final String resourcePath;
  /// OPF identity disambiguates illustrated sections with the same empty
  /// UTF-16 source offset. Display-only; it never enters spoken text.
  final String? spineIdref;
}

class EpubInternalLink {
  const EpubInternalLink(this.start, this.end, this.targetOffset, {
    this.isFootnote = false,
    this.auxiliaryFootnoteKey,
  });
  final int start;
  final int end;
  /// Non-null only for a real, readable OPF-spine destination.
  final int? targetOffset;
  final bool isFootnote;
  /// A verified, referenced, non-spine note has no book/TTS offset.
  final String? auxiliaryFootnoteKey;
}

/// Plain-text preview of a verified semantic footnote already present in
/// the original EPUB speech text. There is no HTML, CSS or network payload.
class EpubFootnotePreview {
  const EpubFootnotePreview(this.targetOffset, this.text);
  final int targetOffset;
  final String text;
}

/// An auxiliary note deliberately has no source offset: opening it must
/// never insert text into the EPUB spine or change TTS/SQLite progress.
class EpubAuxiliaryFootnotePreview {
  const EpubAuxiliaryFootnotePreview(this.key, this.text);
  final String key;
  final String text;
}

/// Verified XHTML figcaption source interval, never invented text.
class EpubFigureCaption {
  const EpubFigureCaption(this.start, this.end);
  final int start;
  final int end;
}

class EpubTablePreview {
  const EpubTablePreview(this.start, this.end, this.rows);
  final int start;
  final int end;
  final List<List<String>> rows;
}

/// A format-check and resource budget, not a full image sandbox.
/// Decoder limits on Android/Windows must still be checked on devices.
bool isSafeEpubRaster(Uint8List bytes, String mediaType) {
  if (bytes.length < 24 || bytes.length > 2 * 1024 * 1024) return false;
  int valid(int width, int height) =>
      width > 0 && height > 0 &&
      width <= 4096 && height <= 4096 &&
      width * height <= 8000000 ? 1 : 0;
  if (mediaType == 'image/png') {
    const magic = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    if (bytes[12] != 73 || bytes[13] != 72 ||
        bytes[14] != 68 || bytes[15] != 82) return false;
    int u32(int at) => (bytes[at] << 24) | (bytes[at + 1] << 16) |
        (bytes[at + 2] << 8) | bytes[at + 3];
    return valid(u32(16), u32(20)) == 1;
  }
  if (mediaType == 'image/jpeg') {
    if (bytes[0] != 0xff || bytes[1] != 0xd8) return false;
    var cursor = 2;
    while (cursor + 4 < bytes.length) {
      if (bytes[cursor] != 0xff) return false;
      while (cursor < bytes.length && bytes[cursor] == 0xff) cursor++;
      if (cursor >= bytes.length) return false;
      final marker = bytes[cursor++];
      if (marker == 0xda || marker == 0xd9) return false;
      if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) continue;
      if (cursor + 2 > bytes.length) return false;
      final length = (bytes[cursor] << 8) | bytes[cursor + 1];
      if (length < 2 || cursor + length > bytes.length) return false;
      if ({0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
            0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf}.contains(marker)) {
        if (length < 7) return false;
        final height = (bytes[cursor + 3] << 8) | bytes[cursor + 4];
        final width = (bytes[cursor + 5] << 8) | bytes[cursor + 6];
        return valid(width, height) == 1;
      }
      cursor += length;
    }
  }
  return false;
}
