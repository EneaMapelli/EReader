/// Remove original XHTML head metadata BEFORE HTML5 error recovery can
/// promote malformed hidden headings into the body. A broken book can omit
/// </head> before opening <body>; in that case the genuine body still wins.
/// If neither a closing head nor a body exists, drop the unterminated head
/// rather than treating its hidden contents as spoken prose.
/// This never substitutes heading closing tags used for chapter titles.
String stripEpubHeadMetadata(String xhtml) {
  final head = RegExp(r'<head\b[^>]*>', caseSensitive: false)
      .firstMatch(xhtml);
  if (head == null) return xhtml;
  final end = RegExp(r'</head\s*>', caseSensitive: false)
      .firstMatch(xhtml, head.end);
  final body = RegExp(r'<body\b[^>]*>', caseSensitive: false)
      .firstMatch(xhtml, head.end);
  if (end != null && (body == null || end.start < body.start)) {
    return xhtml.replaceRange(head.start, end.end, '');
  }
  if (body != null) {
    return xhtml.replaceRange(head.start, body.start, '');
  }
  return xhtml.substring(0, head.start);
}

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
