import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = 'Opening.';
  const second = 'Later spoken.';
  const source = '$first\n\n$second\n\n';
  const document = DocumentContent(
    title: 'Sections',
    text: source,
    epubSpineRanges: [
      EpubSpineRange(idref: 'spoken-1', href: 'a.xhtml',
          start: 0, end: first.length, title: 'First'),
      EpubSpineRange(idref: 'illustration', href: 'images.xhtml',
          start: first.length, end: first.length + 2,
          title: 'Illustrations'),
      EpubSpineRange(idref: 'spoken-2', href: 'b.xhtml',
          start: first.length + 2,
          end: first.length + 2 + second.length, title: 'Second'),
      EpubSpineRange(idref: 'silent-end', href: 'appendix.xhtml',
          start: first.length + 2 + second.length,
          end: source.length, title: 'Visual appendix'),
    ],
  );
  const clips = [
    SpeechSegment(0, first.length, first),
    SpeechSegment(first.length + 2, first.length + 2 + second.length, second),
  ];

  test('EPUB OPF index keeps silent middle and trailing sections', () {
    final chapters = buildEpubChapters(document, clips);
    expect(chapters.map((c) => c.title),
        ['First', 'Illustrations', 'Second', 'Visual appendix']);
    expect(chapters.map((c) => c.hasSpeech), [true, false, true, false]);
    expect(chapters.map((c) => c.segmentIndex), [0, 1, 1, clips.length]);
    expect(chapters.map((c) => c.start), [
      0,
      first.length,
      first.length + 2,
      first.length + 2 + second.length,
    ]);
    expect(chapterIndexForOffset(chapters, first.length), 1);
    expect(chapterIndexForOffset(chapters, first.length + 2), 2);
    expect(chapterIndexForOffset(chapters, source.length), 3);
  });

  test('silent source jumps use next audible clip, not prior one', () {
    final middle = first.length;
    expect(speechSourceDestinationIndexForOffset(clips, middle), 1);
    expect(speechSourceDestinationIndexForOffset(
        clips, first.length + 2), 1);
    // Previous resolver intentionally clamps explicit *spoken* jumps.
    expect(speechSegmentIndexForOffset(clips, source.length), 1);
    // Source-exact navigation has to keep silent trailing EPUB pages
    // separate; it may not play the previous chapter's last sentence.
    expect(speechSourceDestinationIndexForOffset(
        clips, second.length + first.length + 2), clips.length);
    expect(speechSourceDestinationIndexForOffset(
        clips, source.length), clips.length);
    expect(speechSourceDestinationIndexForOffset(const [], 0), -1);
  });

  test('empty OPF spine ranges are represented without inventing speech', () {
    const doc = DocumentContent(
      title: 'Empty',
      text: 'Sound.',
      epubSpineRanges: [
        EpubSpineRange(idref: 'cover', href: 'cover.xhtml',
            start: 0, end: 0, title: 'Cover'),
        EpubSpineRange(idref: 'text', href: 'text.xhtml',
            start: 0, end: 6, title: 'Main'),
        EpubSpineRange(idref: 'last', href: 'last.xhtml',
            start: 6, end: 6, title: 'End'),
      ],
    );
    const speech = [SpeechSegment(0, 6, 'Sound.')];
    final chapters = buildEpubChapters(doc, speech);
    expect(chapters, hasLength(3));
    expect(chapters.map((c) => c.segmentIndex), [0, 0, 1]);
    expect(chapters.map((c) => c.hasSpeech), [false, true, false]);
  });

  test('malformed OPF range order rejects navigational distortion', () {
    expect(() => buildEpubChapters(const DocumentContent(
      title: 'Bad', text: 'Some text',
      epubSpineRanges: [
        EpubSpineRange(idref: 'first', href: 'f.xhtml', start: 0, end: 5),
        EpubSpineRange(idref: 'overlap', href: 's.xhtml', start: 4, end: 9),
      ],
    ), const [SpeechSegment(0, 4, 'Some')]), throwsFormatException);
  });
}
