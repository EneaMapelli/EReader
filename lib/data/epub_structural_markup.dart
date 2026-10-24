import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// Non-executable, source-addressed presentation metadata for an XHTML spine
/// document. All offsets are relative to the extractor's original UTF-16 text.
class EpubRawImage {
  const EpubRawImage(this.offset, this.src, this.alt);
  final int offset;
  final String src;
  final String alt;
}

class EpubRawLink {
  const EpubRawLink(this.start, this.end, this.href, {
    this.isFootnote = false,
    this.legacyNoteCandidate = false,
  });
  final int start;
  final int end;
  final String href;
  final bool isFootnote;
  /// EPUB2 marker is never trusted until its destination is verified.
  final bool legacyNoteCandidate;
}

class EpubRawTarget {
  const EpubRawTarget(this.id, this.offset);
  final String id;
  final int offset;
}

class EpubRawTable {
  const EpubRawTable(this.start, this.end, this.rows);
  final int start;
  final int end;
  final List<List<String>> rows;
}

/// A recognized, fully in-spine footnote body. Its original text and
/// UTF-16 position are not synthesized, copied or inserted anywhere else.
class EpubRawFootnote {
  const EpubRawFootnote(this.id, this.start, this.end);
  final String id;
  final int start;
  final int end;
}

class EpubStructure {
  const EpubStructure({
    this.images = const [],
    this.links = const [],
    this.targets = const [],
    this.tables = const [],
    this.footnotes = const [],
  });

  final List<EpubRawImage> images;
  final List<EpubRawLink> links;
  final List<EpubRawTarget> targets;
  final List<EpubRawTable> tables;
  final List<EpubRawFootnote> footnotes;
}

// Exact class tokens avoid substring false positives ("noteworthy" != "note").
// For EPUB2 both the reference AND destination must identify a footnote.
Set<String> _classTokens(dom.Element node) =>
    (node.attributes['class'] ?? '').toLowerCase()
        .split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toSet();

const _legacyNoteBodyClasses = <String>{
  'footnote', 'foot-note', 'endnote', 'end-note',
};
const _legacyNoteListClasses = <String>{
  'footnotes', 'foot-notes', 'endnotes', 'end-notes',
};
const _legacyReferenceClasses = <String>{
  'footnote-ref', 'footnote-reference', 'footnoteref', 'fnref',
  'fn-ref', 'endnote-ref', 'endnoteref', 'note-ref', 'noteref',
};
const _noteBodyTags = <String>{
  'aside', 'div', 'section', 'p', 'li', 'blockquote',
};

bool _containsAny(Set<String> tokens, Set<String> accepted) =>
    tokens.any(accepted.contains);

bool _legacyFootnoteBody(dom.Element element) {
  if (!_noteBodyTags.contains(element.localName)) return false;
  if (_containsAny(_classTokens(element), _legacyNoteBodyClasses)) {
    return true;
  }
  // List items require a parent list explicitly labeled as footnotes.
  if (element.localName != 'li') return false;
  final parent = element.parent;
  if (parent == null ||
      (parent.localName != 'ol' && parent.localName != 'ul')) return false;
  return _containsAny(_classTokens(parent), _legacyNoteListClasses);
}

bool _legacyFootnoteReference(dom.Element link) {
  final uri = Uri.tryParse(link.attributes['href'] ?? '');
  if (uri == null || uri.fragment.isEmpty || uri.hasScheme ||
      uri.hasAuthority) return false;
  if (_containsAny(_classTokens(link), _legacyReferenceClasses)) return true;
  final rel = (link.attributes['rel'] ?? '').toLowerCase()
      .split(RegExp(r'\s+')).toSet();
  if (rel.contains('footnote')) return true;
  // Superscripted numeric/symbol markers are only candidates.
  if (link.parent?.localName != 'sup') return false;
  return RegExp(r'^(?:\[?\d{1,3}\]?|[*†‡])$').hasMatch(link.text.trim());
}

