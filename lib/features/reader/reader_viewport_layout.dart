import 'package:flutter/material.dart';

/// Horizontal text insets are narrower on small phones; this retains room
/// for readable EPUB paragraphs without altering EPUB source coordinates.
///
/// The hidden-control overlay floats above the text and does not take up
/// layout space. The extra bottom padding allows the last paragraph to be
/// scrolled clear of its restore button, including Android's bottom safe area.
EdgeInsets readerViewportPadding({
  required double width,
  required bool focusMode,
}) {
  final horizontal = width < 380 ? 14.0 : 24.0;
  return EdgeInsets.fromLTRB(
    horizontal,
    18,
    horizontal,
    focusMode ? 104 : 18,
  );
}
