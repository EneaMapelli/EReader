import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../domain/book.dart';
import '../domain/book_bookmark.dart';
import '../domain/reading_anchor.dart';

/// Source file paths in backup SQLite are untrusted and NEVER used for
/// filesystem access. Preview always validates all bytes and identifiers.
class VerifiedBackupBook {
  const VerifiedBackupBook({
    required this.id,
    required this.format,
    required this.file,
    required this.title,
    required this.progressOffset,
    required this.bookmarks,
    this.anchor,
    this.author,
    this.series,
    this.language,
    this.pdfVisualPage,
  });
  final String id;
  final BookFormat format;
  final File file;
  final String title;
  final int progressOffset;
  final ReadingAnchor? anchor;
  final String? author;
  final String? series;
  final String? language;
  final int? pdfVisualPage;
  final List<BookBookmark> bookmarks;
}

class VerifiedLibraryBackup {
  const VerifiedLibraryBackup({required this.books, required this.totalBookBytes});
  final List<VerifiedBackupBook> books;
  final int totalBookBytes;
}

String? _safeMetadata(Object? value, int maxLength) {
  if (value == null) return null;
  if (value is! String || value.length > maxLength ||
      value.runes.any((r) => r < 32 || r == 127)) {
    throw const FormatException('Malformed backed-up metadata');
  }
  return value.isEmpty ? null : value;
}

ReadingAnchor? _decodeAnchor(Object? value) {
  if (value == null) return null;
  if (value is! String || value.length > 4096) {
    throw const FormatException('Malformed backup reading anchor');
  }
  final json = jsonDecode(value);
  if (json is! Map) {
    throw const FormatException('Malformed backup reading anchor');
  }
  return ReadingAnchor.fromJson(Map<String, dynamic>.from(json));
}

