import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

/// Stable ordering information for each EPUB OPF spine item. Text offsets are
/// Dart String (UTF-16 code unit) offsets in the extracted document.
class EpubSpineRange {
  const EpubSpineRange({
    required this.idref,
    required this.href,
    required this.start,
    required this.end,
    this.title = '',
  });

  final String idref;
  final String href;
  final int start;
  final int end;
  /// Display-only chapter title. Does not affect the source anchor or text.
  final String title;
}

class EpubTextResult {
  const EpubTextResult(this.title, this.text, this.ranges);
  final String title;
  final String text;
  final List<EpubSpineRange> ranges;
}

/// A limited, auditable EPUB2/EPUB3 text extractor.
///
/// It reads META-INF/container.xml -> OPF manifest -> spine, rather than
/// interpreting the table of contents as a reading-order specification.
/// This is NOT a full reflowable visual EPUB renderer or DRM implementation.
class EpubTextExtractor {
  const EpubTextExtractor();

  static const int maxFileCount = 10000;
  static const int maxEntrySize = 32 * 1024 * 1024;
  static const int maxTotalUncompressed = 256 * 1024 * 1024;
  static const int maxTextLength = 25 * 1024 * 1024;

  EpubTextResult extract(Uint8List source) {
    if (source.length > 100 * 1024 * 1024) {
      throw const FormatException('EPUB ZIP file exceeds 100 MB');
    }
    if (source.length < 4 ||
        source[0] != 0x50 || source[1] != 0x4b ||
        source[2] != 0x03 || source[3] != 0x04) {
      throw const FormatException('EPUB ZIP header missing');
    }

    // archive >=4.5 bounds decompression to declared uncompressed entry size.
    // Refuse oversized archives *before* reading entry content.
    final archive = ZipDecoder().decodeBytes(source);
    if (archive.length == 0 || archive.length > maxFileCount) {
      throw const FormatException('Invalid or excessive EPUB entries');
    }

    final files = <String, ArchiveFile>{};
    int totalUncompressed = 0;
    for (final entry in archive) {
      final name = _safeZipName(entry.name);
      if (entry.isSymbolicLink) {
        throw const FormatException('EPUB symlinks are not supported');
      }
      if (entry.isDirectory) continue;
      if (entry.size < 0 || entry.size > maxEntrySize) {
        throw const FormatException('Oversized EPUB archive entry');
      }
      totalUncompressed += entry.size;
      if (totalUncompressed > maxTotalUncompressed) {
        throw const FormatException('EPUB expands beyond safety budget');
      }
      if (files.containsKey(name)) {
        throw const FormatException('Duplicate EPUB ZIP entry');
      }
      files[name] = entry;
    }

    final mime = files['mimetype'];
    if (mime != null &&
        _readText(mime, maxLength: 128).trim() != 'application/epub+zip') {
      throw const FormatException('Unexpected EPUB mimetype');
    }

    final container = _parseXml(
      _readRequired(files, 'META-INF/container.xml', maxLength: 256 * 1024),
    );
    String? opfPath;
    for (final node in container.descendants.whereType<XmlElement>()) {
      if (node.name.local == 'rootfile') {
        opfPath = node.getAttribute('full-path');
        if (opfPath != null) break;
      }
    }
    if (opfPath == null || opfPath.isEmpty) {
      throw const FormatException('EPUB OPF rootfile missing');
    }
    opfPath = _safeZipName(opfPath);

    final package = _parseXml(
      _readRequired(files, opfPath, maxLength: 4 * 1024 * 1024),
    );
    String title = 'Untitled';
    final manifest = <String, String>{};
    final spine = <String>[];

    for (final node in package.descendants.whereType<XmlElement>()) {
      if (node.name.local == 'title' && title == 'Untitled') {
        final candidate = node.innerText.trim();
        if (candidate.isNotEmpty) title = candidate;
      }
      if (node.name.local == 'item') {
        final id = node.getAttribute('id');
        final href = node.getAttribute('href');
        final mediaType = node.getAttribute('media-type') ?? '';
        if (id == null || href == null || id.isEmpty) continue;
        if (mediaType != 'application/xhtml+xml' &&
            mediaType != 'text/html') continue;
        if (manifest.containsKey(id)) {
          throw const FormatException('Duplicate OPF manifest identifier');
        }
        manifest[id] = _resolveOpfHref(opfPath, href);
      }
      if (node.name.local == 'itemref' &&
          node.getAttribute('linear') != 'no') {
        final idref = node.getAttribute('idref');
        if (idref != null && idref.isNotEmpty) spine.add(idref);
      }
    }

    if (spine.isEmpty || spine.length > maxFileCount) {
      throw const FormatException('No readable EPUB spine');
    }

    final buffer = StringBuffer();
    final ranges = <EpubSpineRange>[];
    for (final idref in spine) {
      final href = manifest[idref];
      if (href == null) {
        throw FormatException('Missing XHTML manifest item for spine ID: ' + idref);
      }
      final html = _readRequired(files, href, maxLength: maxEntrySize);
      final text = _extractVisibleText(html);
      if (text.isEmpty) continue;
      final chapterTitle = _extractChapterTitle(html, ranges.length + 1);
      if (buffer.isNotEmpty) buffer.write('\n\n');
      final start = buffer.length;
      buffer.write(text);
      if (buffer.length > maxTextLength) {
        throw const FormatException('EPUB text exceeds size limit');
      }
      ranges.add(EpubSpineRange(
        idref: idref, href: href, start: start, end: buffer.length,
        title: chapterTitle,
      ));
    }
    if (ranges.isEmpty) {
      throw const FormatException('No readable text found in EPUB spine');
    }
    return EpubTextResult(title, buffer.toString(), ranges);
  }

