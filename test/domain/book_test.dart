import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/domain/book.dart';

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

  test('file format detects case insensitive supported extension', () {
    expect(BookFormatPath.parse('A.EPUB'), BookFormat.epub);
    expect(BookFormatPath.parse('A.pdf'), BookFormat.pdf);
    expect(BookFormatPath.parse('A.mobi'), isNull);
  });
}
