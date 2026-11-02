import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../data/epub_navigation.dart';
import 'epub_chapter_navigation.dart';

/// An EPUB directory destination keeps its ORIGINAL author-TOC or OPF spine
/// index. Filtering is presentation-only: result indices must never be used
/// as chapter numbers or source offsets.
class ReaderDirectoryItem {
  const ReaderDirectoryItem({
    required this.originalIndex,
    required this.title,
    required this.depth,
    required this.hasSpeech,
    required this.isAuthorToc,
  });

  final int originalIndex;
  final String title;
  final int depth;
  final bool hasSpeech;
  final bool isAuthorToc;
}

List<ReaderDirectoryItem> readerDirectoryItems({
  required List<EpubNavigationEntry> authorToc,
  required List<EpubChapter> chapters,
}) {
  if (authorToc.isNotEmpty) {
    return [
      for (var i = 0; i < authorToc.length; i++)
        ReaderDirectoryItem(
          originalIndex: i,
          title: authorToc[i].label,
          depth: authorToc[i].depth,
          hasSpeech: true, // Author TOC entries may target silent content.
          isAuthorToc: true,
        ),
    ];
  }
  return [
    for (var i = 0; i < chapters.length; i++)
      ReaderDirectoryItem(
        originalIndex: i,
        title: chapters[i].title,
        depth: 0,
        hasSpeech: chapters[i].hasSpeech,
        isAuthorToc: false,
      ),
  ];
}

/// Case-insensitive all-word matching. Keep editorial order and ORIGINAL
/// source identities, including duplicate labels and illustration-only
/// sections sharing an EPUB source offset.
List<ReaderDirectoryItem> filterReaderDirectoryItems(
    List<ReaderDirectoryItem> entries, String query) {
  final words = query.trim().toLowerCase()
      .split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return entries;
  return [
    for (final entry in entries)
      if (words.every((word) => entry.title.toLowerCase().contains(word)))
        entry,
  ];
}

/// The sheet only returns an original directory index. The reader decides
/// whether/how to seek after this route closes, through its existing
/// latest-wins selection barrier. Opening/searching/canceling never plays
/// TTS and never writes a bookmark.
Future<int?> showReaderChapterDirectory(
  BuildContext context, {
  required List<EpubNavigationEntry> authorToc,
  required List<EpubChapter> chapters,
  required int activeTocIndex,
  required int activeChapterIndex,
}) {
  final entries = readerDirectoryItems(authorToc: authorToc, chapters: chapters);
  if (entries.isEmpty) return Future<int?>.value(null);
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ReaderChapterDirectoryBody(
      entries: entries,
      currentIndex: authorToc.isNotEmpty
          ? activeTocIndex : activeChapterIndex,
      authorial: authorToc.isNotEmpty,
    ),
  );
}

class _ReaderChapterDirectoryBody extends StatefulWidget {
  const _ReaderChapterDirectoryBody({
    required this.entries,
    required this.currentIndex,
    required this.authorial,
  });
  final List<ReaderDirectoryItem> entries;
  final int currentIndex;
  final bool authorial;

  @override
  State<_ReaderChapterDirectoryBody> createState() =>
      _ReaderChapterDirectoryBodyState();
}

class _ReaderChapterDirectoryBodyState
    extends State<_ReaderChapterDirectoryBody> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = (screenHeight * 0.72 - keyboard)
        .clamp(160.0, screenHeight * 0.72).toDouble();
    final visible = filterReaderDirectoryItems(widget.entries, _query);
    final isFiltering = _query.trim().isNotEmpty;
    final current = widget.currentIndex;
    // A newly filtered list starts at its first MATCH. Unfiltered lists
    // open near the actual source section, preserving virtual rendering.
    final initial = !isFiltering && current >= 0 &&
            current < widget.entries.length ? current : 0;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              ListTile(
                title: Text(widget.authorial
                    ? 'Book table of contents' : 'EPUB spine sections'),
                subtitle: Text('${widget.entries.length} sections'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  key: const ValueKey('reader-directory-filter'),
                  controller: _queryController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Find a chapter or section',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty ? null : IconButton(
                      key: const ValueKey('reader-directory-clear'),
                      tooltip: 'Clear chapter search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _queryController.clear();
                        setState(() => _query = '');
                      },
                    ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (isFiltering)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        visible.length == 1
                            ? '1 section found'
                            : '${visible.length} sections found',
                        key: const ValueKey('reader-directory-match-count'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No chapters match your search.',
                          key: ValueKey('reader-directory-empty'),
                        ),
                      )
                    : ScrollablePositionedList.builder(
                        key: ValueKey('reader-directory-results-$_query'),
                        initialScrollIndex: initial,
                        itemCount: visible.length,
                        itemBuilder: (_, resultIndex) {
                          final item = visible[resultIndex];
                          final selected = item.originalIndex == current;
                          final subtitle = item.isAuthorToc
                              ? (selected ? 'Current section' : null)
                              : 'Section ${item.originalIndex + 1} of '
                                '${widget.entries.length}'
                                '${item.hasSpeech ? '' : ' · no spoken text'}'
                                '${selected ? ' · current section' : ''}';
                          return Padding(
                            padding: EdgeInsets.only(
                              left: (item.depth.clamp(0, 12) * 14).toDouble(),
                            ),
                            child: ListTile(
                              key: ValueKey('reader-directory-entry-'
                                  '${item.originalIndex}'),
                              dense: true,
                              leading: Icon(selected
                                  ? Icons.menu_book
                                  : item.isAuthorToc
                                      ? Icons.subdirectory_arrow_right
                                      : Icons.article_outlined),
                              title: Text(item.title),
                              subtitle: subtitle == null
                                  ? null : Text(subtitle),
                              selected: selected,
                              onTap: () => Navigator.of(context)
                                  .pop(item.originalIndex),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