  static XmlDocument _parseXml(String data) {
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(data)) {
      throw const FormatException('EPUB metadata contains prohibited DTD');
    }
    return XmlDocument.parse(data);
  }

  static String _readRequired(
    Map<String, ArchiveFile> files,
    String name, {
    required int maxLength,
  }) {
    final entry = files[name];
    if (entry == null) throw FormatException('Missing EPUB resource: ' + name);
    return _readText(entry, maxLength: maxLength);
  }

  static String _readText(ArchiveFile entry, {required int maxLength}) {
    if (entry.size < 0 || entry.size > maxLength) {
      throw const FormatException('EPUB resource too large');
    }
    final bytes = entry.readBytes();
    if (bytes == null || bytes.length > maxLength) {
      throw const FormatException('Cannot read EPUB resource');
    }
    final text = utf8.decode(bytes);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  static String _safeZipName(String name) {
    if (name.isEmpty || name.contains('\\') || name.startsWith('/') ||
        name.contains('\x00') || name.contains(':')) {
      throw const FormatException('Unsafe EPUB resource path');
    }
    final safe = path.posix.normalize(name);
    if (safe == '.' || safe == '..' || safe.startsWith('../')) {
      throw const FormatException('EPUB path escapes archive');
    }
    return safe;
  }

  static String _resolveOpfHref(String opf, String href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.hasScheme || uri.hasAuthority ||
        href.startsWith('/') || href.startsWith('#')) {
      throw const FormatException('Unsafe OPF manifest href');
    }
    final filename = Uri.decodeComponent(uri.path);
    return _safeZipName(
      path.posix.join(path.posix.dirname(opf), filename),
    );
  }

  /// Chapter labels are derived only from the XHTML body (never OPF,
  /// scripts, page metadata, or a navigation-only manifest document).
  /// The source text and UTF-16 offsets remain entirely unchanged.
  static String _extractChapterTitle(String xhtml, int fallbackNumber) {
    final dom = html_parser.parse(xhtml);
    for (final unwanted in dom.querySelectorAll(
        'script,style,nav,svg,head,noscript')) {
      unwanted.remove();
    }
    // Prefer the first highest-level visible heading, not a body excerpt
    // or a filename supplied by an untrusted ZIP path.
    for (final heading in ['h1', 'h2', 'h3']) {
      for (final element in dom.body?.querySelectorAll(heading) ?? []) {
        final title = element.text
            .replaceAll(RegExp(r'\\s+'), ' ')
            .trim();
        if (title.isNotEmpty) {
          return title.length <= 120
              ? title
              : '${title.substring(0, 117)}…';
        }
      }
    }
    return 'Chapter $fallbackNumber';
  }

  static String _extractVisibleText(String xhtml) {
    // Keep paragraph boundaries before flattening DOM text. HTML parsing does
    // not run scripts, load CSS or follow image URLs.
    final withBreaks = xhtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|h[1-6]|li|blockquote|section)>',
              caseSensitive: false),
          '\n\n',
        );
    final dom = html_parser.parse(withBreaks);
    for (final unwanted in dom.querySelectorAll(
      'script,style,nav,svg,head,noscript',
    )) {
      unwanted.remove();
    }
    final body = dom.body?.text ?? '';
    return body.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
  }
}
