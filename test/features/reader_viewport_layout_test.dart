import 'package:ereader/features/reader/reader_viewport_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader toolbar prioritizes title on narrow and magnified layouts',
      () {
    expect(useCompactReaderToolbar(width: 320, scaledBaseTextSize: 16), isTrue);
    expect(useCompactReaderToolbar(width: 419, scaledBaseTextSize: 16), isTrue);
    expect(useCompactReaderToolbar(width: 420, scaledBaseTextSize: 16), isFalse);
    expect(useCompactReaderToolbar(width: 800, scaledBaseTextSize: 25), isFalse);
    expect(useCompactReaderToolbar(width: 800, scaledBaseTextSize: 26), isTrue);
    expect(useCompactReaderToolbar(width: 420, scaledBaseTextSize: 30), isTrue);
  });

  test('narrow phone uses 14 logical-pixel horizontal reading margins', () {
    final padding = readerViewportPadding(width: 320, focusMode: false);
    expect(padding, const EdgeInsets.fromLTRB(14, 18, 14, 18));
    expect(readerViewportPadding(width: 379, focusMode: false),
        const EdgeInsets.fromLTRB(14, 18, 14, 18));
  });

  test('large screens retain the original reading-column margins', () {
    expect(readerViewportPadding(width: 380, focusMode: false),
        const EdgeInsets.fromLTRB(24, 18, 24, 18));
    expect(readerViewportPadding(width: 1024, focusMode: false),
        const EdgeInsets.fromLTRB(24, 18, 24, 18));
  });

  test('focus mode reserves clearance for floating restore button', () {
    for (final width in [320.0, 380.0, 1024.0]) {
      final normal = readerViewportPadding(
          width: width, focusMode: false);
      final focused = readerViewportPadding(
          width: width, focusMode: true);
      expect(focused.left, normal.left);
      expect(focused.right, normal.right);
      expect(focused.top, normal.top);
      expect(focused.bottom, greaterThan(normal.bottom));
      expect(focused.bottom, 104);
    }
  });
}
