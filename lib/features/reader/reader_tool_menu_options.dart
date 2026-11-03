import 'package:flutter/material.dart';

import '../shared/organized_action_sheet.dart';

/// Read-only capability snapshot for the reader tools menu. A pure
/// descriptor avoids mixing book navigation rules with menu presentation.
class ReaderToolMenuAvailability {
  const ReaderToolMenuAvailability({
    required this.isEpub,
    required this.isPdf,
    required this.textMode,
    required this.hasPlayableSegments,
    required this.hasContents,
    required this.canReturnFromLink,
    required this.hasPdfPageBookmarks,
    required this.hasEpubPerformance,
    required this.hasEpubWarnings,
    required this.autoFollow,
    this.followSuspended = false,
    required this.paletteName,
    this.focusMode = false,
    this.hasProgressReturn = false,
    this.hasSectionReturn = false,
    this.hasChapterHistory = false,
    this.hasChapterForward = false,
    this.hasSectionPosition = false,
  });

  final bool isEpub;
  final bool isPdf;
  final bool textMode;
  final bool hasPlayableSegments;
  final bool hasContents;
  final bool canReturnFromLink;
  final bool hasPdfPageBookmarks;
  final bool hasEpubPerformance;
  final bool hasEpubWarnings;
  final bool autoFollow;
  /// Active speech remains uninterrupted while a manual scroll detaches.
  final bool followSuspended;
  final String paletteName;
  final bool focusMode;
  final bool hasProgressReturn;
  /// Latest committed EPUB chapter switch can be undone.
  final bool hasSectionReturn;
  /// Multiple older committed chapter visits can be browsed.
  final bool hasChapterHistory;
  /// At least one forward location remains after a completed Back jump.
  final bool hasChapterForward;
  /// A unique, nonempty original-source interval in the current EPUB section.
  final bool hasSectionPosition;
}

