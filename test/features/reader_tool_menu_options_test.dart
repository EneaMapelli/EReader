import 'package:ereader/features/reader/reader_tool_menu_options.dart';
import 'package:ereader/features/shared/organized_action_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

ReaderToolMenuAvailability options({
  bool epub = false,
  bool pdf = false,
  bool text = true,
  bool playable = true,
  bool toc = false,
  bool returnLink = false,
  bool pdfBookmarks = false,
  bool perf = false,
  bool warnings = false,
  bool autoFollow = true,
  bool followSuspended = false,
  bool focus = false,
  bool progressReturn = false,
  bool sectionPosition = false,
  String palette = 'system',
}) => ReaderToolMenuAvailability(
  isEpub: epub, isPdf: pdf, textMode: text,
  hasPlayableSegments: playable,
  hasContents: toc, canReturnFromLink: returnLink,
  hasPdfPageBookmarks: pdfBookmarks,
  hasEpubPerformance: perf, hasEpubWarnings: warnings,
  autoFollow: autoFollow, followSuspended: followSuspended,
  focusMode: focus,
  hasProgressReturn: progressReturn,
  hasSectionPosition: sectionPosition,
  paletteName: palette,
);

List<String> ids(List<OrganizedActionSection> sections) =>
    [for (final section in sections)
      for (final item in section.items) item.id];

