import 'package:flutter/material.dart';

/// Always-visible narration transport for the reading surface.
///
/// Advanced engine, voice and diagnostic settings live behind the explicit
/// More controls action. This widget owns no player, file or speech provider
/// state: it simply delegates to the reader's existing guarded callbacks.
class ReaderCompactControls extends StatelessWidget {
  const ReaderCompactControls({
    super.key,
    required this.segmentLabel,
    required this.isPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onExpand,
    this.sleepTimerActive = false,
  });

  final String segmentLabel;
  final bool isPlaying;
  final bool sleepTimerActive;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              segmentLabel,
              key: const ValueKey('reader-compact-segment'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            key: const ValueKey('reader-compact-transport'),
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              IconButton(
                key: const ValueKey('reader-compact-previous'),
                tooltip: 'Previous segment (Left arrow)',
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton.filledTonal(
                key: const ValueKey('reader-compact-play-pause'),
                tooltip: isPlaying ? 'Pause narration (Space)' :
                    'Play narration (Space)',
                onPressed: onPlayPause,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                key: const ValueKey('reader-compact-next'),
                tooltip: 'Next segment (Right arrow)',
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
              ),
              IconButton(
                key: const ValueKey('reader-expand-controls'),
                tooltip: sleepTimerActive
                    ? 'More narration controls (sleep timer active)'
                    : 'More narration controls',
                onPressed: onExpand,
                icon: Icon(sleepTimerActive
                    ? Icons.tune : Icons.tune_outlined),
              ),
            ],
          ),
        ],
      );
}
