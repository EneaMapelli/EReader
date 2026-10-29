import 'package:flutter/material.dart';

import '../../domain/reading_progress.dart';

/// Whole-source progress (not a false audio-duration estimate).
/// Seeking is only committed on drag release, never while moving a thumb,
/// so dragging does not start TTS, spend cloud quota or mutate bookmarks.
class ReadingProgressBar extends StatefulWidget {
  const ReadingProgressBar({
    super.key,
    required this.sourceOffset,
    required this.sourceLength,
    required this.onSeekToOffset,
  });

  final int sourceOffset;
  final int sourceLength;
  final ValueChanged<int> onSeekToOffset;

  @override
  State<ReadingProgressBar> createState() => _ReadingProgressBarState();
}

class _ReadingProgressBarState extends State<ReadingProgressBar> {
  double? _preview;

  @override
  Widget build(BuildContext context) {
    final fraction = ReadingSourceProgress.fraction(
        offset: widget.sourceOffset, length: widget.sourceLength);
    final shown = _preview ?? fraction;
    final percent = (shown * 100).round();
    final enabled = widget.sourceLength > 0;
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            '$percent%',
            textAlign: TextAlign.start,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Expanded(
          child: Slider(
            key: const ValueKey('reader-source-progress'),
            value: shown.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: enabled ? 1000 : null,
            label: '$percent% of book text',
            semanticFormatterCallback: (value) =>
                '${(value * 100).round()} percent of book text',
            onChanged: enabled
                ? (value) => setState(() => _preview = value)
                : null,
            onChangeEnd: enabled ? (value) {
              setState(() => _preview = null);
              widget.onSeekToOffset(ReadingSourceProgress.offsetForFraction(
                  fraction: value, length: widget.sourceLength));
            } : null,
          ),
        ),
      ],
    );
  }
}
