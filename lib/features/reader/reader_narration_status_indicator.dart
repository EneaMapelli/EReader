import 'package:flutter/material.dart';

/// A presentation-only status for audio continuing at a different position
/// from the visible page. No player, bookmark or source offsets are mutated.
String readerNarrationPositionLabel({
  required int currentIndex,
  required int segmentCount,
}) {
  if (segmentCount <= 0) return 'TTS unavailable';
  if (currentIndex >= segmentCount) return 'TTS complete';
  final display = currentIndex.clamp(0, segmentCount - 1) + 1;
  return 'TTS $display/$segmentCount';
}

String readerNarrationPositionSemantics({
  required int currentIndex,
  required int segmentCount,
  required bool isPlaying,
}) {
  if (segmentCount <= 0) return 'Narration unavailable; viewing elsewhere';
  if (currentIndex >= segmentCount) {
    return 'Narration complete; viewing elsewhere';
  }
  final display = currentIndex.clamp(0, segmentCount - 1) + 1;
  final state = isPlaying ? 'playing' : 'paused';
  return 'Narration $state, segment $display of $segmentCount; '
      'viewing elsewhere';
}

/// Passive and compact. A separate return action is deliberately required;
/// touching the label must not seek, pause or play the narrator.
class ReaderNarrationStatusIndicator extends StatelessWidget {
  const ReaderNarrationStatusIndicator({
    super.key,
    required this.currentIndex,
    required this.segmentCount,
    required this.isPlaying,
  });

  final int currentIndex;
  final int segmentCount;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) => Semantics(
        key: const ValueKey('reader-detached-narration-status'),
        container: true,
        label: readerNarrationPositionSemantics(
          currentIndex: currentIndex,
          segmentCount: segmentCount,
          isPlaying: isPlaying,
        ),
        child: ExcludeSemantics(
          child: Chip(
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            avatar: Icon(
              isPlaying ? Icons.record_voice_over : Icons.pause_circle_outline,
              size: 17,
            ),
            label: Text(
              readerNarrationPositionLabel(
                currentIndex: currentIndex,
                segmentCount: segmentCount,
              ),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      );
}