void main() {
  test('local EPUB percent appears only for unique source section ranges', () {
    final epub = options(
        epub: true, toc: true, sectionPosition: true);
    final quick = ids(buildReaderQuickNavigationSections(epub));
    expect(quick, contains('section-percent'));
    expect(quick.indexOf('section-percent'),
        quick.indexOf('go-to-percent') + 1);
    expect(ids(buildReaderToolSections(epub)), contains('section-percent'));
    for (final unavailable in [
      options(epub: true, sectionPosition: false),
      options(epub: true, sectionPosition: true, playable: false),
      options(epub: true, sectionPosition: true, toc: false),
      options(pdf: true, text: true, sectionPosition: true),
      options(sectionPosition: true),
    ]) {
      expect(ids(buildReaderToolSections(unavailable)),
          isNot(contains('section-percent')));
      expect(ids(buildReaderQuickNavigationSections(unavailable)),
          isNot(contains('section-percent')));
    }
  });

  test('quick navigation prioritizes search, TOC, bookmarks and Go', () {
    final quick = buildReaderQuickNavigationSections(options(
      epub: true, toc: true, returnLink: true,
      progressReturn: true, followSuspended: true,
    ));
    expect(quick, hasLength(1));
    expect(quick.single.title, 'Navigate & find');
    final quickIds = ids(quick);
    expect(quickIds.take(4).toList(),
        ['search', 'contents', 'bookmarks', 'go-to-percent']);
    expect(quickIds, containsAll([
      'return-link', 'return-to-percent', 'return-to-narration',
      'first-section', 'last-section',
    ]));
    expect(quickIds.toSet().length, quickIds.length,
        reason: 'A destination is shown at most once');
    expect(quickIds, isNot(contains('speech')));
    expect(quickIds, isNot(contains('auto-follow')));
    expect(quickIds, isNot(contains('palette-night')));
    expect(quickIds, isNot(contains('reading-focus')));
  });

  test('compact PDF page navigation shows only available page bookmarks', () {
    final quick = buildReaderQuickNavigationSections(options(
      pdf: true, text: false, playable: false, pdfBookmarks: true,
    ));
    expect(ids(quick), ['pdf-bookmarks']);
    expect(ids(buildReaderQuickNavigationSections(options(
      pdf: true, text: false, playable: false, pdfBookmarks: false,
    ))), isEmpty);
  });

  test('silent EPUB TOC stays reachable without fabricated speech actions',
      () {
    final actions = ids(buildReaderQuickNavigationSections(options(
      epub: true, toc: true, playable: false,
    )));
    expect(actions, ['contents']);
    expect(actions, isNot(contains('search')));
    expect(actions, isNot(contains('first-section')));
  });

  test('TXT and extracted PDF quick navigation use source-safe actions',
      () {
    final txt = ids(buildReaderQuickNavigationSections(options()));
    expect(txt.take(3), ['search', 'bookmarks', 'go-to-percent']);
    expect(txt, isNot(contains('contents')));
    expect(txt, isNot(contains('pdf-pages')));
    final pdf = ids(buildReaderQuickNavigationSections(options(
      pdf: true, text: true, playable: true,
    )));
    expect(pdf.take(3), ['search', 'bookmarks', 'go-to-percent']);
    expect(pdf.last, 'pdf-pages');
    expect(pdf, isNot(contains('pdf-bookmarks')));
  });

  test('EPUB groups all relevant commands and marks the chosen palette',
      () {
    final sections = buildReaderToolSections(options(
      epub: true, toc: true, returnLink: true,
      perf: true, warnings: true, palette: 'night',
    ));
    expect(sections.map((s) => s.title), [
      'Navigate & find', 'Reading appearance',
      'Speech & characters', 'Help & diagnostics',
    ]);
    final actions = ids(sections);
    for (final action in [
      'contents', 'first-section', 'last-section',
      'return-link', 'search', 'bookmarks', 'go-to-percent',
      'appearance', 'font-plus', 'font-minus', 'auto-follow',
      'reading-focus',
      'palette-system', 'palette-sepia', 'palette-night',
      'palette-contrast', 'speech', 'cast', 'pronunciation',
      'keyboard-help', 'epub-performance', 'epub-compat',
    ]) {
      expect(actions, contains(action), reason: 'Missing $action');
    }
    final colors = sections.expand((s) => s.items)
        .where((i) => i.id.startsWith('palette-')).toList();
    expect(colors.where((i) => i.selected).map((i) => i.id),
        ['palette-night']);
    expect(actions, isNot(contains('pdf-pages')));
    expect(actions, isNot(contains('pdf-bookmarks')));
  });

  test('visual PDF provides page bookmarks without text-only controls',
      () {
    final items = ids(buildReaderToolSections(options(
      pdf: true, text: false, playable: false, pdfBookmarks: true,
    )));
    expect(items, contains('pdf-bookmarks'));
    expect(items, isNot(contains('search')));
    expect(items, isNot(contains('bookmarks')));
    expect(items, isNot(contains('appearance')));
    expect(items, isNot(contains('reading-focus')));
    expect(items, isNot(contains('go-to-percent')));
    expect(items, isNot(contains('first-section')));
    expect(items, isNot(contains('last-section')));
    expect(items, isNot(contains('auto-follow')));
    expect(items, isNot(contains('pdf-pages')));
    expect(items, isNot(contains('palette-night')));
    expect(items, contains('speech'));
    expect(items, contains('keyboard-help'));
  });

  test('PDF text mode restores page-view action without EPUB options', () {
    final items = ids(buildReaderToolSections(options(
      pdf: true, text: true, playable: true, pdfBookmarks: true,
    )));
    expect(items, containsAll(['pdf-pages', 'search', 'bookmarks',
      'appearance', 'font-plus', 'auto-follow', 'reading-focus',
      'go-to-percent']));
    expect(items, isNot(contains('pdf-bookmarks')));
    expect(items, isNot(contains('contents')));
    expect(items, isNot(contains('first-section')));
    expect(items, isNot(contains('last-section')));
    expect(items, isNot(contains('epub-compat')));
  });

  test('TXT keeps reading, search and speech tools, not EPUB/PDF controls',
      () {
    final sections = buildReaderToolSections(options(
        autoFollow: false));
    final items = ids(sections);
    expect(items, containsAll(['search', 'bookmarks', 'go-to-percent',
      'appearance', 'speech', 'pronunciation', 'keyboard-help']));
    expect(items, isNot(contains('contents')));
    expect(items, isNot(contains('first-section')));
    expect(items, isNot(contains('last-section')));
    expect(items, isNot(contains('pdf-pages')));
    expect(items, isNot(contains('palette-night')));
    expect(items, isNot(contains('epub-performance')));
    final follow = sections.expand((s) => s.items)
        .singleWhere((i) => i.id == 'auto-follow');
    expect(follow.selected, isFalse);
  });

  test('temporarily detached follow shows return command only when valid', () {
    final detached = buildReaderToolSections(options(
        epub: true, autoFollow: true, followSuspended: true));
    final commands = ids(detached);
    expect(commands, contains('return-to-narration'));
    final follow = detached.expand((s) => s.items)
        .singleWhere((item) => item.id == 'auto-follow');
    expect(follow.selected, isTrue,
        reason: 'Temporary scrolling must not disable the user preference');
    expect(follow.subtitle, contains('Temporarily paused'));

    for (final combination in [
      options(epub: true, followSuspended: false),
      options(epub: true, autoFollow: false, followSuspended: true),
      options(pdf: true, text: false, followSuspended: true),
      options(epub: true, playable: false, followSuspended: true),
    ]) {
      final unavailable = ids(buildReaderToolSections(combination));
      expect(unavailable, isNot(contains('return-to-narration')));
    }
    expect(ids(buildReaderToolSections(options(
        pdf: true, text: true, followSuspended: true))),
        contains('return-to-narration'));
  });

  test('focus reading mode is selectable only with readable text', () {
    final normal = buildReaderToolSections(options(epub: true));
    final focusOff = normal.expand((s) => s.items)
        .singleWhere((item) => item.id == 'reading-focus');
    expect(focusOff.title, 'Hide narration controls');
    expect(focusOff.selected, isFalse);

    final focused = buildReaderToolSections(options(epub: true, focus: true));
    final focusOn = focused.expand((s) => s.items)
        .singleWhere((item) => item.id == 'reading-focus');
    expect(focusOn.title, 'Show narration controls');
    expect(focusOn.selected, isTrue);

    final missingText = ids(buildReaderToolSections(
        options(epub: true, playable: false)));
    expect(missingText, isNot(contains('reading-focus')));

    final visualPdf = ids(buildReaderToolSections(
        options(pdf: true, text: false, playable: true)));
    expect(visualPdf, isNot(contains('reading-focus')));

    final textPdf = ids(buildReaderToolSections(
        options(pdf: true, text: true, playable: true)));
    expect(textPdf, contains('reading-focus'));
  });

  test('silent-only EPUB keeps TOC visible but hides inert edge jumps',
      () {
    final items = ids(buildReaderToolSections(options(
      epub: true, toc: true, playable: false,
    )));
    expect(items, contains('contents'));
    expect(items, isNot(contains('first-section')));
    expect(items, isNot(contains('last-section')));
  });

  test('return to percentage jump appears only for available text', () {
    final normal = ids(buildReaderToolSections(options(
        epub: true, toc: true, playable: true)));
    expect(normal, isNot(contains('return-to-percent')));
    for (final settings in [
      options(epub: true, toc: true, progressReturn: true),
      options(progressReturn: true),
      options(pdf: true, text: true, progressReturn: true),
    ]) {
      final actions = ids(buildReaderToolSections(settings));
      expect(actions, contains('go-to-percent'));
      expect(actions, contains('return-to-percent'));
    }
    for (final settings in [
      options(pdf: true, text: false, progressReturn: true),
      options(epub: true, playable: false, progressReturn: true),
      options(pdf: true, text: true, playable: false,
          progressReturn: true),
    ]) {
      final actions = ids(buildReaderToolSections(settings));
      expect(actions, isNot(contains('return-to-percent')));
    }
  });

  test('loading or incompatible EPUB never invents unavailable actions',
      () {
    final items = ids(buildReaderToolSections(options(
      epub: true, playable: false, toc: false,
      perf: false, warnings: false,
    )));
    expect(items, isNot(contains('contents')));
    expect(items, isNot(contains('first-section')));
    expect(items, isNot(contains('last-section')));
    expect(items, isNot(contains('search')));
    expect(items, isNot(contains('go-to-percent')));
    expect(items, isNot(contains('cast')));
    expect(items, isNot(contains('epub-performance')));
    expect(items, isNot(contains('epub-compat')));
    expect(items, contains('speech'));
    expect(items, contains('pronunciation'));
  });
}
