import 'book.dart';

/// In-memory catalog-only search; it never reads or indexes the contents of
/// private EPUB/PDF/TXT files and never modifies stored metadata.
///
/// Terms are combined with AND. An unqualified term may match title, author
/// or series; title:, author: and series: restrict the field. Double quotes
/// group a contiguous phrase. The raw query is bounded to keep filtering a
/// large library predictable and to avoid accidental unbounded allocations.
enum LibrarySearchField { any, title, author, series }

class LibrarySearchTerm {
  const LibrarySearchTerm({required this.field, required this.value});

  final LibrarySearchField field;
  final String value;

  bool matches(BookRecord book) {
    bool contains(String? fieldValue) =>
        fieldValue?.toLowerCase().contains(value) ?? false;
    return switch (field) {
      LibrarySearchField.any =>
        contains(book.title) || contains(book.author) || contains(book.series),
      LibrarySearchField.title => contains(book.title),
      LibrarySearchField.author => contains(book.author),
      LibrarySearchField.series => contains(book.series),
    };
  }
}

class LibrarySearchQuery {
  const LibrarySearchQuery._(this.terms, this.error);

  static const int maxLength = 256;
  static const int maxTerms = 16;

  final List<LibrarySearchTerm> terms;
  final String? error;
  bool get isValid => error == null;

  bool matches(BookRecord book) =>
      isValid && terms.every((term) => term.matches(book));

  static LibrarySearchQuery parse(String raw) {
    if (raw.length > maxLength) {
      return const LibrarySearchQuery._(
          [], 'Search must be 256 characters or fewer');
    }

    final terms = <LibrarySearchTerm>[];
    var offset = 0;

    bool isSpace(int code) =>
        code == 0x20 || code == 0x09 || code == 0x0A ||
        code == 0x0D || code == 0xA0;

    while (offset < raw.length) {
      while (offset < raw.length && isSpace(raw.codeUnitAt(offset))) {
        offset++;
      }
      if (offset == raw.length) break;
      if (terms.length >= maxTerms) {
        return const LibrarySearchQuery._(
            [], 'Search supports at most 16 terms');
      }

      var field = LibrarySearchField.any;
      final remaining = raw.substring(offset).toLowerCase();
      for (final candidate in <(String, LibrarySearchField)>[
        ('title:', LibrarySearchField.title),
        ('author:', LibrarySearchField.author),
        ('series:', LibrarySearchField.series),
      ]) {
        if (remaining.startsWith(candidate.$1)) {
          field = candidate.$2;
          offset += candidate.$1.length;
          break;
        }
      }
      if (offset >= raw.length || isSpace(raw.codeUnitAt(offset))) {
        return const LibrarySearchQuery._(
            [], 'Enter text after a search field');
      }

      final word = StringBuffer();
      if (raw.codeUnitAt(offset) == 0x22) {
        offset++;
        while (offset < raw.length && raw.codeUnitAt(offset) != 0x22) {
          word.writeCharCode(raw.codeUnitAt(offset++));
        }
        if (offset == raw.length) {
          return const LibrarySearchQuery._(
              [], 'Close the quoted search phrase');
        }
        offset++; // Closing quote.
        if (offset < raw.length && !isSpace(raw.codeUnitAt(offset))) {
          return const LibrarySearchQuery._(
              [], 'Separate search terms with a space');
        }
      } else {
        while (offset < raw.length && !isSpace(raw.codeUnitAt(offset))) {
          word.writeCharCode(raw.codeUnitAt(offset++));
        }
      }
      final value = word.toString().trim().toLowerCase();
      if (value.isEmpty) {
        return const LibrarySearchQuery._(
            [], 'Search terms cannot be empty');
      }
      terms.add(LibrarySearchTerm(field: field, value: value));
    }
    return LibrarySearchQuery._(
      List<LibrarySearchTerm>.unmodifiable(terms), null,
    );
  }
}
