import 'package:ereader/domain/book_bookmark.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts source-anchored bookmarked positions', () {
    const bookmark = BookBookmark(
      id: 'id-1',
      bookId: 'book-hash',
      title: 'Arrival at castle',
      globalOffset: 120,
      createdAt: DateTime.utc(2026, 10, 22),
      anchor: ReadingAnchor(
        kind: AnchorKind.epubSpine,
        sourceId: 'chapter-5',
        localOffset: 23,
      ),
    );
    expect(() => bookmark.validate(), returnsNormally);
    expect(bookmark.anchor!.sourceId, 'chapter-5');
  });

  test('rejects unsafe or empty bookmark metadata', () {
    final invalid = BookBookmark(
      id: 'b',
      bookId: 'book-hash',
      title: '',
      globalOffset: -1,
      createdAt: DateTime.utc(2026, 10, 22),
    );
    expect(() => invalid.validate(), throwsFormatException);
  });
}
