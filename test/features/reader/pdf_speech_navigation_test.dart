import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/dialogue_segmenter.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/features/reader/pdf_speech_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void _verifySourceOffsets(String source, List<SpeechSegment> segments) {
  var end = 0;
  for (final part in segments) {
    expect(part.start, greaterThanOrEqualTo(end));
    expect(part.end, greaterThan(part.start));
    expect(source.substring(part.start, part.end), part.text);
    end = part.end;
  }
}

void main() {
  test('PDF text pages never share a spoken TTS chunk', () {
    const first = 'A short first PDF page.';
    const second = 'A second physical page.';
    const source = '$first\n\n$second';
    const doc = DocumentContent(text: source, title: 'PDF',
      pdfPageRanges: [
        PdfPageRange(1, 0, first.length),
        PdfPageRange(2, first.length + 2, source.length),
      ],
    );
    final chunks = segmentPdfPages(doc);
    expect(chunks, hasLength(2));
    expect(chunks.map((e) => e.text), [first, second]);
    expect(chunks[0].end, first.length);
    expect(chunks[1].start, first.length + 2);
    expect(pdfSpeechQuoteResetOffsets(doc), [first.length + 2]);
    _verifySourceOffsets(source, chunks);
  });

  test('PDF quote groups reset at each page, including unmatched quotes', () {
    const first = '«An unfinished phrase.';
    const second = 'Narrator starts the next page.';
    const source = '$first\n\n$second';
    const doc = DocumentContent(text: source, title: 'Quotes',
      pdfPageRanges: [
        PdfPageRange(3, 0, first.length),
        PdfPageRange(5, first.length + 2, source.length),
      ],
    );
    final quoted = splitQuotedSegmentsWithRegions(
      segmentPdfPages(doc),
      resetAt: pdfSpeechQuoteResetOffsets(doc),
    );
    expect(quoted.any((part) => part.segment.text == second &&
        part.quoteGroup != null), isFalse);
    expect(quoted.last.segment.text, second);
    expect(quoted.last.quoteGroup, isNull);
    _verifySourceOffsets(source, [
      for (final part in quoted) part.segment,
    ]);
  });

  test('UTF-16 offsets stay page-exact across emoji and small chunks', () {
    const first = 'A 🐉 dragon. Two words.';
    const second = '😀 new page. Finale.';
    const source = '$first\n\n$second';
    const doc = DocumentContent(text: source, title: 'Unicode',
      pdfPageRanges: [
        PdfPageRange(1, 0, first.length),
        PdfPageRange(2, first.length + 2, source.length),
      ],
    );
    final chunks = segmentPdfPages(doc, maxChars: 16);
    expect(chunks, isNotEmpty);
    expect(chunks.every((part) =>
        part.end <= first.length || part.start >= first.length + 2), isTrue);
    _verifySourceOffsets(source, chunks);
  });

  test('omitted image-only PDF pages retain physical page provenance', () {
    const source = 'On page one.\n\nOn page five.';
    const doc = DocumentContent(text: source, title: 'Gap',
      pdfPageRanges: [
        PdfPageRange(1, 0, 12),
        PdfPageRange(5, 14, source.length),
      ],
    );
    final chunks = segmentPdfPages(doc);
    expect(chunks, hasLength(2));
    expect(doc.anchorAt(BookFormat.pdf, chunks[1].start).sourceId, '5');
    _verifySourceOffsets(source, chunks);
  });

  test('malformed pages and non-whitespace separator are rejected', () {
    expect(() => segmentPdfPages(const DocumentContent(
      text: 'One.XTwo.', title: 'Invalid',
      pdfPageRanges: [
        PdfPageRange(1, 0, 4),
        PdfPageRange(2, 5, 9),
      ],
    )), throwsFormatException);
    expect(() => segmentPdfPages(const DocumentContent(
      text: 'Some text', title: 'Overlap',
      pdfPageRanges: [
        PdfPageRange(1, 0, 5),
        PdfPageRange(2, 4, 9),
      ],
    )), throwsFormatException);
  });

  test('restoring completed source offset does not replay last clip', () {
    const chunks = [
      SpeechSegment(0, 6, 'First.'),
      SpeechSegment(8, 14, 'Second'),
      SpeechSegment(16, 22, 'Third.'),
    ];
    expect(speechResumeIndexForOffset(chunks, 0), 0);
    expect(speechResumeIndexForOffset(chunks, 6), 1);
    expect(speechResumeIndexForOffset(chunks, 7), 1);
    expect(speechResumeIndexForOffset(chunks, 20), 2);
    expect(speechResumeIndexForOffset(chunks, 22), 3);
    expect(speechResumeIndexForOffset(chunks, 40), 3);
    // Explicit TOC/bookmark navigation always gives a *real* clip to play.
    expect(speechSegmentIndexForOffset(chunks, 22), 2);
    expect(speechResumeIndexForOffset(const [], 0), -1);
  });
  test('PDF page end and final EOF round-trip through source anchors', () {
    const first = 'One page.';
    const second = 'Last page.';
    const source = '$first\n\n$second';
    const doc = DocumentContent(
      text: source,
      title: 'Page anchors',
      pdfPageRanges: [
        PdfPageRange(1, 0, first.length),
        PdfPageRange(2, first.length + 2, source.length),
      ],
    );
    final nextPageStart = first.length + 2;
    final next = doc.anchorAt(BookFormat.pdf, nextPageStart);
    expect(next.sourceId, '2');
    expect(next.localOffset, 0);
    expect(doc.offsetOf(next), nextPageStart);
    final finished = doc.anchorAt(BookFormat.pdf, source.length);
    expect(finished.sourceId, '2');
    expect(finished.localOffset, second.length);
    expect(doc.offsetOf(finished), source.length);
    final segments = segmentPdfPages(doc);
    expect(speechResumeIndexForOffset(segments, source.length),
        segments.length);
  });

}
