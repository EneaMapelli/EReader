import 'package:flutter/material.dart';

import 'reader_chapter_history_shortcut.dart';

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
    this.sectionProgressPercent,
    this.onOpenSections,
    this.onPreviousSection,
    this.onNextSection,
    this.onHistoryBack,
    this.onHistoryForward,
    this.onHistoryRecent,
    this.historyRevision,
    this.currentHistoryRevision,
  });

  final String segmentLabel;
  final bool isPlaying;
  final bool sleepTimerActive;
  /// Visible EPUB TOC/spine position, never the active speech segment.
  /// Null for TXT, PDF or books without a navigable section.
  final String? sectionLabel;
  final int? sectionIndex;
  final int? sectionCount;
  /// Exact canonical-source percentage inside the visible EPUB section.
  /// Null when NAV/OPF source boundaries are ambiguous or empty.
  final int? sectionProgressPercent;
  final VoidCallback? onOpenSections;
  /// These move between EPUB source sections, never audio utterances.
  /// Null disables the button at the first/last section.
  final VoidCallback? onPreviousSection;
  final VoidCallback? onNextSection;
  /// Separate source-accurate history navigation; never TTS segment skips.
  final VoidCallback? onHistoryBack;
  final VoidCallback? onHistoryForward;
  final VoidCallback? onHistoryRecent;
  /// The displayed revision and a live lookup reject outdated popup
  /// actions if history changes while the user is choosing an option.
  final int? historyRevision;
  final int Function()? currentHistoryRevision;
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
            Row(
              key: const ValueKey('reader-compact-section-navigation'),
              children: [
                IconButton(
                  key: const ValueKey('reader-compact-previous-section'),
                  tooltip: 'Previous EPUB section',
                  onPressed: onPreviousSection,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('reader-compact-current-section'),
                    onPressed: onOpenSections,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 48),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${sectionLabel!} (${sectionIndex! + 1}/$sectionCount)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        if (sectionProgressPercent != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${sectionProgressPercent!.clamp(0, 100)}%',
                            key: const ValueKey(
                                'reader-compact-section-progress'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                        const SizedBox(width: 4),
                        const Icon(Icons.list, size: 18),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('reader-compact-next-section'),
                  tooltip: 'Next EPUB section',
                  onPressed: onNextSection,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
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
              if (onHistoryBack != null ||
                  onHistoryForward != null || onHistoryRecent != null)
                ReaderChapterHistoryShortcut(
                  onBack: onHistoryBack,
                  onForward: onHistoryForward,
                  onRecent: onHistoryRecent,
                  historyRevision: historyRevision,
                  currentHistoryRevision: currentHistoryRevision,
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
