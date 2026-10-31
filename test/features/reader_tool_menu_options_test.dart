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
  String palette = 'system',
}) => ReaderToolMenuAvailability(
  isEpub: epub, isPdf: pdf, textMode: text,
  hasPlayableSegments: playable,
  hasContents: toc, canReturnFromLink: returnLink,
  hasPdfPageBookmarks: pdfBookmarks,
  hasEpubPerformance: perf, hasEpubWarnings: warnings,
  autoFollow: autoFollow, paletteName: palette,
);

List<String> ids(List<OrganizedActionSection> sections) =>
    [for (final section in sections)
      for (final item in section.items) item.id];

void main() {
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
      'contents', 'return-link', 'search', 'bookmarks',
      'appearance', 'font-plus', 'font-minus', 'auto-follow',
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
      'appearance', 'font-plus', 'auto-follow']));
    expect(items, isNot(contains('pdf-bookmarks')));
    expect(items, isNot(contains('contents')));
    expect(items, isNot(contains('epub-compat')));
  });

  test('TXT keeps reading, search and speech tools, not EPUB/PDF controls',
      () {
    final sections = buildReaderToolSections(options(
        autoFollow: false));
    final items = ids(sections);
    expect(items, containsAll(['search', 'bookmarks',
      'appearance', 'speech', 'pronunciation', 'keyboard-help']));
    expect(items, isNot(contains('contents')));
    expect(items, isNot(contains('pdf-pages')));
    expect(items, isNot(contains('palette-night')));
    expect(items, isNot(contains('epub-performance')));
    final follow = sections.expand((s) => s.items)
        .singleWhere((i) => i.id == 'auto-follow');
    expect(follow.selected, isFalse);
  });

  test('loading or incompatible EPUB never invents unavailable actions',
      () {
    final items = ids(buildReaderToolSections(options(
      epub: true, playable: false, toc: false,
      perf: false, warnings: false,
    )));
    expect(items, isNot(contains('contents')));
    expect(items, isNot(contains('search')));
    expect(items, isNot(contains('cast')));
    expect(items, isNot(contains('epub-performance')));
    expect(items, isNot(contains('epub-compat')));
    expect(items, contains('speech'));
    expect(items, contains('pronunciation'));
  });
}
