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
  return xhtml
      .replaceAll(breaks, '\n')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|blockquote|section)>',
            caseSensitive: false),
        '\n\n',
      );
}
