import 'package:ereader/data/epub_inline_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalization mismatch discards every visual style', () {
    final styles = extractEpubInlineStyles(
      '<html><body><p>Hello <em>world</em>.</p></body></html>',
      'An unrelated passage.',
    );
    expect(styles, isEmpty,
        reason: 'Do not attach XHTML styling to a different spoken source');
  });

  test('emoji keep UTF-16 source offsets inside emphasis', () {
    const source = 'plain 📖 plain';
    final styles = extractEpubInlineStyles(
      '<html><body><p>plain <em>📖</em> plain</p></body></html>',
      source,
    );
    expect(styles.length, 1);
    expect(styles.single.start, 6);
    expect(styles.single.end, 8);
    expect(source.substring(styles.single.start, styles.single.end), '📖');
    expect(styles.single.italic, isTrue);
  });

  test('nested strong and emphasis are flattened into disjoint style runs', () {
    const source = 'A quiet voice heard.';
    final styles = extractEpubInlineStyles(
      '<html><body><p>A <em>quiet <strong>voice</strong></em>'
      ' heard.</p></body></html>',
      source,
    );
    expect(styles.every((span) => span.start < span.end), isTrue);
    final quiet = source.indexOf('quiet');
    final voice = source.indexOf('voice');
    final italic = styles.firstWhere(
        (span) => span.start <= quiet && span.end >= quiet + 5);
    final combined = styles.firstWhere(
        (span) => span.start <= voice && span.end >= voice + 5);
    expect(italic.italic, isTrue);
    expect(italic.bold, isFalse);
    expect(combined.italic, isTrue);
    expect(combined.bold, isTrue);
    for (var i = 1; i < styles.length; i++) {
      expect(styles[i].start, greaterThanOrEqualTo(styles[i - 1].end));
    }
  });

  test('non-content XHTML cannot produce formatting metadata', () {
    const source = 'Safe content.';
    final styles = extractEpubInlineStyles(
      '<html><head><strong>Private</strong></head><body>'
      '<script><b>Injected</b></script><nav><h2>TOC</h2></nav>'
      '<style>body{font-weight:bold}</style>'
      '<p>Safe content.</p></body></html>',
      source,
    );
    expect(styles, isEmpty);
  });
}
