import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../domain/book.dart';

/// A self-contained, private export, NOT an automatic cloud backup.
///
/// EReader copies exact book bytes plus a consistent standalone SQLite
/// snapshot (including bookmarks, reading positions, cast/voice settings),
/// leaving native OS credential-vault secrets outside the archive.
/// A separate restore flow is required on a new device because the snapshot
/// contains original device paths. Never overwrite a running SQLite store.
class LibraryBackupResult {
  const LibraryBackupResult({
    required this.directory,
    required this.bookCount,
    required this.bookBytes,
  });
  final Directory directory;
  final int bookCount;
  final int bookBytes;
}

typedef LibrarySnapshotWriter = void Function(String destination);

/// Pure filesystem/database routine, independent of Flutter and file_picker.
/// On any error staged output is removed and no finished export appears.
///
/// Source identity is SHA-256 of the *complete* book, as already used by
/// LibraryStore. Never back up arbitrary paths from a legacy JSON database.
Future<LibraryBackupResult> exportPortableLibraryBackup({
  required Directory sourceHome,
  required Directory destinationParent,
  required List<BookRecord> books,
  required LibrarySnapshotWriter writeSqliteSnapshot,
  void Function(int done, int total)? onProgress,
  int maxBooks = 10000,
  int maxTotalBytes = 20 * 1024 * 1024 * 1024,
}) async {
  if (maxBooks < 1 || maxBooks > 10000 ||
      maxTotalBytes < 1 || maxTotalBytes > 20 * 1024 * 1024 * 1024) {
    throw ArgumentError('Invalid backup capacity limits');
  }
  if (books.length > maxBooks) {
    throw const FormatException('Too many books in library backup');
  }

  final home = p.normalize(p.absolute(sourceHome.path));
  final destination = p.normalize(p.absolute(destinationParent.path));
  if (home == destination || p.isWithin(home, destination)) {
    throw const FormatException('Backup cannot be saved inside app storage');
  }
  if (await FileSystemEntity.type(destination, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FormatException('Choose an existing non-symlink folder');
  }

  // Preflight every source before writing a single output file.
  final sources = <({BookRecord book, File file, int length})>[];
  final seen = <String>{};
  var bytes = 0;
  for (final book in books) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(book.id) ||
        !seen.add(book.id)) {
      throw const FormatException('Invalid or duplicate library book ID');
    }
    final expectedPath = p.join(home, 'books',
        '${book.id}.${book.format.extension}');
    final actual = p.normalize(p.absolute(book.localPath));
    if (actual != expectedPath ||
        !p.isWithin(p.join(home, 'books'), actual)) {
      throw const FormatException('Book source is outside managed storage');
    }
    if (await FileSystemEntity.type(actual, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('A managed book is missing or not a file');
    }
    final file = File(actual);
    final length = await file.length();
    if (length <= 0 || length > 100 * 1024 * 1024 ||
        bytes > maxTotalBytes - length) {
      throw const FormatException('Book exceeds backup size budget');
    }
    bytes += length;
    sources.add((book: book, file: file, length: length));
  }

  // A private temporary sibling is renamed only after SQLite and EVERY
  // book digest pass. Incomplete backups never look like finished exports.
  final staging = await destinationParent.createTemp('.ereader-backup-');
  try {
    final copied = Directory(p.join(staging.path, 'books'));
    await copied.create();

    final databaseSnapshot = File(p.join(staging.path, 'library.sqlite'));
    writeSqliteSnapshot(databaseSnapshot.path);
    if (await FileSystemEntity.type(
        databaseSnapshot.path, followLinks: false) !=
        FileSystemEntityType.file ||
        await databaseSnapshot.length() < 4096) {
      throw const FormatException('SQLite backup snapshot is incomplete');
    }
    // VACUUM INTO produces a WAL-free, standalone SQLite database.
    // Confirm it opens and includes exactly the expected book identities.
    final check = sqlite3.open(databaseSnapshot.path);
    try {
      final status = check.select('PRAGMA integrity_check').first['integrity_check'];
      if (status != 'ok') {
        throw const FormatException('SQLite backup failed integrity check');
      }
      final ids = check.select('SELECT id FROM books')
          .map((r) => r['id'] as String).toSet();
      if (ids.length != seen.length || !ids.containsAll(seen)) {
        throw const FormatException('SQLite snapshot book list differs');
      }
    } finally {
      check.dispose();
    }

    final catalog = <Map<String, Object?>>[];
    var completed = 0;
    for (final entry in sources) {
      final book = entry.book;
      final name = '${book.id}.${book.format.extension}';
      final copy = File(p.join(copied.path, name));
      await entry.file.copy(copy.path);
      if (await copy.length() != entry.length) {
        throw const FormatException('Book changed during library backup');
      }
      final digest = (await sha256.bind(copy.openRead()).first).toString();
      if (digest != book.id) {
        throw const FormatException('Source book checksum did not match');
      }
      catalog.add({
        'sha256': book.id,
        'file': 'books/$name',
        'format': book.format.name,
        'title': book.title,
        if (book.author != null) 'author': book.author,
        if (book.series != null) 'series': book.series,
        if (book.language != null) 'language': book.language,
        'progressOffset': book.progressOffset,
        'favorite': book.isFavorite,
        if (book.progressAnchor != null)
          'progressAnchor': book.progressAnchor!.toJson(),
      });
      completed++;
      onProgress?.call(completed, books.length);
    }

    await File(p.join(staging.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'type': 'ereader-library-backup',
        'version': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'bookCount': books.length,
        'totalBookBytes': bytes,
        'books': catalog,
        'containsLibraryPreferencesAndAnnotations': true,
        'containsNativeCredentialVaultSecrets': false,
        'restoreRequiresPathRelinking': true,
      }), flush: true,
    );

    final suffix = p.basename(staging.path)
        .replaceFirst('.ereader-backup-', '');
    final folder = Directory(p.join(destination, 'EReader-backup-$suffix'));
    if (await folder.exists()) {
      throw const FileSystemException('Backup folder already exists');
    }
    final finished = await staging.rename(folder.path);
    return LibraryBackupResult(
      directory: finished, bookCount: books.length, bookBytes: bytes);
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
