/// Remove original XHTML head metadata before HTML5 error recovery can
/// promote malformed hidden elements into the rendered body. This does NOT
/// alter any closing body elements: chapter titles need genuine heading
/// boundaries instead of the speech extractor's newline substitutions.
String stripEpubHeadMetadata(String xhtml) => xhtml.replaceAll(
  RegExp(r'<head\b[^>]*>[\s\S]*?</head\s*>', caseSensitive: false),
  '',
);

/// Identical presentation-source preprocessing for extracted speech text,
/// structural metadata and inline styles. A single transformation is critical:
/// if any parser normalizes differently, source UTF-16 offsets are unsafe.
///
/// The original behavior for plain <br>, <br/> and supported closing block
/// tags is unchanged. Older XHTML may use <br clear="all"> or other attributes;
/// these now produce the intended newline without introducing HTML execution.
String preprocessEpubVisibleXhtml(String xhtml) {
  // Quoted > characters inside attributes do not terminate the tag.
  final breaks = RegExp(
    r'''<br\b(?:[^>"']|"[^"]*"|'[^']*')*\/?>''',
    caseSensitive: false,
  );
  // An HTML5 parser can repair malformed XHTML by reparenting invalid
  // heading elements from <head> into <body>. Remove the entire original
  // head BEFORE parsing, or hidden metadata can become spoken prose.
  // All consumers (text, typography, links and images) share this filter,
  // preserving identical UTF-16 source offsets.
  final bodyOnly = stripEpubHeadMetadata(xhtml);
  return bodyOnly
      .replaceAll(breaks, '\n')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|blockquote|section)>',
            caseSensitive: false),
        '\n\n',
      );
}
