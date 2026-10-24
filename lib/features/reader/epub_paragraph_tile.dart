import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'epub_visual_layout.dart';

/// Display-only, session-local colors. A future reader-preferences screen
/// can persist these without touching source anchors or speech settings.
enum EpubReadingPalette { system, sepia, night }

extension EpubReadingPaletteColors on EpubReadingPalette {
  Color background(BuildContext context) => switch (this) {
    EpubReadingPalette.system =>
        Theme.of(context).scaffoldBackgroundColor,
    EpubReadingPalette.sepia => const Color(0xFFF4ECD9),
    EpubReadingPalette.night => const Color(0xFF17191E),
  };

  Color foreground(BuildContext context) => switch (this) {
    EpubReadingPalette.system => Theme.of(context).colorScheme.onSurface,
    EpubReadingPalette.sepia => const Color(0xFF372B20),
    EpubReadingPalette.night => const Color(0xFFE2E3E7),
  };

  Color highlight(BuildContext context) => switch (this) {
    EpubReadingPalette.system => Theme.of(context).colorScheme.primaryContainer,
    EpubReadingPalette.sepia => const Color(0xFFE7D39B),
    EpubReadingPalette.night => const Color(0xFF3C4968),
  };

  Color highlightForeground(BuildContext context) => switch (this) {
    EpubReadingPalette.system =>
        Theme.of(context).colorScheme.onPrimaryContainer,
    EpubReadingPalette.sepia => const Color(0xFF302414),
    EpubReadingPalette.night => const Color(0xFFF0F3FF),
  };
}

/// Lazy, source-exact EPUB paragraph widget. No HTML WebView, network
/// resources, external CSS, JavaScript or embedded assets are evaluated.
/// Individual spoken spans remain tappable without rewriting source text.
class EpubParagraphTile extends StatefulWidget {
  const EpubParagraphTile({
    super.key,
    required this.block,
    required this.activeSegmentIndex,
    required this.fontSize,
    required this.onSelectSegment,
    this.palette = EpubReadingPalette.system,
  });

  final EpubVisualBlock block;
  final int activeSegmentIndex;
  final double fontSize;
  final ValueChanged<int> onSelectSegment;
  final EpubReadingPalette palette;

  @override
  State<EpubParagraphTile> createState() => _EpubParagraphTileState();
}

class _EpubParagraphTileState extends State<EpubParagraphTile> {
  final Map<int, TapGestureRecognizer> _recognizers = {};

  TapGestureRecognizer _tap(int index) {
    final recognizer = _recognizers.putIfAbsent(
      index, TapGestureRecognizer.new,
    );
    recognizer.onTap = () => widget.onSelectSegment(index);
    return recognizer;
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant EpubParagraphTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.block, widget.block)) {
      _clearRecognizers();
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final heading = widget.block.heading;
    final size = widget.fontSize;
    final style = TextStyle(
      fontFamily: 'serif',
      fontSize: heading ? size + 5 : size,
      height: heading ? 1.35 : 1.75,
      fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
      color: palette.foreground(context),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8, widget.block.chapterStart ? 24 : 4,
            8, heading ? 18 : 17,
          ),
          child: Semantics(
            header: heading,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final run in widget.block.runs)
                    TextSpan(
                      text: run.text,
                      style: TextStyle(
                        fontWeight: run.bold || run.headingLevel > 0
                            ? FontWeight.w700 : null,
                        fontStyle: run.italic ? FontStyle.italic : null,
                        // An internal h2/h3 must be recognizable even if
                        // another text element shares this visual block.
                        fontSize: run.headingLevel > 0 && !heading
                            ? size + (7 - run.headingLevel).clamp(1, 6)
                            : null,
                        backgroundColor:
                            run.segmentIndex == widget.activeSegmentIndex
                                ? palette.highlight(context) : null,
                        color: run.segmentIndex == widget.activeSegmentIndex
                            ? palette.highlightForeground(context) : null,
                      ),
                      recognizer: run.segmentIndex == null
                          ? null
                          : _tap(run.segmentIndex!),
                    ),
                ],
              ),
              style: style,
              textAlign: heading ? TextAlign.start : TextAlign.justify,
              softWrap: true,
            ),
          ),
        ),
      ),
    );
  }
}
