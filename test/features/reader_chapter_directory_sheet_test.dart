import 'package:ereader/data/epub_navigation.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/reader_chapter_directory_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _launcher({
  List<EpubNavigationEntry> toc = const [],
  List<EpubChapter> chapters = const [],
  int currentToc = -1,
  int currentChapter = -1,
  required ValueChanged<int?> onSelected,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(builder: (context) => ElevatedButton(
      onPressed: () async {
        final index = await showReaderChapterDirectory(
          context,
          authorToc: toc,
          chapters: chapters,
          activeTocIndex: currentToc,
          activeChapterIndex: currentChapter,
        );
        onSelected(index);
      },
      child: const Text('Open EPUB index'),
    )),
  ),
);

void main() {
  test('publisher titles preserve original index, depth and duplicate names',
      () {
    const toc = [
      EpubNavigationEntry('Chapter', 0, 0),
      EpubNavigationEntry('Illustrations', 100, 2),
      EpubNavigationEntry('Illustrations', 100, 1),
      EpubNavigationEntry('Last CHAPTER', 200, 0),
    ];
    const chapters = [
      EpubChapter(idref: 'unused', title: 'Spine', start: 0,
          end: 10, segmentIndex: 0),
    ];
    final items = readerDirectoryItems(authorToc: toc, chapters: chapters);
    expect(items.map((e) => e.originalIndex), [0, 1, 2, 3]);
    expect(items.map((e) => e.depth), [0, 2, 1, 0]);
    expect(items.every((e) => e.isAuthorToc), isTrue);
    final illustrations = filterReaderDirectoryItems(items, '  ILLUSTRATIONS ');
    expect(illustrations.map((e) => e.originalIndex), [1, 2]);
    final search = filterReaderDirectoryItems(items, 'last chapter');
    expect(search.map((e) => e.originalIndex), [3]);
    expect(filterReaderDirectoryItems(items, 'missing'), isEmpty);
    expect(filterReaderDirectoryItems(items, '  '), same(items));
  });

  test('OPF silent same-offset sections stay distinct from narrated chapter',
      () {
    const chapters = [
      EpubChapter(idref: 'narrated', title: 'Story', start: 0,
          end: 100, segmentIndex: 0),
      EpubChapter(idref: 'art-a', title: 'Art A', start: 100,
          end: 100, segmentIndex: 1, hasSpeech: false),
      EpubChapter(idref: 'art-b', title: 'Art B', start: 100,
          end: 100, segmentIndex: 1, hasSpeech: false),
    ];
    final items = readerDirectoryItems(
      authorToc: const [], chapters: chapters,
    );
    expect(items.map((e) => e.originalIndex), [0, 1, 2]);
    expect(items.map((e) => e.hasSpeech), [true, false, false]);
    expect(filterReaderDirectoryItems(items, 'art b').single.originalIndex, 2);
  });

  testWidgets('thousands of TOC entries filter to original source index',
      (tester) async {
    final toc = List<EpubNavigationEntry>.generate(
      2000,
      (index) => EpubNavigationEntry(
        'Chapter ${index + 1}', index * 10, index.isEven ? 0 : 1,
      ),
    );
    int? chosen;
    await tester.pumpWidget(_launcher(
      toc: toc, currentToc: 1234, onSelected: (index) => chosen = index,
    ));
    await tester.tap(find.text('Open EPUB index'));
    await tester.pumpAndSettle();
    expect(find.text('Book table of contents'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-directory-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-directory-entry-1234')),
        findsOneWidget, reason: 'Unfiltered index opens near current chapter');
    expect(chosen, isNull);

    await tester.enterText(
        find.byKey(const ValueKey('reader-directory-filter')), 'Chapter 1999');
    await tester.pumpAndSettle();
    expect(find.text('1 section found'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-directory-entry-1998')),
        findsOneWidget);
    expect(chosen, isNull,
        reason: 'Typing in the index never commits a source jump');
    await tester.tap(find.byKey(const ValueKey('reader-directory-entry-1998')));
    await tester.pumpAndSettle();
    expect(chosen, 1998,
        reason: 'Filtered display index zero is NOT the original TOC index');
  });

  testWidgets('silent spine items preserve their unique original index',
      (tester) async {
    const chapters = [
      EpubChapter(idref: 'story', title: 'Story', start: 0,
          end: 100, segmentIndex: 0),
      EpubChapter(idref: 'art-1', title: 'Illustration One', start: 100,
          end: 100, segmentIndex: 1, hasSpeech: false),
      EpubChapter(idref: 'art-2', title: 'Illustration Two', start: 100,
          end: 100, segmentIndex: 1, hasSpeech: false),
    ];
    int? chosen;
    await tester.pumpWidget(_launcher(
      chapters: chapters, currentChapter: 1,
      onSelected: (index) => chosen = index,
    ));
    await tester.tap(find.text('Open EPUB index'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-directory-entry-1')),
        findsOneWidget);
    expect(find.textContaining('no spoken text'), findsWidgets);

    await tester.enterText(
        find.byKey(const ValueKey('reader-directory-filter')), 'illustration two');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-directory-entry-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-directory-entry-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reader-directory-entry-2')));
    await tester.pumpAndSettle();
    expect(chosen, 2);
  });

  testWidgets('no search results and clear restore the full chapter list',
      (tester) async {
    const chapters = [
      EpubChapter(idref: 'a', title: 'Introduction', start: 0,
          end: 10, segmentIndex: 0),
      EpubChapter(idref: 'b', title: 'The Forest', start: 10,
          end: 20, segmentIndex: 1),
      EpubChapter(idref: 'c', title: 'Afterword', start: 20,
          end: 30, segmentIndex: 2),
    ];
    int? chosen;
    await tester.pumpWidget(_launcher(
      chapters: chapters, currentChapter: 1,
      onSelected: (index) => chosen = index,
    ));
    await tester.tap(find.text('Open EPUB index'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('reader-directory-filter')), 'no such entry');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-directory-empty')), findsOneWidget);
    expect(find.text('0 sections found'), findsOneWidget);
    expect(chosen, isNull);
    await tester.tap(find.byKey(const ValueKey('reader-directory-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-directory-entry-1')),
        findsOneWidget);
    expect(find.text('The Forest'), findsOneWidget);
    expect(chosen, isNull);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(chosen, isNull,
        reason: 'Dismissal does not initiate navigation');
  });

  testWidgets('narrow screen with large text keeps chapter search usable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    int? chosen;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          chosen = await showReaderChapterDirectory(
            context,
            authorToc: const [
              EpubNavigationEntry('Long chapter name', 0, 0),
              EpubNavigationEntry('Another chapter', 100, 0),
            ],
            chapters: const [],
            activeTocIndex: 0,
            activeChapterIndex: -1,
          );
        },
        child: const Text('Open'),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-directory-filter')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('reader-directory-filter')), 'another');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-directory-entry-1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('reader-directory-entry-1')));
    await tester.pumpAndSettle();
    expect(chosen, 1);
  });
}
