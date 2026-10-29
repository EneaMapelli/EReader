import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../domain/book.dart';
import '../domain/book_collection.dart';
import '../domain/book_bookmark.dart';
import '../domain/pdf_visual_bookmark.dart';
import '../domain/reading_anchor.dart';

/// Source file paths in backup SQLite are untrusted and NEVER used for
/// filesystem access. Preview always validates all bytes and identifiers.
class VerifiedBackupBook {
  const VerifiedBackupBook({
    required this.id,
    required this.format,
    required this.file,
    required this.title,
    required this.importedAt,
    required this.progressOffset,
    required this.bookmarks,
    this.pdfVisualBookmarks = const [],
    this.anchor,
    this.author,
    this.series,
    this.language,
    this.pdfVisualPage,
    this.isFavorite = false,
    this.readingStatus = BookReadingStatus.toRead,
    this.collectionNames = const [],
  });
  final String id;
  final BookFormat format;
  final File file;
  final String title;
  final DateTime importedAt;
  final int progressOffset;
  final ReadingAnchor? anchor;
  final String? author;
  final String? series;
  final String? language;
  final int? pdfVisualPage;
  final bool isFavorite;
  final BookReadingStatus readingStatus;
  final List<String> collectionNames;
  final List<BookBookmark> bookmarks;
  final List<PdfVisualBookmark> pdfVisualBookmarks;
}

class VerifiedLibraryBackup {
  const VerifiedLibraryBackup({required this.books, required this.totalBookBytes,
    this.collectionCatalog = const []});
  final List<VerifiedBackupBook> books;
  final int totalBookBytes;
  final List<String> collectionCatalog;
}

class LibraryRestorePreview {
  const LibraryRestorePreview({
    required this.total,
    required this.availableToImport,
    required this.alreadyPresent,
    required this.bookmarksToImport,
    required this.verifiedBytes,
    this.collectionsToImport = 0,
  });

  final int total;
  final int availableToImport;
  final int alreadyPresent;
  final int bookmarksToImport;
  final int verifiedBytes;
  final int collectionsToImport;
}

class LibraryRestoreResult {
  const LibraryRestoreResult({
    required this.added,
    required this.skipped,
    required this.bookmarksImported,
    this.collectionsImported = 0,
  });

