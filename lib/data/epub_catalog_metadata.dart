import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'epub_text_decoder.dart';

/// OPF-only catalog metadata; no XHTML rendering, scripts, external
/// resources, cloud services or chapter text is needed to import a book.
class EpubCatalogMetadata {
  const EpubCatalogMetadata({
    this.title,
    this.author,
    this.series,
    this.language,
  });

  final String? title;
  final String? author;
  final String? series;
  final String? language;
}

/// Extracts bounded EPUB2/3 OPF catalog fields from an untrusted ZIP.
/// Does not make claims about EPUB layout or validate the entire book.
///
/// Package metadata is best effort: importers should retain the original
/// filename if this fails and let the reader report detailed parse errors
/// when a user actually opens the damaged book.
class EpubCatalogMetadataReader {
  const EpubCatalogMetadataReader();

  static const _maxArchive = 100 * 1024 * 1024;
  static const _maxEntries = 10000;
  static const _maxInflated = 256 * 1024 * 1024;

  EpubCatalogMetadata read(Uint8List bytes) {
    if (bytes.length < 4 || bytes.length > _maxArchive ||
        bytes[0] != 0x50 || bytes[1] != 0x4b ||
        bytes[2] != 0x03 || bytes[3] != 0x04) {
      throw const FormatException('Invalid EPUB archive');
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.length == 0 || archive.length > _maxEntries) {
      throw const FormatException('Invalid EPUB entry count');
    }
    final files = <String, ArchiveFile>{};
    var total = 0;
    for (final entry in archive) {
      final name = _safeZipPath(entry.name);
      if (entry.isSymbolicLink) {
        throw const FormatException('EPUB archive links are not supported');
      }
      if (entry.isDirectory) continue;
      if (entry.size < 0 || entry.size > 32 * 1024 * 1024) {
        throw const FormatException('Oversized EPUB resource');
      }
      total += entry.size;
      if (total > _maxInflated || files.containsKey(name)) {
        throw const FormatException('Invalid EPUB resource inventory');
      }
      files[name] = entry;
    }

    final container = _xml(
      _text(files, 'META-INF/container.xml', 256 * 1024),
    );
    String? opfPath;
    for (final element in container.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'rootfile') {
        opfPath = element.getAttribute('full-path');
        if (opfPath != null) break;
      }
    }
    if (opfPath == null || opfPath.isEmpty) {
      throw const FormatException('Missing EPUB OPF path');
    }
    final package = _xml(_text(files, _safeZipPath(opfPath), 4 * 1024 * 1024));
    XmlElement? metadata;
    for (final element in package.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'metadata') {
        metadata = element;
        break;
      }
    }
    if (metadata == null) {
      throw const FormatException('Missing EPUB package metadata');
    }

    final elements = metadata.children.whereType<XmlElement>().toList();
    String? firstValue(String name) {
      for (final el in elements) {
        if (el.name.local == name) {
          final value = _clean(el.innerText);
          if (value != null) return value;
        }
      }
      return null;
    }

    final title = firstValue('title');
    final creators = <String>[];
    for (final el in elements) {
      if (el.name.local == 'creator') {
        final creator = _clean(el.innerText);
        if (creator != null && !creators.contains(creator)) {
          creators.add(creator);
        }
        if (creators.length == 3) break;
      }
    }
    final author = _clean(creators.join(', '));
    final language = _locale(firstValue('language'));

    String? series;
    // EPUB2/Calibre convention, used widely by existing personal libraries.
    for (final el in elements) {
      if (el.name.local != 'meta') continue;
      if ((el.getAttribute('name') ?? '').toLowerCase() ==
          'calibre:series') {
        series = _clean(el.getAttribute('content'));
        if (series != null) break;
      }
    }
    // EPUB3 collection metadata. Accept a collection only if its refines
    // metadata identifies it as a series (not a publisher/other collection).
    if (series == null) {
      for (final el in elements) {
        if (el.name.local != 'meta' ||
            el.getAttribute('property') != 'belongs-to-collection') {
          continue;
        }
        final id = el.getAttribute('id');
        if (id == null || id.isEmpty) continue;
        final candidate = _clean(el.innerText);
        if (candidate == null) continue;
        final isSeries = elements.any((other) =>
            other.name.local == 'meta' &&
            other.getAttribute('property') == 'collection-type' &&
            other.getAttribute('refines') == '#$id' &&
            other.innerText.trim().toLowerCase() == 'series');
        if (isSeries) {
          series = candidate;
          break;
        }
      }
    }

    return EpubCatalogMetadata(
      title: title,
      author: author,
      series: series,
      language: language,
    );
  }

  static String _safeZipPath(String name) {
    if (name.isEmpty || name.contains(r'\') || name.startsWith('/') ||
        name.contains('\x00') || name.contains(':')) {
      throw const FormatException('Unsafe EPUB internal path');
    }
    final value = p.posix.normalize(name);
    if (value == '.' || value == '..' || value.startsWith('../')) {
      throw const FormatException('EPUB internal path escapes archive');
    }
    return value;
  }

  static String _text(
      Map<String, ArchiveFile> files, String path, int maxLength) {
    final entry = files[path];
    if (entry == null || entry.size > maxLength || entry.size < 0) {
      throw const FormatException('Missing or oversized EPUB metadata');
    }
    final bytes = entry.readBytes();
    if (bytes == null || bytes.length > maxLength) {
      throw const FormatException('Cannot read EPUB metadata');
    }
    return decodeEpubTextResource(bytes, maxBytes: maxLength);
  }

  static XmlDocument _xml(String source) {
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(source)) {
      throw const FormatException('EPUB XML external entities are prohibited');
    }
    return XmlDocument.parse(source);
  }

  static String? _clean(String? source) {
    if (source == null) return null;
    final text = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty || text.length > 160 ||
        text.runes.any((code) => code < 32 || code == 127)) {
      return null;
    }
    return text;
  }

  static String? _locale(String? source) {
    if (source == null) return null;
    final value = source.replaceAll('_', '-');
    return RegExp(r'^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{2,8})?$').hasMatch(value)
        ? value : null;
  }
}
