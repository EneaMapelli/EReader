import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'epub_visual_layout.dart';

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
  });

  final EpubVisualBlock block;
  final int activeSegmentIndex;
  final double fontSize;
  final ValueChanged<int> onSelectSegment;

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
    final scheme = Theme.of(context).colorScheme;
    final heading = widget.block.heading;
    final size = widget.fontSize;
    final style = TextStyle(
      fontFamily: 'serif',
      fontSize: heading ? size + 5 : size,
      height: heading ? 1.35 : 1.75,
      fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
      color: scheme.onSurface,
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
                      style: run.segmentIndex == widget.activeSegmentIndex
                          ? TextStyle(
                              backgroundColor: scheme.primaryContainer,
                              color: scheme.onPrimaryContainer,
                            )
                          : null,
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
