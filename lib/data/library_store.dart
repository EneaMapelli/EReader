import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/book.dart';
import '../domain/reading_anchor.dart';

/// Local, transactional Windows/Android library. Inject homeDirectory in tests.
class LibraryStore {
  LibraryStore({Directory? homeDirectory}) : _configuredHome = homeDirectory;
  final Directory? _configuredHome;
  Directory? _home;
  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('LibraryStore not initialized');
    return db;
  }

  Directory get _booksDir => Directory(p.join(_home!.path, 'books'));

  Future<void> initialize() async {
    if (_db != null) return;
    final support = _configuredHome ??
        Directory(p.join((await getApplicationSupportDirectory()).path, 'ereader'));
    _home = support;
    await support.create(recursive: true);
    await _booksDir.create(recursive: true);
    final db = sqlite3.open(p.join(support.path, 'library.sqlite'));
    try {
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA foreign_keys = ON');
      final version = db.select('PRAGMA user_version').first['user_version'] as int;
      if (version > 2) {
        throw StateError('Library created by a newer EReader version');
      }
      if (version < 1) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS books (
              id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              local_path TEXT NOT NULL,
              format TEXT NOT NULL,
              imported_at TEXT NOT NULL,
              progress_offset INTEGER NOT NULL DEFAULT 0
                CHECK(progress_offset >= 0),
              progress_anchor TEXT
            )
          ''');
          db.execute('PRAGMA user_version = 2');
        });
      }
      if (version == 1) {
        _transaction(db, () {
          db.execute('ALTER TABLE books ADD COLUMN progress_anchor TEXT');
          db.execute('PRAGMA user_version = 2');
        });
      }
      await _migrateLegacyJson(db, support);
      _db = db;
    } catch (_) {
      db.dispose();
      _home = null;
      rethrow;
    }
  }

  /// Import the old JSON library atomically; archive it only after COMMIT.
  /// If archiving fails, repeat startup safely with INSERT OR IGNORE.
  Future<void> _migrateLegacyJson(Database db, Directory home) async {
    final legacy = File(p.join(home.path, 'library.json'));
    if (!await legacy.exists()) return;
    final contents = jsonDecode(await legacy.readAsString());
    if (contents is! List) {
      throw const FormatException('Legacy library must contain a JSON array');
    }
    final records = contents.map((item) =>
        BookRecord.fromJson(Map<String, dynamic>.from(item as Map))).toList();

    _transaction(db, () {
      for (final book in records) {
        if (!_isManagedPath(book.localPath)) continue;
        _insert(db, book, ignoreDuplicates: true);
      }
    });

    final archived = File(p.join(home.path, 'library.migrated.json'));
    try {
      if (!await archived.exists()) {
        await legacy.rename(archived.path);
      } else {
        await legacy.delete();
      }
    } on FileSystemException {
      // Keep the original; idempotent migration can be retried.
    }
  }

  List<BookRecord> get books => _database
      .select('SELECT * FROM books ORDER BY imported_at DESC, title COLLATE NOCASE')
      .map(_fromRow)
      .toList();

  BookRecord? getBook(String id) {
    final rows = _database.select('SELECT * FROM books WHERE id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<BookRecord> importFile(String sourcePath, {String? originalName}) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw const FormatException('Source does not exist');
    final displayName = originalName ?? p.basename(sourcePath);
    final format = BookFormatPath.parse(displayName);
    if (format == null) throw const FormatException('Unsupported extension');
    final length = await source.length();
    if (length == 0 || length > 100 * 1024 * 1024) {
      throw const FormatException('Book must be 1 byte to 100 MB');
    }

    final bytes = await source.readAsBytes();
    _validateSignature(bytes, format);
    final id = sha256.convert(bytes).toString();
    final existing = getBook(id);
    if (existing != null && await File(existing.localPath).exists()) {
      // A duplicate import should preserve reading progress and metadata.
      return existing;
    }

    final target = File(
        p.join(_booksDir.path, id + '.' + format.extension));
    if (!_isManagedPath(target.path)) {
      throw StateError('Unsafe book destination path');
    }
    final temporary = File(target.path + '.part');
    try {
      if (await target.exists()) {
        // A previous process may have written the file but crashed before
        // committing its SQLite entry. Validate before adopting it.
        final foundHash = sha256.convert(await target.readAsBytes()).toString();
        if (foundHash != id) {
          throw const FormatException('Managed book file is corrupted');
        }
      } else {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(target.path);
      }

      if (existing != null) {
        // Recover a previously imported book whose private file went missing,
        // while preserving its progress and user-visible title.
        _transaction(_database, () {
          _database.execute('UPDATE books SET local_path = ? WHERE id = ?',
              [target.path, id]);
        });
        return getBook(id)!;
      }

      final record = BookRecord(
        id: id,
        title: p.basenameWithoutExtension(displayName),
        localPath: target.path,
        format: format,
        importedAt: DateTime.now().toUtc(),
      );
      _transaction(_database, () => _insert(_database, record));
      return record;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> savePosition(String bookId, int offset,
      {ReadingAnchor? anchor}) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    _database.execute(
        'UPDATE books SET progress_offset = ?, progress_anchor = ? WHERE id = ?',
        [offset, anchor == null ? null : jsonEncode(anchor.toJson()), bookId]);
  }

  Future<void> removeBook(String bookId) async {
    final book = getBook(bookId);
    if (book == null) return;
    _transaction(_database, () {
      _database.execute('DELETE FROM books WHERE id = ?', [bookId]);
    });
    if (_isManagedPath(book.localPath)) {
      final file = File(book.localPath);
      if (await file.exists()) await file.delete();
    }
  }

  bool _isManagedPath(String path) =>
      _home != null && p.isWithin(_booksDir.absolute.path, p.absolute(path));

  void dispose() {
    _db?.dispose();
    _db = null;
  }

  static BookRecord _fromRow(Row row) => BookRecord(
        id: row['id'] as String,
        title: row['title'] as String,
        localPath: row['local_path'] as String,
        format: BookFormat.values.byName(row['format'] as String),
        importedAt: DateTime.parse(row['imported_at'] as String),
        progressOffset: row['progress_offset'] as int,
        progressAnchor: row['progress_anchor'] is String
            ? ReadingAnchor.fromJson(
                Map<String, dynamic>.from(
                    jsonDecode(row['progress_anchor'] as String) as Map))
            : null,
      );

  static void _insert(Database db, BookRecord record,
      {bool ignoreDuplicates = false}) {
    final verb = ignoreDuplicates ? 'INSERT OR IGNORE' : 'INSERT';
    db.execute('''
      $verb INTO books (
        id, title, local_path, format, imported_at, progress_offset,
        progress_anchor
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [
      record.id,
      record.title,
      record.localPath,
      record.format.name,
      record.importedAt.toIso8601String(),
      record.progressOffset,
      record.progressAnchor == null
          ? null
          : jsonEncode(record.progressAnchor!.toJson()),
    ]);
  }

  static void _validateSignature(List<int> bytes, BookFormat format) {
    if (format == BookFormat.pdf &&
        !(bytes.length >= 5 &&
          bytes[0] == 0x25 && bytes[1] == 0x50 &&
          bytes[2] == 0x44 && bytes[3] == 0x46 && bytes[4] == 0x2D)) {
      throw const FormatException('Invalid PDF signature');
    }
    if (format == BookFormat.epub &&
        !(bytes.length >= 4 &&
          bytes[0] == 0x50 && bytes[1] == 0x4B &&
          bytes[2] == 0x03 && bytes[3] == 0x04)) {
      throw const FormatException('Invalid EPUB ZIP signature');
    }
  }

  static T _transaction<T>(Database db, T Function() run) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = run();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
