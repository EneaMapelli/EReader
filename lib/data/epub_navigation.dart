import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// A book-author supplied navigation item, before its local XHTML target
/// has been verified against the actually readable OPF spine.
class EpubRawNavigationEntry {
  const EpubRawNavigationEntry(this.label, this.href, this.depth);
  final String label;
  final String href;
  final int depth;
}

/// A resolved, non-executable EPUB directory entry. [offset] indexes the
/// very same UTF-16 source string as bookmarks, search and speech segments.
class EpubNavigationEntry {
  const EpubNavigationEntry(this.label, this.offset, this.depth);
  final String label;
  final int offset;
  final int depth;
}

String? _safeTitle(String text) {
  final label = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (label.isEmpty) return null;
  return label.length <= 120 ? label : '${label.substring(0, 117)}…';
}

/// EPUB3 Navigation Document. Only the first TOC nav is consulted: landmarks
/// and page-list are not the author's primary contents. No CSS/JS/HTTP/HTML
/// rendering occurs here. Recursive list traversal preserves hierarchy.
List<EpubRawNavigationEntry> parseEpub3Navigation(String xhtml) {
  if (xhtml.length > 2 * 1024 * 1024) return const [];
  final doc = html_parser.parse(xhtml);
  final result = <EpubRawNavigationEntry>[];
  var visited = 0;
  const maxEntries = 2000;
  const maxDepth = 20;
  dom.Element? contents;
  for (final nav in doc.querySelectorAll('nav')) {
    final type = nav.attributes['epub:type'] ?? '';
    final role = nav.attributes['role'] ?? '';
    if (type.split(RegExp(r'\s+')).contains('toc') ||
        role.split(RegExp(r'\s+')).contains('doc-toc')) {
      contents = nav;
      break;
    }
  }
  if (contents == null) return const [];

  void walk(dom.Element list, int depth) {
    if (depth > maxDepth || result.length >= maxEntries ||
        visited > maxEntries * 8) return;
    for (final li in list.children.where((child) => child.localName == 'li')) {
      if (++visited > maxEntries * 8) return;
      for (final element in li.children) {
        if (element.localName == 'a') {
          final href = element.attributes['href'];
          final label = _safeTitle(element.text);
          if (href != null && href.length <= 1024 && label != null &&
              result.length < maxEntries) {
            result.add(EpubRawNavigationEntry(label, href, depth));
          }
          break;
        }
        if (element.localName == 'span') break;
      }
      if (depth < maxDepth) {
        for (final child in li.children.where((child) =>
            child.localName == 'ol' || child.localName == 'ul')) {
          walk(child, depth + 1);
        }
      }
    }
  }

  for (final top in contents.children.where((child) =>
      child.localName == 'ol' || child.localName == 'ul')) {
    walk(top, 0);
  }
  return List.unmodifiable(result);
}

/// EPUB2 NCX. No external entities/DTD or network resources are parsed;
/// only navMap/navPoint labels and content src values are read.
List<EpubRawNavigationEntry> parseEpub2Ncx(String xml) {
  if (xml.length > 2 * 1024 * 1024 ||
      RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(xml)) {
    return const [];
  }
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (_) {
    // Malformed optional NCX never prevents normal spine reading.
    return const [];
  }
  final navMaps = doc.descendants.whereType<XmlElement>()
      .where((node) => node.name.local == 'navMap').toList();
  if (navMaps.isEmpty) return const [];
  final result = <EpubRawNavigationEntry>[];
  const maxEntries = 2000;
  const maxDepth = 20;
  var inspected = 0;

  void walk(XmlElement parent, int depth) {
    if (depth > maxDepth || result.length >= maxEntries ||
        inspected > maxEntries * 8) return;
    for (final node in parent.children.whereType<XmlElement>()
        .where((element) => element.name.local == 'navPoint')) {
      if (++inspected > maxEntries * 8) return;
      String? label;
      String? href;
      for (final child in node.children.whereType<XmlElement>()) {
        if (child.name.local == 'navLabel') {
          label = _safeTitle(child.innerText);
        } else if (child.name.local == 'content') {
          href = child.getAttribute('src');
        }
      }
      if (label != null && href != null && href.length <= 1024 &&
          result.length < maxEntries) {
        result.add(EpubRawNavigationEntry(label, href, depth));
      }
      if (depth < maxDepth) walk(node, depth + 1);
    }
  }

  walk(navMaps.first, 0);
  return List.unmodifiable(result);
}
