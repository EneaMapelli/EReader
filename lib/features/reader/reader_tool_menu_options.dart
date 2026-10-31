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
    required this.paletteName,
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
  final String paletteName;
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
        subtitle: 'Automatically scroll while reading aloud',
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