  final int added;
  final int skipped;
  final int bookmarksImported;
  final int collectionsImported;
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
    final schemaVersion =
        database.select('PRAGMA user_version').first['user_version'];
    // New exports use v22. Older v17-v21 snapshots remain readable;
    // collections default to absent if the join table does not exist.
    if (integrity != 'ok' || schemaVersion is! int ||
        schemaVersion < 17 || schemaVersion > 22) {
      throw const FormatException('Unsupported or damaged backup database');
    }
    final source = database.select(
      'SELECT id, title, format, imported_at, progress_offset, progress_anchor, '
      'author, series, language, pdf_visual_page'
      '${schemaVersion >= 20 ? ', is_favorite' : ''}'
      '${schemaVersion >= 21 ? ', reading_status' : ''} FROM books',
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

    // Version 19 adds source-independent physical PDF bookmarks.
    // Older v17/v18 snapshots do not have this table; they are still
    // perfectly valid portable backups. Always validate ALL rows before
    // publishing the restore preview.
    final savedVisualBookmarks = <String, List<PdfVisualBookmark>>{};
    if (schemaVersion >= 19) {
      final visualRows = database.select(
        'SELECT id, book_id, title, page_number, created_at '
        'FROM pdf_visual_bookmarks',
      );
      if (visualRows.length > 1000000) {
        throw const FormatException('Too many PDF page bookmarks');
      }
      for (final row in visualRows) {
        final bookId = row['book_id'] as String;
        final parent = rows[bookId];
        if (parent == null || parent['format'] != 'pdf') {
          throw const FormatException('Orphan/non-PDF visual bookmark');
        }
        final bookmark = PdfVisualBookmark(
          id: row['id'] as String,
          bookId: bookId,
          title: row['title'] as String,
          pageNumber: row['page_number'] as int,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
        bookmark.validate();
        savedVisualBookmarks.putIfAbsent(bookId, () => []).add(bookmark);
      }
    }

    // All collection rows and memberships are checked, even for existing
    // books that the user will choose not to re-import. This prevents a
    // corrupt or malicious backup from smuggling unverified catalog state.
    final backedCollections = <String, List<String>>{};
    final collectionCatalog = <String>[];
    if (schemaVersion >= 22) {
      final collections = database.select(
        'SELECT id, name, created_at FROM book_collections',
      );
      if (collections.length > 1000) {
        throw const FormatException('Too many backed-up collections');
      }
      final namesById = <String, String>{};
      final uniqueNames = <String>{};
      for (final row in collections) {
        final id = row['id'] as String;
        final name = row['name'] as String;
        final createdAt = DateTime.parse(row['created_at'] as String);
        final item = BookCollection(
          id: id, name: name, createdAt: createdAt);
        item.validate();
        if (!uniqueNames.add(name.toLowerCase())) {
          throw const FormatException('Duplicate backup collection names');
        }
        namesById[id] = name;
        collectionCatalog.add(name);
      }
      final members = database.select(
        'SELECT collection_id, book_id FROM book_collection_members',
      );
      if (members.length > 200000) {
        throw const FormatException('Too many backed-up memberships');
      }
      final seenPairs = <String>{};
      for (final row in members) {
        final cid = row['collection_id'] as String;
        final bid = row['book_id'] as String;
        final name = namesById[cid];
        if (name == null || !rows.containsKey(bid) ||
            !seenPairs.add('$cid:$bid')) {
          throw const FormatException('Orphan/duplicate collection membership');
        }
        backedCollections.putIfAbsent(bid, () => []).add(name);
      }
    }

    if (schemaVersion >= 22) {
      final declaredCatalog = decoded['collectionCatalog'];
      if (declaredCatalog is! List ||
          declaredCatalog.length != collectionCatalog.length ||
          declaredCatalog.any((entry) => entry is! String) ||
          declaredCatalog.toSet().length != declaredCatalog.length ||
          !declaredCatalog.toSet().containsAll(collectionCatalog)) {
        throw const FormatException('Backup collection catalog mismatch');
      }
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
      // The manifest and the snapshot are independently serialized.
      // A modified SQLite metadata/progress row cannot silently override
      // the backup catalog presented to the user during preview.
      for (final field in const ['author', 'series', 'language']) {
        if (raw[field] != row[field]) {
          throw const FormatException('Backup metadata mismatch');
        }
      }
      // A v20 manifest must agree with its independently snapshotted
      // SQLite favorite flag; do not silently trust tampered metadata.
      final favorite = schemaVersion >= 20
          ? row['is_favorite'] : 0;
      if (favorite is! int || (favorite != 0 && favorite != 1) ||
          (schemaVersion >= 20 && raw['favorite'] != (favorite == 1))) {
        throw const FormatException('Backup favorite metadata mismatch');
      }
      // A manually selected shelf is verified independently in the
      // manifest and SQLite. Legacy snapshots default to 'toRead'.
      final shelf = schemaVersion >= 21
          ? row['reading_status'] : BookReadingStatus.toRead.name;
      if (shelf is! String ||
          !BookReadingStatus.values.any((value) => value.name == shelf) ||
          (schemaVersion >= 21 && raw['readingStatus'] != shelf)) {
        throw const FormatException('Backup reading shelf mismatch');
      }
      final expectedCollections = backedCollections[id] ?? const <String>[];
      if (schemaVersion >= 22) {
        final declared = raw['collections'];
        if (declared is! List || declared.length != expectedCollections.length ||
            declared.any((value) => value is! String) ||
            declared.toSet().length != declared.length ||
            !declared.toSet().containsAll(expectedCollections)) {
          throw const FormatException('Backup collections mismatch');
        }
      }
      if (raw['progressOffset'] != row['progress_offset']) {
        throw const FormatException('Backup source progress mismatch');
      }
      final savedAnchor = _decodeAnchor(row['progress_anchor']);
      final declaredAnchor = raw['progressAnchor'];
      if ((savedAnchor == null) != (declaredAnchor == null) ||
          (savedAnchor != null &&
              jsonEncode(savedAnchor.toJson()) !=
                  jsonEncode(declaredAnchor))) {
        throw const FormatException('Backup reading anchor mismatch');
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
        importedAt: DateTime.parse(row['imported_at'] as String),
        author: _safeMetadata(row['author'], 160),
        series: _safeMetadata(row['series'], 160),
        language: _safeMetadata(row['language'], 24),
        progressOffset: progress,
        anchor: savedAnchor,
        pdfVisualPage: page is int ? page : null,
        isFavorite: favorite == 1,
        readingStatus: BookReadingStatus.values.byName(shelf),
        collectionNames: List<String>.unmodifiable(expectedCollections),
        bookmarks: List<BookBookmark>.unmodifiable(
            savedBookmarks[id] ?? const []),
        pdfVisualBookmarks: List<PdfVisualBookmark>.unmodifiable(
            savedVisualBookmarks[id] ?? const []),
      ));
      onProgress?.call(result.length, count);
    }
    if (bytes != declaredBytes || seen.length != rows.length) {
      throw const FormatException('Backup bytes or book count mismatch');
    }
    return VerifiedLibraryBackup(
      books: List<VerifiedBackupBook>.unmodifiable(result),
      totalBookBytes: bytes,
      collectionCatalog: List<String>.unmodifiable(collectionCatalog),
    );
  } finally {
    database.dispose();
  }
}