List<OrganizedActionSection> buildReaderToolSections(
    ReaderToolMenuAvailability options) => [
  OrganizedActionSection(title: 'Navigate & find', items: [
    if (options.isEpub && options.hasContents)
      const OrganizedActionItem(
        id: 'contents', title: 'Table of contents',
        icon: Icons.view_list_outlined,
        subtitle: 'Jump between EPUB sections',
      ),
    if (options.isEpub && options.hasContents &&
        options.hasPlayableSegments) ...[
      const OrganizedActionItem(
        id: 'first-section', title: 'First section',
        icon: Icons.first_page,
        subtitle: 'Jump to the beginning of the EPUB contents',
      ),
      const OrganizedActionItem(
        id: 'last-section', title: 'Last section',
        icon: Icons.last_page,
        subtitle: 'Jump to the final EPUB contents section',
      ),
    ],
    if (options.textMode && options.hasPlayableSegments)
      const OrganizedActionItem(
        id: 'go-to-percent', title: 'Go to book position',
        icon: Icons.percent,
        subtitle: 'Enter a percentage of the original text',
      ),
    if (options.isEpub && options.textMode && options.hasPlayableSegments &&
        options.hasContents && options.hasSectionPosition)
      const OrganizedActionItem(
        id: 'section-percent', title: 'Go to position in this section',
        icon: Icons.linear_scale,
        subtitle: 'Choose 0–100% within the current EPUB section',
      ),
    if (options.isEpub && options.hasContents &&
        options.hasPlayableSegments && options.hasSectionReturn)
      const OrganizedActionItem(
        id: 'return-to-section',
        title: 'Return before chapter change',
        icon: Icons.undo,
        subtitle: 'Restore the exact position before the latest EPUB chapter switch',
      ),
    if (options.isEpub && options.hasContents &&
        options.hasPlayableSegments && options.hasChapterForward)
      const OrganizedActionItem(
        id: 'forward-to-section',
        title: 'Forward to next visited position',
        icon: Icons.redo,
        subtitle: 'Revisit the next EPUB position after going back',
      ),
    if (options.isEpub && options.hasContents &&
        options.hasPlayableSegments &&
        options.hasSectionReturn && options.hasChapterHistory)
      const OrganizedActionItem(
        id: 'chapter-history',
        title: 'Recent chapter positions',
        icon: Icons.history,
        subtitle: 'Return to an older position visited before changing chapters',
      ),
    if (options.textMode && options.hasPlayableSegments &&
        options.hasProgressReturn)
      const OrganizedActionItem(
        id: 'return-to-percent', title: 'Return to position before jump',
        icon: Icons.undo,
        subtitle: 'Go back after the last confirmed percentage jump',
      ),
    if (options.textMode && options.hasPlayableSegments &&
        options.autoFollow && options.followSuspended)
      const OrganizedActionItem(
        id: 'return-to-narration',
        title: 'Return to narrated passage',
        icon: Icons.my_location,
        subtitle: 'Rejoin the current speech position without seeking',
      ),
    if (options.hasPlayableSegments)
      const OrganizedActionItem(
        id: 'search', title: 'Search this book',
        icon: Icons.search,
        subtitle: 'Find words or phrases within the current book',
      ),
    if (options.hasPlayableSegments)
      const OrganizedActionItem(
        id: 'bookmarks', title: 'Bookmarks',
        icon: Icons.bookmarks_outlined,
        subtitle: 'View or manage saved reading locations',
      ),
    if (options.isPdf && !options.textMode &&
        options.hasPdfPageBookmarks)
      const OrganizedActionItem(
        id: 'pdf-bookmarks', title: 'PDF page bookmarks',
        icon: Icons.bookmarks_outlined,
      ),
    if (options.isEpub && options.canReturnFromLink)
      const OrganizedActionItem(
        id: 'return-link', title: 'Return from internal link',
        icon: Icons.keyboard_return,
      ),
    if (options.isPdf && options.textMode)
      const OrganizedActionItem(
        id: 'pdf-pages', title: 'Return to PDF pages',
        icon: Icons.picture_as_pdf_outlined,
      ),
  ]),
  OrganizedActionSection(title: 'Reading appearance', items: [
    if (options.textMode && options.hasPlayableSegments)
      OrganizedActionItem(
        id: 'reading-focus',
        title: options.focusMode
            ? 'Show narration controls' : 'Hide narration controls',
        icon: options.focusMode
            ? Icons.expand_less : Icons.fullscreen_outlined,
        subtitle: 'Give the text more space; restore controls anytime',
        selected: options.focusMode,
      ),
    if (options.textMode)
      const OrganizedActionItem(
        id: 'appearance', title: 'Font & layout',
        icon: Icons.format_line_spacing,
        subtitle: 'Text size, spacing and colors',
      ),
    if (options.textMode)
      const OrganizedActionItem(
        id: 'font-plus', title: 'Increase text size',
        icon: Icons.text_increase,
      ),
    if (options.textMode)
      const OrganizedActionItem(
        id: 'font-minus', title: 'Decrease text size',
        icon: Icons.text_decrease,
      ),
    if (options.textMode)
      OrganizedActionItem(
        id: 'auto-follow', title: 'Follow narration',
        icon: options.autoFollow ? Icons.my_location
            : Icons.location_disabled,
        subtitle: options.followSuspended
            ? 'Temporarily paused after manual scrolling'
            : 'Automatically scroll while reading aloud',
        selected: options.autoFollow,
      ),
    if (options.isEpub) ...[
      OrganizedActionItem(
        id: 'palette-system', title: 'Device colors',
        icon: Icons.brightness_auto_outlined,
        selected: options.paletteName == 'system',
      ),
      OrganizedActionItem(
        id: 'palette-sepia', title: 'Warm paper',
        icon: Icons.wb_sunny_outlined,
        selected: options.paletteName == 'sepia',
      ),
      OrganizedActionItem(
        id: 'palette-night', title: 'Night reading',
        icon: Icons.dark_mode_outlined,
        selected: options.paletteName == 'night',
      ),
      OrganizedActionItem(
        id: 'palette-contrast', title: 'High contrast',
        icon: Icons.contrast,
        selected: options.paletteName == 'highContrast',
      ),
    ],
  ]),
  OrganizedActionSection(title: 'Speech & characters', items: [
    const OrganizedActionItem(
      id: 'speech', title: 'TTS engines & voices',
      icon: Icons.tune,
      subtitle: 'Offline models, language and cloud consent',
    ),
    if (options.hasPlayableSegments)
      const OrganizedActionItem(
        id: 'cast', title: 'Characters & voice cast',
        icon: Icons.theater_comedy_outlined,
      ),
    const OrganizedActionItem(
      id: 'pronunciation', title: 'Pronunciation dictionary',
      icon: Icons.spellcheck,
    ),
  ]),
  OrganizedActionSection(title: 'Help & diagnostics', items: [
    const OrganizedActionItem(
      id: 'keyboard-help', title: 'Keyboard shortcuts',
      icon: Icons.keyboard_outlined,
    ),
    if (options.isEpub && options.hasEpubPerformance)
      const OrganizedActionItem(
        id: 'epub-performance', title: 'EPUB opening performance',
        icon: Icons.speed_outlined,
        subtitle: 'Inspect opening and rendering timings',
      ),
    if (options.isEpub && options.hasEpubWarnings)
      const OrganizedActionItem(
        id: 'epub-compat', title: 'EPUB compatibility report',
        icon: Icons.report_problem_outlined,
      ),
  ]),
];

/// A shorter, navigation-only entry point for the compact reader AppBar.
/// Reuse the full menu's capability-gated actions; never create separate
/// seek or playback behavior for mobile. Keep frequently used destinations
/// first and the rarer boundary/return actions available at the end.
List<OrganizedActionSection> buildReaderQuickNavigationSections(
    ReaderToolMenuAvailability options) {
  final navigation = buildReaderToolSections(options).first.items;
  const order = <String>[
    'search',
    'contents',
    'bookmarks',
    'go-to-percent',
    'section-percent',
    'return-to-section',
    'forward-to-section',
    'chapter-history',
    'pdf-bookmarks',
    'return-link',
    'return-to-percent',
    'return-to-narration',
    'pdf-pages',
    'first-section',
    'last-section',
  ];
  final quickItems = <OrganizedActionItem>[
    for (final id in order)
      for (final item in navigation)
        if (item.id == id) item,
  ];
  if (quickItems.isEmpty) return const <OrganizedActionSection>[];
  return <OrganizedActionSection>[
    OrganizedActionSection(title: 'Navigate & find', items: quickItems),
  ];
}
