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
    this.sectionLabel,
    this.sectionIndex,
    this.sectionCount,
    this.onOpenSections,
  });

  final String segmentLabel;
  final bool isPlaying;
  final bool sleepTimerActive;
  /// Visible EPUB TOC/spine position, never the active speech segment.
  /// Null for TXT, PDF or books without a navigable section.
  final String? sectionLabel;
  final int? sectionIndex;
  final int? sectionCount;
  final VoidCallback? onOpenSections;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sectionLabel != null &&
              sectionIndex != null && sectionCount != null &&
              sectionIndex! >= 0 && sectionIndex! < sectionCount! &&
              onOpenSections != null)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey('reader-compact-current-section'),
                onPressed: onOpenSections,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${sectionLabel!} (${sectionIndex! + 1}/$sectionCount)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
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
