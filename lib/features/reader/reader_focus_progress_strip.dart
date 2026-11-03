import 'package:flutter/material.dart';

import '../../domain/reading_progress.dart';

/// Source-text progress in immersive reading mode, separate from the
/// narration clock and the active TTS segment.
///
/// The first row is always the original whole-book text position. EPUBs
/// may expose a second compact, independently actionable section row:
/// its title opens the existing directory, and an optional local
/// percentage opens the existing section Go dialog. These controls
/// never seek, play audio, or persist checkpoints themselves.
class ReaderFocusProgressStrip extends StatelessWidget
    implements PreferredSizeWidget {
  const ReaderFocusProgressStrip({
    super.key,
    required this.sourceOffset,
    required this.sourceLength,
    required this.onNavigate,
    this.sectionTitle,
    this.sectionIndex,
    this.sectionCount,
    this.sectionProgressPercent,
    this.onOpenSections,
    this.onNavigateWithinSection,
    this.onPreviousSection,
    this.onNextSection,
  });

  final int sourceOffset;
  final int sourceLength;
  final VoidCallback onNavigate;
  final String? sectionTitle;
  final int? sectionIndex;
  final int? sectionCount;
  final int? sectionProgressPercent;
  final VoidCallback? onOpenSections;
  final VoidCallback? onNavigateWithinSection;
  /// Navigation across EPUB sections; null means at a boundary.
  /// Distinct from TTS previous/next segment transport.
  final VoidCallback? onPreviousSection;
  final VoidCallback? onNextSection;

  bool get _hasSection => sectionTitle != null &&
      sectionIndex != null && sectionCount != null &&
      sectionCount! > 0 && sectionIndex! >= 0 &&
      sectionIndex! < sectionCount! && onOpenSections != null;

  @override
  Size get preferredSize => Size.fromHeight(_hasSection ? 92 : 44);

  @override
  Widget build(BuildContext context) {
    final progress = ReadingSourceProgress.fraction(
      offset: sourceOffset,
      length: sourceLength,
    );
    final percent = (progress * 100).round();
    final colorScheme = Theme.of(context).colorScheme;
    final background = Theme.of(context).appBarTheme.backgroundColor ??
        colorScheme.surface;
    final localPercent = sectionProgressPercent?.clamp(0, 100).toInt();
    final canGoToSection = _hasSection && localPercent != null &&
        onNavigateWithinSection != null;
    // On narrow devices with large accessibility text the title remains
    // visible, while the ordinal is provided in the semantic label.
    final showVisualOrdinal = MediaQuery.sizeOf(context).width >= 320 &&
        MediaQuery.textScalerOf(context).scale(12) <= 18;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Semantics(
            key: const ValueKey('reader-focus-progress-semantics'),
            button: sourceLength > 0,
            enabled: sourceLength > 0,
            label: sourceLength > 0
                ? 'Book text position: $percent percent. '
                    'Open go to book position'
                : 'Book text position unavailable',
            onTap: sourceLength > 0 ? onNavigate : null,
            child: ExcludeSemantics(
              child: Material(
                color: background,
                child: InkWell(
                  key: const ValueKey('reader-focus-progress'),
                  onTap: sourceLength > 0 ? onNavigate : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            '$percent%',
                            key: const ValueKey('reader-focus-progress-label'),
                            style: Theme.of(context).textTheme.labelMedium,
                            textAlign: TextAlign.start,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            key: const ValueKey('reader-focus-progress-track'),
                            value: progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right,
                            color: colorScheme.onSurfaceVariant, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_hasSection)
          SizedBox(
            height: 48,
            child: Material(
              color: background,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('reader-focus-previous-section'),
                    tooltip: 'Previous EPUB section',
                    onPressed: onPreviousSection,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Semantics(
                      key: const ValueKey('reader-focus-section-semantics'),
                      button: true,
                      label: 'Current EPUB section: $sectionTitle, '
                          '${sectionIndex! + 1} of $sectionCount. '
                          'Open table of contents',
                      onTap: onOpenSections,
                      child: ExcludeSemantics(
                        child: InkWell(
                          key: const ValueKey('reader-focus-section'),
                          onTap: onOpenSections,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, right: 4),
                            child: Row(
                              children: [
                                Icon(Icons.menu_book_outlined,
                                    size: 18, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    sectionTitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                                if (showVisualOrdinal) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '${sectionIndex! + 1}/$sectionCount',
                                    key: const ValueKey(
                                        'reader-focus-section-number'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canGoToSection)
                    Semantics(
                      key: const ValueKey(
                          'reader-focus-section-progress-semantics'),
                      button: true,
                      label: 'Section text position: $localPercent percent. '
                          'Go to a position in this section',
                      onTap: onNavigateWithinSection,
                      child: ExcludeSemantics(
                        child: TextButton(
                          key: const ValueKey('reader-focus-section-go'),
                          onPressed: onNavigateWithinSection,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(56, 48),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('$localPercent%'),
                        ),
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('reader-focus-next-section'),
                    tooltip: 'Next EPUB section',
                    onPressed: onNextSection,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