/// Parse body-only features without interpreting styles, executing code,
/// loading resources or changing the speech/source text. Every offset is
/// projected through the *same* whitespace transformations as the original
/// EpubTextExtractor and accepted only if the entire body still matches.
EpubStructure extractEpubStructure(String xhtml, String expectedText) {
  final prepared = xhtml
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|blockquote|section)>',
            caseSensitive: false), '\n\n');
  final parsed = parser.parse(prepared);
  for (final hidden in parsed.querySelectorAll(
      'script,style,nav,svg,head,noscript')) {
    hidden.remove();
  }
  final body = parsed.body;
  if (body == null) return const EpubStructure();

  final raw = StringBuffer();
  final images = <EpubRawImage>[];
  final links = <EpubRawLink>[];
  final targets = <EpubRawTarget>[];
  final tables = <EpubRawTable>[];
  final footnotes = <EpubRawFootnote>[];
  var invalid = false;
  const maxNodeDepth = 256;
  const maxAnnotations = 3000;

  void visit(dom.Node node, int depth) {
    if (invalid) return;
    if (depth > maxNodeDepth ||
        images.length + links.length + targets.length +
            tables.length + footnotes.length > maxAnnotations) {
      invalid = true;
      return;
    }
    if (node is dom.Text) {
      raw.write(node.data);
      return;
    }
    if (node is! dom.Element) return;
    final start = raw.length;
    final id = node.attributes['id'] ??
        (node.localName == 'a' ? node.attributes['name'] : null);
    if (id != null && id.isNotEmpty && id.length <= 256) {
      targets.add(EpubRawTarget(id, start));
    }
    if (node.localName == 'img') {
      final src = node.attributes['src'];
      if (src != null && src.isNotEmpty && src.length <= 1024) {
        images.add(EpubRawImage(start, src,
            (node.attributes['alt'] ?? '').trim().substringSafe(160)));
      }
    }
    for (final child in node.nodes) {
      visit(child, depth + 1);
    }
    final end = raw.length;
    if (node.localName == 'a') {
      final href = node.attributes['href'];
      if (href != null && href.length <= 1024 && start < end) {
        final semanticType = node.attributes['epub:type'] ?? '';
        final role = node.attributes['role'] ?? '';
        final footnote = semanticType.split(RegExp(r'\s+'))
                .contains('noteref') ||
            role.split(RegExp(r'\s+')).contains('doc-noteref');
        links.add(EpubRawLink(
            start, end, href, isFootnote: footnote,
            legacyNoteCandidate: !footnote &&
                _legacyFootnoteReference(node)));
      }
    }
    if (start < end && id != null && id.isNotEmpty &&
        id.length <= 256) {
      final type = (node.attributes['epub:type'] ?? '')
          .split(RegExp(r'\s+'));
      final role = (node.attributes['role'] ?? '')
          .split(RegExp(r'\s+'));
      final isNote = type.contains('footnote') ||
          role.contains('doc-footnote') ||
          _legacyFootnoteBody(node);
      if (isNote && footnotes.length < 200) {
        footnotes.add(EpubRawFootnote(id, start, end));
      }
    }
    if (node.localName == 'table' && start < end) {
      final rowElements = node.querySelectorAll('tr');
      if (rowElements.isNotEmpty && rowElements.length <= 40) {
        final rows = <List<String>>[];
        for (final row in rowElements) {
          final cells = row.children.where((child) =>
              child.localName == 'th' || child.localName == 'td').toList();
          if (cells.isEmpty || cells.length > 12) continue;
          rows.add([
            for (final cell in cells)
              cell.text.trim().replaceAll(RegExp(r'\s+'), ' ')
                  .substringSafe(300),
          ]);
        }
        if (rows.isNotEmpty) {
          tables.add(EpubRawTable(start, end, List.unmodifiable(rows)));
        }
      }
    }
  }

  for (final child in body.nodes) {
    visit(child, 0);
  }
  if (invalid || raw.toString() != body.text) return const EpubStructure();

  // Match the extractor's raw-body normalization byte-for-byte.
  final original = raw.toString();
  final removedRanges = <({int start, int end, int removedBefore})>[];
  var removed = 0;
  final beforeTrim = original.replaceAllMapped(RegExp(r'[ \t]+\n'), (m) {
    removedRanges.add((
      start: m.start, end: m.end - 1, removedBefore: removed,
    ));
    removed += m.end - m.start - 1;
    return '\n';
  });
  if (beforeTrim.trim() != expectedText) return const EpubStructure();
  final leftTrim = beforeTrim.length - beforeTrim.trimLeft().length;
  final rightLimit = beforeTrim.trimRight().length;

  int project(int position) {
    var low = 0;
    var high = removedRanges.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (removedRanges[mid].end <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final int normalized;
    if (low < removedRanges.length &&
        removedRanges[low].start < position) {
      final m = removedRanges[low];
      normalized = m.start - m.removedBefore;
    } else if (low > 0) {
      final prior = removedRanges[low - 1];
      normalized = position - prior.removedBefore -
          (prior.end - prior.start);
    } else {
      normalized = position;
    }
    return normalized.clamp(leftTrim, rightLimit).toInt() - leftTrim;
  }

  return EpubStructure(
    images: List.unmodifiable([
      for (final item in images)
        EpubRawImage(project(item.offset), item.src, item.alt),
    ]),
    links: List.unmodifiable([
      for (final item in links)
        if (project(item.start) < project(item.end))
          EpubRawLink(project(item.start), project(item.end), item.href,
              isFootnote: item.isFootnote,
              legacyNoteCandidate: item.legacyNoteCandidate),
    ]),
    targets: List.unmodifiable([
      for (final item in targets)
        EpubRawTarget(item.id, project(item.offset)),
    ]),
    tables: List.unmodifiable([
      for (final item in tables)
        if (project(item.start) < project(item.end))
          EpubRawTable(
            project(item.start), project(item.end), item.rows),
    ]),
    footnotes: List.unmodifiable([
      for (final item in footnotes)
        if (project(item.start) < project(item.end))
          EpubRawFootnote(item.id,
              project(item.start), project(item.end)),
    ]),
  );
}

extension _SafePrefix on String {
  String substringSafe(int limit) =>
      length > limit ? substring(0, limit) : this;
}