/// Verify the whole local backup (not just the books that will be restored).
/// No arbitrary path, symlink, oversized source, consent or executable is used.
/// This operation is read-only and can be shown before restoration confirmation.
Future<VerifiedLibraryBackup> inspectLibraryBackup(
  Directory backup, {
  void Function(int done, int total)? onProgress,
}) async {
  final root = p.normalize(p.absolute(backup.path));
  final booksDir = Directory(p.join(root, 'books'));
  final manifest = File(p.join(root, 'manifest.json'));
  final snapshotFile = File(p.join(root, 'library.sqlite'));
  if (await FileSystemEntity.type(root, followLinks: false) !=
          FileSystemEntityType.directory ||
      await FileSystemEntity.type(booksDir.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      await FileSystemEntity.type(manifest.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await FileSystemEntity.type(snapshotFile.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await manifest.length() > 8 * 1024 * 1024 ||
      await snapshotFile.length() > 1024 * 1024 * 1024) {
    throw const FormatException('Not a supported private EReader backup');
  }

  final decoded = jsonDecode(await manifest.readAsString());
  if (decoded is! Map ||
      decoded['type'] != 'ereader-library-backup' ||
      decoded['version'] != 1 ||
      decoded['restoreRequiresPathRelinking'] != true ||
      decoded['containsNativeCredentialVaultSecrets'] != false) {
    throw const FormatException('Unsupported library backup manifest');
  }
  final rawBooks = decoded['books'];
  final count = decoded['bookCount'];
  final declaredBytes = decoded['totalBookBytes'];
  if (rawBooks is! List || count is! int ||
      count < 0 || count > 10000 || rawBooks.length != count ||
      declaredBytes is! int || declaredBytes < 0 ||
      declaredBytes > 20 * 1024 * 1024 * 1024) {
    throw const FormatException('Invalid library backup limits/counts');
  }

  // Backup snapshots are never attached to the active store. Avoid its
  // absolute local_path values even when a bookmark/manifest names one.
  final database = sqlite3.open(snapshotFile.path);
  try {
    final integrity = database.select('PRAGMA integrity_check')
        .first['integrity_check'];
    if (integrity != 'ok' ||
        database.select('PRAGMA user_version').first['user_version'] != 17) {
      throw const FormatException('Unsupported or damaged backup database');
    }
    final source = database.select(
      'SELECT id, title, format, progress_offset, progress_anchor, '
      'author, series, language, pdf_visual_page FROM books',
    );
    if (source.length != count) {
      throw const FormatException('Backup SQLite book count mismatch');
    }
    final rows = {for (final row in source) row['id'] as String: row};
    if (rows.length != count) {
      throw const FormatException('Duplicate backup book ID');
    }
    final savedBookmarks = <String, List<BookBookmark>>{};
    final bookmarkRows = database.select(
      'SELECT id, book_id, title, global_offset, created_at, '
      'anchor_json FROM bookmarks',
    );
    if (bookmarkRows.length > 1000000) {
      throw const FormatException('Too many backup bookmarks');
    }
    for (final row in bookmarkRows) {
      final bookId = row['book_id'] as String;
      if (!rows.containsKey(bookId)) {
        throw const FormatException('Orphan backup bookmark');
      }
      final bookmark = BookBookmark(
        id: row['id'] as String,
        bookId: bookId,
        title: row['title'] as String,
        globalOffset: row['global_offset'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
        anchor: _decodeAnchor(row['anchor_json']),
      );
      bookmark.validate();
      savedBookmarks.putIfAbsent(bookId, () => []).add(bookmark);
    }

    final seen = <String>{};
    final result = <VerifiedBackupBook>[];
    var bytes = 0;
    for (final raw in rawBooks) {
      if (raw is! Map || raw['sha256'] is! String ||
          raw['format'] is! String || raw['file'] is! String) {
        throw const FormatException('Malformed backed-up book');
      }
      final id = raw['sha256'] as String;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id) || !seen.add(id)) {
        throw const FormatException('Unsafe or duplicate backup book ID');
      }
      final formats = BookFormat.values.where(
          (format) => format.name == raw['format']);
      if (formats.length != 1) {
        throw const FormatException('Invalid backup book format');
      }
      final format = formats.single;
      if (raw['file'] != 'books/$id.${format.extension}') {
        throw const FormatException('Unsafe backup file path');
      }
      final row = rows[id];
      if (row == null || row['format'] != format.name ||
          row['title'] != raw['title']) {
        throw const FormatException('Manifest/book database mismatch');
      }
      final file = File(p.join(booksDir.path, '$id.${format.extension}'));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Missing or symlinked backup book');
      }
      final length = await file.length();
      if (length == 0 || length > 100 * 1024 * 1024 ||
          bytes > 20 * 1024 * 1024 * 1024 - length) {
        throw const FormatException('Oversized backed-up book');
      }
      bytes += length;
      if ((await sha256.bind(file.openRead()).first).toString() != id) {
        throw const FormatException('Backup file checksum mismatch');
      }
      final title = _safeMetadata(row['title'], 160);
      if (title == null || title.trim().isEmpty) {
        throw const FormatException('Invalid book title');
      }
      final progress = row['progress_offset'];
      final page = row['pdf_visual_page'];
      if (progress is! int || progress < 0 ||
          (page != null && (page is! int || page < 1 || page > 100000))) {
        throw const FormatException('Invalid backup reading progress');
      }
      result.add(VerifiedBackupBook(
        id: id, format: format, file: file, title: title,
        author: _safeMetadata(row['author'], 160),
        series: _safeMetadata(row['series'], 160),
        language: _safeMetadata(row['language'], 24),
        progressOffset: progress,
        anchor: _decodeAnchor(row['progress_anchor']),
        pdfVisualPage: page is int ? page : null,
        bookmarks: List<BookBookmark>.unmodifiable(
            savedBookmarks[id] ?? const []),
      ));
      onProgress?.call(result.length, count);
    }
    if (bytes != declaredBytes || seen.length != rows.length) {
      throw const FormatException('Backup bytes or book count mismatch');
    }
    return VerifiedLibraryBackup(
      books: List<VerifiedBackupBook>.unmodifiable(result),
      totalBookBytes: bytes,
    );
  } finally {
    database.dispose();
  }
}
