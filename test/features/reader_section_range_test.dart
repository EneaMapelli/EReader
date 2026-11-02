import 'package:ereader/data/epub_navigation.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/reader_section_range.dart';
import 'package:flutter_test/flutter_test.dart';

ReaderSectionRange? range({
  List<EpubNavigationEntry> toc = const [],
  List<EpubChapter> chapters = const [],
  int index = 0,
  int sourceLength = 300,
}) => readerSectionRangeForIndex(
  authorToc: toc,
  chapters: chapters,
  currentIndex: index,
  sourceLength: sourceLength,
);

void main() {
  test('publisher TOC uses canonical source offsets not chapter ordinals', () {
    const toc = [
      EpubNavigationEntry('Opening', 0, 0),
      EpubNavigationEntry('Chapter Two', 100, 0),
      EpubNavigationEntry('Ending', 200, 0),
    ];
    final chapter = range(toc: toc, index: 1)!;
    expect([chapter.start, chapter.end, chapter.length], [100, 200, 100]);
    expect(chapter.percentageAt(130), 30);
    expect(chapter.percentageAt(-100), 0);
    expect(chapter.percentageAt(500), 100);
    expect(chapter.offsetAtPercentage(0), 100);
    expect(chapter.offsetAtPercentage(25), 125);
    expect(chapter.offsetAtPercentage(75), 175);
    expect(chapter.offsetAtPercentage(100), 199,
        reason: '100% must not select the NEXT EPUB chapter');
    expect(() => chapter.offsetAtPercentage(-1), throwsArgumentError);
    expect(() => chapter.offsetAtPercentage(101), throwsArgumentError);
    expect(range(toc: toc, index: 2)!.end, 300,
        reason: 'Final section ends at canonical source EOF');
  });

  test('out of order editorial TOC uses nearest higher source boundary', () {
    const toc = [
      EpubNavigationEntry('Final', 240, 0),
      EpubNavigationEntry('First', 0, 0),
      EpubNavigationEntry('Middle', 100, 1),
      EpubNavigationEntry('Late', 180, 0),
    ];
    final first = range(toc: toc, index: 1)!;
    final middle = range(toc: toc, index: 2)!;
    expect([first.start, first.end], [0, 100]);
    expect([middle.start, middle.end], [100, 180]);
    expect([range(toc: toc, index: 0)!.start,
        range(toc: toc, index: 0)!.end], [240, 300]);
  });

  test('duplicate publisher anchors cannot fabricate unique local progress',
      () {
    const toc = [
      EpubNavigationEntry('Cover', 0, 0),
      EpubNavigationEntry('Chapter', 0, 1),
      EpubNavigationEntry('Text', 70, 0),
    ];
    expect(range(toc: toc, index: 0), isNull);
    expect(range(toc: toc, index: 1), isNull);
    expect(range(toc: toc, index: 2), isNotNull);
    expect(range(toc: toc, index: 2)!.offsetAtPercentage(100), 299);
  });

  test('OPF fallback honors exact spine bounds and silent zero spans', () {
    const chapters = [
      EpubChapter(idref: 'one', title: 'One', start: 0, end: 100,
          segmentIndex: 0),
      EpubChapter(idref: 'illustration', title: 'Cover', start: 100,
          end: 100, segmentIndex: 1, hasSpeech: false),
      EpubChapter(idref: 'two', title: 'Two', start: 100, end: 220,
          segmentIndex: 1),
    ];
    expect(range(chapters: chapters, index: 0)!.end, 100);
    expect(range(chapters: chapters, index: 1), isNull);
    expect(range(chapters: chapters, index: 2), isNull,
        reason: 'Equal OPF start offsets are visually ambiguous');
  });

  test('single OPF section and invalid data fail closed safely', () {
    const chapters = [
      EpubChapter(idref: 'one', title: 'One', start: 10, end: 20,
          segmentIndex: 0),
    ];
    final selected = range(chapters: chapters, sourceLength: 30)!;
    expect(selected.offsetAtPercentage(100), 19);
    expect(range(chapters: chapters, sourceLength: 15), isNull);
    expect(range(chapters: chapters, index: -1), isNull);
    expect(range(chapters: chapters, index: 7), isNull);
    expect(range(chapters: chapters, sourceLength: 0), isNull);
    expect(range(toc: const [
      EpubNavigationEntry('Malformed', -2, 0),
    ]), isNull);
    expect(range(toc: const [
      EpubNavigationEntry('Malformed', 330, 0),
    ]), isNull);
    expect(range(toc: const [
      EpubNavigationEntry('Current', 100, 0),
      EpubNavigationEntry('Out of range', 900, 0),
    ]), isNull);
  });
}
