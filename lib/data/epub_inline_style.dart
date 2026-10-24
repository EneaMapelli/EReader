import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'epub_html_preprocess.dart';

/// Pure presentation metadata, measured in UTF-16 code units of the
/// *unchanged* EpubTextExtractor output. Does not change the TTS input.
class EpubInlineStyleSpan {
  const EpubInlineStyleSpan(this.start, this.end, {
    this.bold = false,
    this.italic = false,
    this.headingLevel = 0,
  });

  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final int headingLevel;

  bool sameStyle(EpubInlineStyleSpan other) =>
      bold == other.bold && italic == other.italic &&
      headingLevel == other.headingLevel;
}

/// Extracts safe, bounded semantic typography from body tags only.
/// Normalization intentionally duplicates the existing EPUB text
/// extractor's exact whitespace treatment. If verification fails, drop
/// *all* styling rather than attaching a style to the wrong text.
/// No scripts, CSS, links, embedded resources or images are ever evaluated.
List<EpubInlineStyleSpan> extractEpubInlineStyles(
    String xhtml, String expectedText) {
  final prepared = preprocessEpubVisibleXhtml(xhtml);
  final parsed = parser.parse(prepared);
  for (final unwanted in parsed.querySelectorAll(
      'script,style,nav,svg,head,noscript')) {
    unwanted.remove();
  }
  final body = parsed.body;
  if (body == null) return const [];

  final raw = StringBuffer();
  final rawStyles = <EpubInlineStyleSpan>[];
  const maxStyleRuns = 100000;
  var invalid = false;

  void visit(dom.Node node, bool bold, bool italic, int heading, int depth) {
    if (invalid) return;
    if (depth > 256 || rawStyles.length > maxStyleRuns) {
      invalid = true;
      return;
    }
    if (node is dom.Text) {
      final value = node.data;
      if (value.isEmpty) return;
      final start = raw.length;
      raw.write(value);
      if (bold || italic || heading != 0) {
        rawStyles.add(EpubInlineStyleSpan(
          start, raw.length, bold: bold, italic: italic,
          headingLevel: heading,
        ));
      }
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    final childBold = bold || tag == 'b' || tag == 'strong';
    final childItalic = italic || tag == 'i' || tag == 'em' ||
        tag == 'cite' || tag == 'dfn';
    final level = RegExp(r'^h([1-6])$').firstMatch(tag ?? '');
    final childHeading = level == null
        ? heading : int.parse(level.group(1)!);
    for (final child in node.nodes) {
      visit(child, childBold, childItalic, childHeading, depth + 1);
    }
  }

  for (final node in body.nodes) {
    visit(node, false, false, 0, 0);
  }
  if (invalid) return const [];
  final rawText = raw.toString();
  if (rawText != body.text) return const [];

  // Precisely reproduce the existing extractor's whitespace normalization.
  // Each removed [space/tab...before newline] interval is projected to a
  // zero-width location. Binary search maps raw UTF-16 offsets to positions
  // in the normalized text in O(log whitespace-runs).
  final removals = <({int start, int end, int removedBefore})>[];
  var removed = 0;
  final beforeTrim = rawText.replaceAllMapped(
      RegExp(r'[ \t]+\n'), (match) {
    final end = match.end - 1; // the trailing newline is retained
    removals.add((
      start: match.start, end: end, removedBefore: removed,
    ));
    removed += end - match.start;
    return '\n';
  });
  final normalized = beforeTrim.trim();
  if (normalized != expectedText) return const [];
  final leftTrim = beforeTrim.length - beforeTrim.trimLeft().length;
  final rightLimit = beforeTrim.trimRight().length;

  int project(int position) {
    var lo = 0;
    var hi = removals.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (removals[mid].end <= position) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final int mapped;
    if (lo < removals.length &&
        removals[lo].start < position) {
      final m = removals[lo];
      mapped = m.start - m.removedBefore;
    } else if (lo > 0) {
      final prior = removals[lo - 1];
      mapped = position - prior.removedBefore -
          (prior.end - prior.start);
    } else {
      mapped = position;
    }
    return mapped.clamp(leftTrim, rightLimit).toInt() - leftTrim;
  }

  final mapped = <EpubInlineStyleSpan>[];
  for (final run in rawStyles) {
    final start = project(run.start);
    final end = project(run.end);
    if (start >= end) continue;
    final style = EpubInlineStyleSpan(start, end,
        bold: run.bold, italic: run.italic,
        headingLevel: run.headingLevel);
    if (mapped.isNotEmpty &&
        mapped.last.end == start && mapped.last.sameStyle(style)) {
      final last = mapped.removeLast();
      mapped.add(EpubInlineStyleSpan(last.start, end,
          bold: style.bold, italic: style.italic,
          headingLevel: style.headingLevel));
    } else {
      mapped.add(style);
    }
  }
  return List<EpubInlineStyleSpan>.unmodifiable(mapped);
}
