import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import 'epub_inline_style.dart';
import 'epub_structural_markup.dart';
import 'epub_embedded_content.dart';
import 'epub_navigation.dart';

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
  const EpubTextResult(this.title, this.text, this.ranges, {
    this.styles = const [],
    this.images = const [],
    this.links = const [],
    this.tables = const [],
    this.navigation = const [],
  });
  final String title;
  final String text;
  final List<EpubSpineRange> ranges;
  /// Global source offsets; semantic markup cannot alter spoken text.
  final List<EpubInlineStyleSpan> styles;
  final List<EpubEmbeddedImage> images;
  final List<EpubInternalLink> links;
  final List<EpubTablePreview> tables;
  /// Authorial NAV/NCX entries, resolved only to readable spine offsets.
  final List<EpubNavigationEntry> navigation;
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
    final imageManifest = <String, String>{};
    final ncxManifest = <String, String>{};
    String? navDocumentPath;
    String? spineTocId;
    final spine = <String>[];

    for (final node in package.descendants.whereType<XmlElement>()) {
      if (node.name.local == 'title' && title == 'Untitled') {
        final candidate = node.innerText.trim();
        if (candidate.isNotEmpty) title = candidate;
      }
      if (node.name.local == 'spine') {
        spineTocId = node.getAttribute('toc');
      }
      if (node.name.local == 'item') {
        final id = node.getAttribute('id');
        final href = node.getAttribute('href');
        final mediaType = node.getAttribute('media-type') ?? '';
        if (id == null || href == null || id.isEmpty) continue;
        if (mediaType == 'application/x-dtbncx+xml') {
          ncxManifest[id] = _resolveOpfHref(opfPath, href);
          continue;
        }
        if (mediaType == 'image/png' || mediaType == 'image/jpeg') {
          imageManifest[_resolveOpfHref(opfPath, href)] = mediaType;
          continue;
        }
        if (mediaType != 'application/xhtml+xml' &&
            mediaType != 'text/html') continue;
        if ((node.getAttribute('properties') ?? '')
            .split(RegExp(r'\s+')).contains('nav')) {
          navDocumentPath ??= _resolveOpfHref(opfPath, href);
        }
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
    final styles = <EpubInlineStyleSpan>[];
    var styleBudgetExceeded = false;
    const maxGlobalStyleRuns = 100000;
    final imageRefs = <({int offset, String src, String alt, String href})>[];
    final linkRefs = <({
      int start, int end, String href, String source, bool footnote
    })>[];
    final fragmentRefs = <String, int>{};
    final tables = <EpubTablePreview>[];
    const maxTables = 120;
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
      // Annotate the SAME normalized source text as the old extractor.
      // Mismatched DOM normalization safely yields no style spans.
      // Bound the metadata independently of text length; on overflow, the
      // entire book falls back to unstyled but source-exact reading.
      if (!styleBudgetExceeded) {
        final itemStyles = extractEpubInlineStyles(html, text);
        if (itemStyles.length > maxGlobalStyleRuns - styles.length) {
          styles.clear();
          styleBudgetExceeded = true;
        } else {
          for (final style in itemStyles) {
            styles.add(EpubInlineStyleSpan(
              start + style.start, start + style.end,
              bold: style.bold, italic: style.italic,
              headingLevel: style.headingLevel,
            ));
          }
        }
      }
      final structure = extractEpubStructure(html, text);
      for (final img in structure.images) {
        if (imageRefs.length >= 32) break;
        imageRefs.add((
          offset: start + img.offset, src: img.src,
          alt: img.alt, href: href,
        ));
      }
      for (final target in structure.targets) {
        if (fragmentRefs.length >= 30000) break;
        // A fragment at the very end of its source item should stay in
        // that spine item rather than resolve into the next item's separator.
        final local = target.offset == text.length
            ? text.length - 1 : target.offset;
        fragmentRefs.putIfAbsent('$href#${target.id}',
            () => start + local);
      }
      for (final link in structure.links) {
        if (linkRefs.length >= 3000) break;
        linkRefs.add((
          start: start + link.start, end: start + link.end,
          href: link.href, source: href,
          footnote: link.isFootnote,
        ));
      }
      for (final table in structure.tables) {
        if (tables.length >= maxTables) break;
        tables.add(EpubTablePreview(
          start + table.start, start + table.end, table.rows,
        ));
      }
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
    // Resolve only links inside the readable EPUB spine; no external
    // URLs, mailto schemes, scripts, remote assets, or implicit downloads.
    final spinePaths = {for (final range in ranges) range.href};
    final links = <EpubInternalLink>[];
    for (final ref in linkRefs) {
      final destination = _localFragment(ref.source, ref.href);
      if (destination == null || !spinePaths.contains(destination.path)) {
        continue;
      }
      final target = destination.fragment.isEmpty
          ? ranges.firstWhere((entry) => entry.href == destination.path).start
          : fragmentRefs['${destination.path}#${destination.fragment}'];
      if (target == null) continue;
      links.add(EpubInternalLink(ref.start, ref.end, target,
          isFootnote: ref.footnote));
    }
    // Malformed nested anchors may create overlapping link ranges. Drop
    // ambiguous links instead of allowing them to reject an entire ebook
    // during visual layout construction.
    links.sort((a, b) => a.start.compareTo(b.start));
    final nonOverlappingLinks = <EpubInternalLink>[];
    var lastLinkEnd = 0;
    for (final link in links) {
      if (link.start < lastLinkEnd) continue;
      nonOverlappingLinks.add(link);
      lastLinkEnd = link.end;
    }

    // A local, manifest-declared PNG/JPEG must pass byte budget and
    // dimension checks before it can enter a Flutter Image.memory widget.
    final images = <EpubEmbeddedImage>[];
    final imageCache = <String, Uint8List>{};
    var imageByteBudget = 12 * 1024 * 1024;
    for (final ref in imageRefs) {
      final resource = _localResource(ref.href, ref.src);
      if (resource == null) continue;
      final type = imageManifest[resource];
      final entry = files[resource];
      if (type == null || entry == null || entry.size > 2 * 1024 * 1024) {
        continue;
      }
      var bytes = imageCache[resource];
      if (bytes == null) {
        if (entry.size > imageByteBudget) continue;
        final loaded = entry.readBytes();
        if (loaded == null || !isSafeEpubRaster(loaded, type)) continue;
        bytes = Uint8List.fromList(loaded);
        imageCache[resource] = bytes;
        imageByteBudget -= bytes.length;
      }
      images.add(EpubEmbeddedImage(
        offset: ref.offset, bytes: bytes,
        alt: ref.alt, resourcePath: resource,
      ));
    }
    // Authorial navigation is a separate optional overlay; it MUST NOT
    // replace OPF spine as the text/voice reading order. Reject targets
    // outside actually readable spine resources and limit entries.
    List<EpubNavigationEntry> resolveNavigation(
        List<EpubRawNavigationEntry> items, String navSource) {
      final resolved = <EpubNavigationEntry>[];
      final seen = <String>{};
      final byPath = {for (final range in ranges) range.href: range};
      for (final item in items) {
        final destination = _localFragment(navSource, item.href);
        if (destination == null) continue;
        final range = byPath[destination.path];
        if (range == null) continue;
        final offset = destination.fragment.isEmpty ? range.start :
            fragmentRefs['${destination.path}#${destination.fragment}'];
        if (offset == null || offset < range.start || offset >= range.end) {
          continue;
        }
        final key = '${item.label}|$offset';
        if (!seen.add(key)) continue;
        resolved.add(EpubNavigationEntry(
          item.label, offset, item.depth));
        if (resolved.length >= 2000) break;
      }
      return List.unmodifiable(resolved);
    }

    List<EpubNavigationEntry> navigation = const [];
    if (navDocumentPath != null) {
      try {
        final raw = _readRequired(
            files, navDocumentPath!, maxLength: 2 * 1024 * 1024);
        navigation = resolveNavigation(
            parseEpub3Navigation(raw), navDocumentPath!);
      } on FormatException {
        // Missing, malicious or malformed optional TOC must not block
        // an otherwise readable book.
      }
    }
    if (navigation.isEmpty) {
      final ncx = spineTocId == null
          ? (ncxManifest.length == 1 ? ncxManifest.values.first : null)
          : ncxManifest[spineTocId];
      if (ncx != null) {
        try {
          final raw = _readRequired(
              files, ncx, maxLength: 2 * 1024 * 1024);
          navigation = resolveNavigation(parseEpub2Ncx(raw), ncx);
        } on FormatException {
          // Fall back to the existing XHTML spine headings.
        }
      }
    }

    return EpubTextResult(title, buffer.toString(), ranges,
        navigation: navigation,
        styles: List.unmodifiable(styles),
        images: List.unmodifiable(images),
        links: List.unmodifiable(nonOverlappingLinks),
        tables: List.unmodifiable(tables));
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
            .replaceAll(RegExp(r'\s+'), ' ')
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

  static ({String path, String fragment})? _localFragment(
      String sourceHref, String destination) {
    final uri = Uri.tryParse(destination);
    if (uri == null || uri.hasScheme || uri.hasAuthority ||
        uri.path.startsWith('/') || uri.query.isNotEmpty ||
        uri.fragment.isEmpty && uri.path.isEmpty) {
      return null;
    }
    try {
      final targetPath = uri.path.isEmpty
          ? sourceHref
          : _safeZipName(path.posix.join(
              path.posix.dirname(sourceHref),
              Uri.decodeComponent(uri.path)));
      return (path: targetPath, fragment: Uri.decodeComponent(uri.fragment));
    } on FormatException {
      return null;
    }
  }

  static String? _localResource(String sourceHref, String src) {
    final uri = Uri.tryParse(src);
    if (uri == null || uri.hasScheme || uri.hasAuthority ||
        uri.path.isEmpty || uri.path.startsWith('/') ||
        uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      return null;
    }
    try {
      return _safeZipName(path.posix.join(path.posix.dirname(sourceHref),
          Uri.decodeComponent(uri.path)));
    } on FormatException {
      return null;
    }
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
