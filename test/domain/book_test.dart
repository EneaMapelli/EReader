import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/reading_anchor.dart';

void main() {
  test('book JSON retains reading position', () {
    final book = BookRecord(
      id: '123',
      title: 'Il libro',
      localPath: '/tmp/book.epub',
      format: BookFormat.epub,
      importedAt: DateTime.utc(2026, 10, 22),
      progressOffset: 123,
    );
    final restored = BookRecord.fromJson(book.toJson());
    expect(restored.progressOffset, 123);
    expect(restored.format, BookFormat.epub);
    expect(restored.atOffset(456).progressOffset, 456);
  });

  test('book JSON saves source anchor and migrates old records', () {
    final original = BookRecord(
      id: 'book-id',
      title: 'Title',
      localPath: '/tmp/book.epub',
      format: BookFormat.epub,
      importedAt: DateTime.utc(2026, 10, 22),
      progressOffset: 1234,
      progressAnchor: const ReadingAnchor(
        kind: AnchorKind.epubSpine,
        sourceId: 'chapter-2',
        localOffset: 18,
      ),
    );
    final restored = BookRecord.fromJson(original.toJson());
    expect(restored.progressOffset, 1234);
    expect(restored.progressAnchor!.sourceId, 'chapter-2');
    expect(restored.progressAnchor!.localOffset, 18);

    final legacy = Map<String, dynamic>.from(original.toJson())
      ..remove('progressAnchor');
    final oldRestored = BookRecord.fromJson(legacy);
    expect(oldRestored.progressOffset, 1234);
    expect(oldRestored.progressAnchor, isNull);
  });

  test('file format detects case insensitive supported extension', () {
    expect(BookFormatPath.parse('A.EPUB'), BookFormat.epub);
    expect(BookFormatPath.parse('A.pdf'), BookFormat.pdf);
    expect(BookFormatPath.parse('A.mobi'), isNull);
  });
}
