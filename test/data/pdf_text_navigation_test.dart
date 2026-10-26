import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/pdf_text_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spans = [
    PdfPageRange(1, 0, 120),
    PdfPageRange(3, 122, 200), // Physical page 2 has no selectable text.
    PdfPageRange(6, 202, 300),
  ];

  test('visible physical page maps to nearest readable forward page', () {
    expect(pdfTextOffsetForVisualPage(spans, 1), 0);
    expect(pdfTextOffsetForVisualPage(spans, 2), 122);
    expect(pdfTextOffsetForVisualPage(spans, 3), 122);
    expect(pdfTextOffsetForVisualPage(spans, 4), 202);
    expect(pdfTextOffsetForVisualPage(spans, 7), 202);
    expect(pdfTextOffsetForVisualPage(spans, 0), isNull);
    expect(pdfTextOffsetForVisualPage([], 1), isNull);
  });

  test('spoken text offsets map back to real physical source pages', () {
    expect(pdfVisualPageForTextOffset(spans, 0), 1);
    expect(pdfVisualPageForTextOffset(spans, 119), 1);
    expect(pdfVisualPageForTextOffset(spans, 120), 3);
    expect(pdfVisualPageForTextOffset(spans, 122), 3);
    expect(pdfVisualPageForTextOffset(spans, 199), 3);
    expect(pdfVisualPageForTextOffset(spans, 300), 6);
    expect(pdfVisualPageForTextOffset(spans, -1), isNull);
    expect(pdfVisualPageForTextOffset([], 5), isNull);
  });

  test('text-less spans never invent PDF reading or OCR offsets', () {
    const empty = [
      PdfPageRange(1, 0, 0),
      PdfPageRange(2, 2, 2),
    ];
    expect(pdfTextOffsetForVisualPage(empty, 1), isNull);
    expect(pdfTextOffsetForVisualPage(empty, 2), isNull);
  });
}
