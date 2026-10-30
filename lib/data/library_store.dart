import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/book.dart';
import '../domain/book_collection.dart';
import '../domain/reading_activity.dart';
import 'epub_catalog_metadata.dart';
import 'library_backup.dart';
import 'library_backup_restore.dart';
import 'pdf_cover_thumbnail.dart';
import '../domain/reading_anchor.dart';
import '../domain/pronunciation_rule.dart';
import '../domain/speech_preferences.dart';
import '../domain/reading_preferences.dart';
import '../domain/book_bookmark.dart';
import '../domain/pdf_visual_bookmark.dart';
import '../domain/cloud_speech_consent.dart';
import '../domain/voice_cast.dart';
import '../domain/cast_span.dart';
import '../domain/character_candidate.dart';
import '../domain/alias_candidate.dart';
import '../domain/cast_merge.dart';
import '../domain/narrative_reference.dart';
import '../domain/llm_analysis_consent.dart';

/// Local, transactional Windows/Android library. Inject homeDirectory in tests.
class LibraryStore implements CloudSpeechAccess, LlmAnalysisAccess {
  LibraryStore({Directory? homeDirectory, PdfCoverRenderer? pdfCoverRenderer})
      : _configuredHome = homeDirectory,
        _pdfCoverRenderer = pdfCoverRenderer ?? renderPdfFirstPageThumbnail;
  final Directory? _configuredHome;
  final PdfCoverRenderer _pdfCoverRenderer;
  final Map<String, Future<File?>> _pendingPdfCovers = {};
  final Set<String> _failedPdfCovers = {};
  Directory? _home;
  Database? _db;
  String? _startupInterruptedBookId;

  // Process-local order of USER/visual bookmark writes. Speech recovery
  // writes must not change this counter: a delayed completion callback can
  // compare its starting revision and avoid undoing a later manual jump.
  // No schema migration is required: pending Futures cannot survive
  // process termination, while the actual bookmark is durable in SQLite.
  final Map<String, int> _manualPositionRevisions = {};
  int manualPositionRevision(String bookId) =>
      _manualPositionRevisions[bookId] ?? 0;

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('LibraryStore not initialized');
    return db;
  }

  Directory get _booksDir => Directory(p.join(_home!.path, 'books'));
  Directory get _coversDir => Directory(p.join(_home!.path, 'covers'));

  /// Cover assets are named exclusively by immutable SHA-256 book IDs.
  File? coverFile(String bookId) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(bookId)) return null;
    for (final ext in ['jpg', 'png']) {
      final file = File(p.join(_coversDir.path, '$bookId.$ext'));
      if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
          FileSystemEntityType.file) return file;
    }
    return null;
  }

  Future<void> _persistCover(String bookId, EpubCatalogMetadata meta) async {
    final image = meta.coverBytes;
    final extension = meta.coverExtension;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(bookId) ||
        image == null || !['jpg', 'png'].contains(extension) ||
        coverFile(bookId) != null) return;
    final destination = File(p.join(_coversDir.path, '$bookId.$extension'));
    final staging = File(destination.path + '.part');
    try {
      await _coversDir.create(recursive: true);
      await staging.writeAsBytes(image, flush: true);
      await staging.rename(destination.path);
    } on FileSystemException {
      // Image cache failure must never make an imported EPUB unreadable.
    } finally {
      try {
        if (await staging.exists()) await staging.delete();
      } on FileSystemException {
        // Windows may still have a decoder handle open.
      }
    }
  }

  /// Lazy, local first-page thumbnail. Only PDFs use PDFium; EPUB covers
  /// remain OPF-derived. Failures are remembered for this app session to
  /// avoid continuously reopening a malformed PDF when scrolling the list.
  /// Re-launching the app retries them. Import and reading never depend on it.
  Future<File?> ensurePdfCover(String bookId) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(bookId)) {
      return Future<File?>.value(null);
    }
    final book = getBook(bookId);
    if (book == null || book.format != BookFormat.pdf ||
        !_isManagedPath(book.localPath)) {
      return Future<File?>.value(null);
    }
    final existing = coverFile(bookId);
    if (existing != null) return Future<File?>.value(existing);
    if (_failedPdfCovers.contains(bookId)) return Future<File?>.value(null);
    final pending = _pendingPdfCovers[bookId];
    if (pending != null) return pending;
    final future = _generatePdfCover(book);
    _pendingPdfCovers[bookId] = future;
    future.then((_) => _pendingPdfCovers.remove(bookId));
    return future;
  }

  Future<File?> _generatePdfCover(BookRecord book) async {
    // Disposal during shutdown or a concurrent remove must not allow a
    // thumbnail worker to resurrect a deleted book or leak async errors.
    bool isCurrentBook() {
      try {
        return getBook(book.id)?.localPath == book.localPath;
      } on StateError {
        return false;
      }
    }
    final destination = File(p.join(_coversDir.path, '${book.id}.png'));
    final staging = File('${destination.path}.part');
    try {
      if (!await File(book.localPath).exists()) return null;
      final png = await _pdfCoverRenderer(book.localPath);
      if (png == null || png.length < 8 || png.length > 1024 * 1024 ||
          png[0] != 137 || png[1] != 80 || png[2] != 78 || png[3] != 71 ||
          png[4] != 13 || png[5] != 10 || png[6] != 26 || png[7] != 10) {
        return null;
      }
      await _coversDir.create(recursive: true);
      await staging.writeAsBytes(png, flush: true);
      // A deleted book or an import repair must not resurrect orphan images.
      if (!isCurrentBook()) return null;
      await staging.rename(destination.path);
      if (!isCurrentBook()) {
        if (await destination.exists()) await destination.delete();
        return null;
      }
      return destination;
    } catch (_) {
      // Renderer, password or filesystem errors leave the normal PDF icon.
      return null;
    } finally {
      try {
        if (await staging.exists()) await staging.delete();
      } on FileSystemException {
        // Windows thumbnail decoders can briefly hold handles.
      }
      if (isCurrentBook()) {
        try {
          if (FileSystemEntity.typeSync(
                destination.path, followLinks: false) !=
              FileSystemEntityType.file) {
            _failedPdfCovers.add(book.id);
          }
        } on FileSystemException {
          _failedPdfCovers.add(book.id);
        }
      }
    }
  }

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
      if (version > 24) {
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
          if (!_hasSqliteColumn(db, 'books', 'progress_anchor')) {
            db.execute('ALTER TABLE books ADD COLUMN progress_anchor TEXT');
          }
          db.execute('PRAGMA user_version = 2');
        });
      }
      if (version < 3) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS pronunciation_rules (
              id TEXT PRIMARY KEY NOT NULL,
              book_id TEXT,
              phrase TEXT NOT NULL,
              spoken_as TEXT NOT NULL,
              whole_word INTEGER NOT NULL DEFAULT 1,
              case_sensitive INTEGER NOT NULL DEFAULT 0,
              enabled INTEGER NOT NULL DEFAULT 1
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_pronunciation_book
            ON pronunciation_rules(book_id)
          ''');
          db.execute('''
            CREATE TABLE IF NOT EXISTS speech_preferences (
              scope_id TEXT PRIMARY KEY NOT NULL,
              value_json TEXT NOT NULL
            )
          ''');
          db.execute('PRAGMA user_version = 3');
        });
      }
      if (version < 4) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS bookmarks (
              id TEXT PRIMARY KEY NOT NULL,
              book_id TEXT NOT NULL REFERENCES books(id)
                ON DELETE CASCADE,
              title TEXT NOT NULL,
              global_offset INTEGER NOT NULL
                CHECK(global_offset >= 0),
              anchor_json TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_bookmarks_book
            ON bookmarks(book_id, created_at)
          ''');
          db.execute('PRAGMA user_version = 4');
        });
      }
      if (version < 5) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS cloud_speech_consent (
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              provider_id TEXT NOT NULL,
              allowed INTEGER NOT NULL DEFAULT 0,
              max_chars INTEGER NOT NULL DEFAULT 0,
              used_chars INTEGER NOT NULL DEFAULT 0,
              approved_at TEXT,
              PRIMARY KEY (book_id, provider_id),
              CHECK (max_chars >= 0 AND max_chars <= 10000000),
              CHECK (used_chars >= 0 AND used_chars <= max_chars)
            )
          ''');
          db.execute('PRAGMA user_version = 5');
        });
      }
      if (version < 6) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS cast_characters (
              id TEXT PRIMARY KEY NOT NULL,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              display_name TEXT NOT NULL,
              aliases_json TEXT NOT NULL DEFAULT '[]'
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_cast_book
            ON cast_characters(book_id, display_name)
          ''');
          db.execute('''
            CREATE TABLE IF NOT EXISTS cast_voices (
              character_id TEXT NOT NULL
                REFERENCES cast_characters(id) ON DELETE CASCADE,
              provider_id TEXT NOT NULL,
              voice_name TEXT NOT NULL,
              voice_locale TEXT NOT NULL,
              PRIMARY KEY (character_id, provider_id)
            )
          ''');
          db.execute('''
            CREATE TABLE IF NOT EXISTS segment_cast (
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              start_offset INTEGER NOT NULL,
              end_offset INTEGER NOT NULL,
              source_sha256 TEXT NOT NULL,
              character_id TEXT NOT NULL
                REFERENCES cast_characters(id) ON DELETE CASCADE,
              anchor_json TEXT,
              PRIMARY KEY (book_id, start_offset, end_offset),
              CHECK (start_offset >= 0 AND end_offset > start_offset)
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_segment_cast_character
            ON segment_cast(character_id)
          ''');
          db.execute('PRAGMA user_version = 6');
        });
      }
      if (version < 7) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS cast_spans (
              id TEXT PRIMARY KEY NOT NULL,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              start_offset INTEGER NOT NULL,
              end_offset INTEGER NOT NULL,
              source_sha256 TEXT NOT NULL,
              speaker_id TEXT REFERENCES cast_characters(id)
                ON DELETE SET NULL,
              anchor_json TEXT,
              origin TEXT NOT NULL,
              status TEXT NOT NULL,
              confidence REAL,
              locked_by_user INTEGER NOT NULL DEFAULT 0,
              CHECK (start_offset >= 0 AND end_offset > start_offset),
              CHECK (origin IN ('user', 'llm')),
              CHECK (status IN ('proposed', 'accepted', 'rejected'))
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_cast_spans_book
            ON cast_spans(book_id, start_offset, end_offset)
          ''');
          db.execute('PRAGMA user_version = 7');
        });
      }
      if (version < 8) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS llm_analysis_consent (
              book_id TEXT PRIMARY KEY NOT NULL
                REFERENCES books(id) ON DELETE CASCADE,
              allowed INTEGER NOT NULL DEFAULT 0,
              max_input_chars INTEGER NOT NULL DEFAULT 0,
              used_input_chars INTEGER NOT NULL DEFAULT 0,
              approved_at TEXT,
              CHECK (max_input_chars >= 0 AND max_input_chars <= 10000000),
              CHECK (used_input_chars >= 0 AND
                     used_input_chars <= max_input_chars)
            )
          ''');
          db.execute('PRAGMA user_version = 8');
        });
      }
      if (version < 9) {
        _transaction(db, () {
          if (!_hasSqliteColumn(db, 'cast_spans', 'evidence_json')) {
            db.execute('ALTER TABLE cast_spans ADD COLUMN evidence_json TEXT');
          }
          db.execute('PRAGMA user_version = 9');
        });
      }
      if (version < 10) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS character_candidates (
              id TEXT PRIMARY KEY,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              proposed_name TEXT NOT NULL,
              mention_start INTEGER NOT NULL,
              mention_end INTEGER NOT NULL,
              source_sha256 TEXT NOT NULL,
              confidence REAL NOT NULL,
              status TEXT NOT NULL DEFAULT 'proposed',
              created_character_id TEXT
                REFERENCES cast_characters(id) ON DELETE SET NULL,
              CHECK (mention_start >= 0 AND mention_end > mention_start),
              CHECK (confidence >= 0 AND confidence <= 1),
              CHECK (status IN ('proposed', 'accepted', 'rejected')),
              UNIQUE(book_id, mention_start, mention_end, proposed_name)
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_character_candidates_book
            ON character_candidates(book_id, status, mention_start)
          ''');
          db.execute('PRAGMA user_version = 10');
        });
      }
      if (version < 11) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS alias_candidates (
              id TEXT PRIMARY KEY,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              alias_text TEXT NOT NULL,
              suggested_character_id TEXT
                REFERENCES cast_characters(id) ON DELETE SET NULL,
              approved_character_id TEXT
                REFERENCES cast_characters(id) ON DELETE SET NULL,
              mention_start INTEGER NOT NULL,
              mention_end INTEGER NOT NULL,
              source_sha256 TEXT NOT NULL,
              evidence_json TEXT,
              confidence REAL NOT NULL,
              status TEXT NOT NULL DEFAULT 'proposed',
              CHECK (mention_start >= 0 AND mention_end > mention_start),
              CHECK (confidence >= 0 AND confidence <= 1),
              CHECK (status IN ('proposed', 'accepted', 'rejected')),
              UNIQUE(book_id, mention_start, mention_end, alias_text)
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_alias_candidates_book
            ON alias_candidates(book_id, status, mention_start)
          ''');
          db.execute('PRAGMA user_version = 11');
        });
      }
      if (version < 12) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS cast_merges (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              old_character_id TEXT NOT NULL,
              kept_character_id TEXT NOT NULL,
              old_name TEXT NOT NULL,
              kept_name TEXT NOT NULL,
              snapshot_sha256 TEXT NOT NULL,
              voice_choices_json TEXT NOT NULL,
              updated_records_json TEXT NOT NULL,
              merged_at TEXT NOT NULL
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_cast_merges_book
            ON cast_merges(book_id, merged_at)
          ''');
          db.execute('PRAGMA user_version = 12');
        });
      }
      if (version < 13) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS narrative_references (
              id TEXT PRIMARY KEY,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              mention_start INTEGER NOT NULL,
              mention_end INTEGER NOT NULL,
              mention_text TEXT NOT NULL,
              source_sha256 TEXT NOT NULL,
              mention_kind TEXT NOT NULL,
              proposed_character_id TEXT
                REFERENCES cast_characters(id) ON DELETE SET NULL,
              approved_character_id TEXT
                REFERENCES cast_characters(id) ON DELETE SET NULL,
              confidence REAL NOT NULL,
              ambiguous INTEGER NOT NULL DEFAULT 0,
              evidence_json TEXT,
              status TEXT NOT NULL DEFAULT 'proposed',
              CHECK (mention_start >= 0 AND mention_end > mention_start),
              CHECK (confidence >= 0 AND confidence <= 1),
              CHECK (ambiguous IN (0, 1)),
              CHECK (status IN ('proposed', 'accepted', 'rejected')),
              UNIQUE (book_id, mention_start, mention_end)
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_narrative_ref_book
            ON narrative_references(book_id, status, mention_start)
          ''');
          db.execute('PRAGMA user_version = 13');
        });
      }
      // Optional local-only last-opened marker. This contains neither text,
      // TTS authorization nor credentials and does not enable auto-play.
      if (version < 14) {
        _transaction(db, () {
          if (!_hasSqliteColumn(db, 'books', 'last_opened_at')) {
            db.execute('ALTER TABLE books ADD COLUMN last_opened_at TEXT');
          }
          db.execute('PRAGMA user_version = 14');
        });
      }
      // Visual PDF page is deliberately separate from the extracted-text
      // source anchor. Scanned PDFs have no read-aloud position at all.
      if (version < 15) {
        _transaction(db, () {
          if (!_hasSqliteColumn(db, 'books', 'pdf_visual_page')) {
            db.execute('ALTER TABLE books ADD COLUMN pdf_visual_page INTEGER '
                'CHECK(pdf_visual_page IS NULL OR '
                '(pdf_visual_page >= 1 AND pdf_visual_page <= 100000))');
          }
          db.execute('PRAGMA user_version = 15');
        });
      }
      // A single, intentionally ephemeral "narration may have been
      // interrupted" marker. It stores no text, credentials or permission.
      // The last spoken *source anchor* is saved atomically with this row.
      if (version < 16) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS speech_recovery_marker (
              slot INTEGER PRIMARY KEY NOT NULL CHECK(slot = 1),
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              started_at TEXT NOT NULL
            )
          ''');
          db.execute('PRAGMA user_version = 16');
        });
      }
      // Optional fields are independent of the immutable source hash.
      if (version < 17) {
        _transaction(db, () {
          for (final column in ['author', 'series', 'language']) {
            if (!_hasSqliteColumn(db, 'books', column)) {
              db.execute('ALTER TABLE books ADD COLUMN $column TEXT');
            }
          }
          db.execute('PRAGMA user_version = 17');
        });
      }
      // Visual reading preferences are separate from speech engine settings.
      // Scope keys have no foreign key, so deletion explicitly clears
      // any per-book override in removeBook().
      if (version < 18) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS reading_preferences (
              scope_id TEXT PRIMARY KEY NOT NULL,
              value_json TEXT NOT NULL
            )
          ''');
          db.execute('PRAGMA user_version = 18');
        });
      }
      // Dedicated visual-only PDF page bookmarks. Do not mix physical page
      // numbers with source offsets in the narration bookmarks table.
      if (version < 19) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS pdf_visual_bookmarks (
              id TEXT PRIMARY KEY NOT NULL,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              title TEXT NOT NULL,
              page_number INTEGER NOT NULL
                CHECK(page_number >= 1 AND page_number <= 100000),
              created_at TEXT NOT NULL
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_pdf_visual_bookmark_book
            ON pdf_visual_bookmarks(book_id, page_number)
          ''');
          db.execute('PRAGMA user_version = 19');
        });
      }
      // User-starred books are catalog metadata, not a text/TTS checkpoint.
      // All existing books default to not starred after v19 -> v20.
      if (version < 20) {
        _transaction(db, () {
          if (!_hasSqliteColumn(db, 'books', 'is_favorite')) {
            db.execute(
              'ALTER TABLE books ADD COLUMN is_favorite INTEGER NOT NULL '
              'DEFAULT 0 CHECK(is_favorite IN (0, 1))',
            );
          }
          db.execute('PRAGMA user_version = 20');
        });
      }
      // Explicit reading shelf; a 'Finished' label never means TTS/audio
      // completed and must not change the persisted source checkpoint.
      if (version < 21) {
        _transaction(db, () {
          if (!_hasSqliteColumn(db, 'books', 'reading_status')) {
            db.execute(
              "ALTER TABLE books ADD COLUMN reading_status TEXT NOT NULL "
              "DEFAULT 'toRead' CHECK(reading_status IN "
              "('toRead', 'reading', 'finished'))",
            );
          }
          db.execute('PRAGMA user_version = 21');
        });
      }
      // A collection is a local user-defined category, not a folder on
      // disk. The many-to-many table has FK cascade from both sides.
      if (version < 22) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS book_collections (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL COLLATE NOCASE UNIQUE,
              created_at TEXT NOT NULL
            )
          ''');
          db.execute('''
            CREATE TABLE IF NOT EXISTS book_collection_members (
              collection_id TEXT NOT NULL
                REFERENCES book_collections(id) ON DELETE CASCADE,
              book_id TEXT NOT NULL
                REFERENCES books(id) ON DELETE CASCADE,
              PRIMARY KEY (collection_id, book_id)
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_collection_members_book
            ON book_collection_members(book_id, collection_id)
          ''');
          db.execute('PRAGMA user_version = 22');
        });
      }
      // v23 stores only daily integer totals and a user-set goal. No
      // individual action timestamps, content, or automatic cloud sync.
      if (version < 23) {
        _transaction(db, () {
          db.execute('''
            CREATE TABLE IF NOT EXISTS reading_activity_daily (
              book_id TEXT NOT NULL
                REFERENCES books(id) ON DELETE CASCADE,
              local_day TEXT NOT NULL,
              mode TEXT NOT NULL
                CHECK(mode IN ('visual', 'tts')),
              seconds INTEGER NOT NULL DEFAULT 0
                CHECK(seconds >= 0),
              PRIMARY KEY(book_id, local_day, mode)
            )
          ''');
          db.execute('''
            CREATE INDEX IF NOT EXISTS idx_reading_activity_day
            ON reading_activity_daily(local_day)
          ''');
          db.execute('''
            CREATE TABLE IF NOT EXISTS reading_activity_settings (
              slot INTEGER PRIMARY KEY CHECK(slot = 1),
              goal_minutes INTEGER NOT NULL DEFAULT 20
                CHECK(goal_minutes BETWEEN 0 AND 240)
            )
          ''');
          db.execute('''
            INSERT OR IGNORE INTO reading_activity_settings(slot, goal_minutes)
            VALUES (1, 20)
          ''');
          db.execute('PRAGMA user_version = 23');
        });
      }
      // v24: user-controlled, persistent opt-out. Existing installations
      // preserve the previous enabled behavior until deliberately disabled.
      // A partially downgraded marker must not attempt ADD COLUMN twice.
      if (version < 24) {
        _transaction(db, () {
          if (!_hasSqliteColumn(
              db, 'reading_activity_settings', 'tracking_enabled')) {
            db.execute('''
              ALTER TABLE reading_activity_settings
              ADD COLUMN tracking_enabled INTEGER NOT NULL DEFAULT 1
                CHECK(tracking_enabled IN (0, 1))
            ''');
          }
          db.execute('PRAGMA user_version = 24');
        });
      }
      await _migrateLegacyJson(db, support);
      // A marker is stale only on a new process startup. Consume exactly
      // once; reopening a book must NEVER cause the app to auto-synthesize.
      _startupInterruptedBookId = _transaction(db, () {
        final rows = db.select(
            'SELECT book_id FROM speech_recovery_marker WHERE slot = 1');
        db.execute('DELETE FROM speech_recovery_marker WHERE slot = 1');
        return rows.isEmpty ? null : rows.first['book_id'] as String;
      });
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

  /// Explicit local backup only. A WAL-safe VACUUM INTO SQLite snapshot
  /// is paired with exact managed book bytes, validated by SHA-256 before
  /// the output folder is promoted. The OS credential vault is excluded.
  /// Restoring on a different device requires later path relinking.
  Future<LibraryBackupResult> exportLibraryBackup(
    Directory destination, {
    void Function(int done, int total)? onProgress,
  }) async {
    final sourceHome = _home;
    if (sourceHome == null) {
      throw StateError('LibraryStore is not initialized');
    }
    return exportPortableLibraryBackup(
      sourceHome: sourceHome,
      destinationParent: destination,
      books: books,
      writeSqliteSnapshot: (output) {
        // SQLite's native VACUUM INTO yields a standalone consistent
        // snapshot, unlike copying an active WAL-mode DB file directly.
        _database.execute('VACUUM INTO ?', [output]);
      },
      onProgress: onProgress,
    );
  }

  /// Full read-only inspection before touching any library file/row.
  /// Existing hashes are never overwritten, including their positions,
  /// bookmarks, metadata, voice settings and cloud permissions.
  Future<LibraryRestorePreview> previewLibraryRestore(
    Directory backup, {
    void Function(int done, int total)? onProgress,
  }) async {
    final validated = await inspectLibraryBackup(
      backup, onProgress: onProgress);
    final existingIds = books.map((book) => book.id).toSet();
    final newBooks = validated.books.where(
        (book) => !existingIds.contains(book.id)).toList();
    return LibraryRestorePreview(
      total: validated.books.length,
      availableToImport: newBooks.length,
      alreadyPresent: validated.books.length - newBooks.length,
      bookmarksToImport: newBooks.fold<int>(
          0, (count, book) => count + book.bookmarks.length +
              book.pdfVisualBookmarks.length),
      verifiedBytes: validated.totalBookBytes,
      collectionsToImport: validated.collectionCatalog.where((name) =>
          !collections.any((existing) =>
              existing.name.toLowerCase() == name.toLowerCase())).length,
    );
  }

  /// Opt-in, add-only v1 restore. The backup is re-verified before writing,
  /// and each new book is copied with a digest check before one SQLite
  /// transaction inserts its metadata + bookmarks. A failed later book
  /// leaves earlier successful books but never changes an existing book.
  ///
  /// No global preferences, per-book TTS preferences, cloud/LLM consents,
  /// credentials, voice/cast tables, or crash/autoplay recovery are restored.
  Future<LibraryRestoreResult> restoreLibraryBackup(
    Directory backup, {
    void Function(int done, int total)? onProgress,
  }) async {
    final home = _home;
    if (home == null) throw StateError('LibraryStore not initialized');
    final homePath = p.normalize(p.absolute(home.path));
    final backupPath = p.normalize(p.absolute(backup.path));
    if (p.isWithin(homePath, backupPath) ||
        p.isWithin(backupPath, homePath) || backupPath == homePath) {
      throw const FormatException('Backup must be outside app storage');
    }
    // Re-check the complete archive, even after a successful preview;
    // never trust a manifest cached before confirmation.
    final inspected = await inspectLibraryBackup(backup);
    // Do not copy sensitive books through a symlinked managed directory.
    // Directory.create(recursive:true) at startup would otherwise accept
    // a pre-existing symlink/junction as a valid folder.
    if (await FileSystemEntity.type(
            _booksDir.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Managed books folder is not a directory');
    }
    var added = 0;
    var skipped = 0;
    var bookmarks = 0;
    // Recover the entire catalog, even empty folders and when every book
    // already exists. No existing name or membership is overwritten.
    final importedCollections = _transaction(_database, () {
      var created = 0;
      for (final name in inspected.collectionCatalog) {
        final present = _database.select(
          'SELECT id FROM book_collections WHERE name = ? COLLATE NOCASE',
          [name],
        );
        if (present.isEmpty) {
          _ensureRestoredCollection(name);
          created++;
        }
      }
      return created;
    });
    for (final entry in inspected.books) {
      if (getBook(entry.id) != null) {
        skipped++;
        onProgress?.call(added + skipped, inspected.books.length);
        continue;
      }

      final target = File(p.join(
          _booksDir.path, '${entry.id}.${entry.format.extension}'));
      if (!_isManagedPath(target.path)) {
        throw const FormatException('Invalid private book destination');
      }
      final temp = File('${target.path}.restore.part');
      var createdTarget = false;
      try {
        final type = await FileSystemEntity.type(
            target.path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          // A stale temporary symlink must not redirect the next copy
          // outside managed storage, even if it has a plausible name.
          final stagedType = await FileSystemEntity.type(
              temp.path, followLinks: false);
          if (stagedType == FileSystemEntityType.link) {
            throw const FormatException('Unsafe temporary book file');
          }
          if (stagedType != FileSystemEntityType.file &&
              stagedType != FileSystemEntityType.notFound) {
            throw const FormatException('Invalid temporary book path');
          }
          // Stream/copy the exact verified book; check again in case the
          // external backup was changed during restore.
          if (await temp.exists()) await temp.delete();
          await entry.file.copy(temp.path);
          final digest =
              (await sha256.bind(temp.openRead()).first).toString();
          if (digest != entry.id) {
            throw const FormatException('Backup changed during restore');
          }
          await temp.rename(target.path);
          createdTarget = true;
        } else if (type != FileSystemEntityType.file ||
            (await sha256.bind(target.openRead()).first).toString() !=
                entry.id) {
          throw const FormatException('Conflicting private book file');
        }

        // New-book progress and bookmarks are restored atomically, with
        // unique remapped bookmark IDs. No existing catalog row is touched.
        _transaction(_database, () {
          if (getBook(entry.id) != null) {
            throw StateError('Book appeared during restore');
          }
          _insert(_database, BookRecord(
            id: entry.id,
            title: entry.title,
            author: entry.author,
            series: entry.series,
            language: entry.language,
            localPath: target.path,
            format: entry.format,
            importedAt: entry.importedAt,
            progressOffset: entry.progressOffset,
            progressAnchor: entry.anchor,
            isFavorite: entry.isFavorite,
            readingStatus: entry.readingStatus,
          ));
          if (entry.format == BookFormat.pdf &&
              entry.pdfVisualPage != null) {
            _database.execute(
              'UPDATE books SET pdf_visual_page = ? WHERE id = ?',
              [entry.pdfVisualPage, entry.id],
            );
          }
          // Existing destination collections win by name. New collection
          // rows and memberships participate in this book's transaction;
          // existing books and their memberships are never touched.
          for (final name in entry.collectionNames) {
            final collectionId = _ensureRestoredCollection(name);
            _database.execute('''
              INSERT INTO book_collection_members (collection_id, book_id)
              VALUES (?, ?)
            ''', [collectionId, entry.id]);
          }
          for (final mark in entry.pdfVisualBookmarks) {
            // Imported IDs use the same deterministic collision-safe
            // namespace as text bookmarks but a distinct table and type.
            final suffix = sha256.convert(utf8.encode(mark.id))
                .toString().substring(0, 56);
            final bookmarkId = '${entry.id}:pdf:$suffix';
            _database.execute('''
              INSERT INTO pdf_visual_bookmarks
                (id, book_id, title, page_number, created_at)
              VALUES (?, ?, ?, ?, ?)
            ''', [
              bookmarkId, entry.id, mark.title, mark.pageNumber,
              mark.createdAt.toUtc().toIso8601String(),
            ]);
          }
          for (final mark in entry.bookmarks) {
            // The backup bookmark ID is not trusted as a global key.
            // Remapping by immutable book ID prevents collision with
            // bookmarks already present from unrelated local books.
            final suffix =
                sha256.convert(utf8.encode(mark.id)).toString()
                    .substring(0, 56);
            final bookmarkId = '${entry.id}:$suffix';
            _database.execute('''
              INSERT INTO bookmarks (id, book_id, title, global_offset,
                  anchor_json, created_at)
              VALUES (?, ?, ?, ?, ?, ?)
            ''', [
              bookmarkId, entry.id, mark.title, mark.globalOffset,
              mark.anchor == null
                  ? null : jsonEncode(mark.anchor!.toJson()),
              mark.createdAt.toIso8601String(),
            ]);
          }
        });
        added++;
        bookmarks += entry.bookmarks.length + entry.pdfVisualBookmarks.length;
      } catch (_) {
        // File staging never becomes a valid book. A target created by
        // this restore may be removed ONLY when no committed DB row
        // references it. Existing files are never removed.
        if (createdTarget && getBook(entry.id) == null) {
          try {
            if (await target.exists()) await target.delete();
          } on FileSystemException {
            // Next manual attempt verifies the orphan hash before reuse.
          }
        }
        rethrow;
      } finally {
        try {
          if (await temp.exists()) await temp.delete();
        } on FileSystemException {
          // Windows may hold a transient file lock; no database row
          // points to the .part file.
        }
      }
      onProgress?.call(added + skipped, inspected.books.length);
    }
    return LibraryRestoreResult(
      added: added, skipped: skipped, bookmarksImported: bookmarks,
      collectionsImported: importedCollections,
    );
  }

  /// Adds at most one bounded sample interval; never writes text, source
  /// positions, audio, API data or the individual event timestamp. The
  /// integer day bucket uses the device's local calendar when sampled.
  void recordReadingActivity(
    String bookId, ReadingActivityMode mode, int seconds, {
    DateTime? at,
  }) {
    if (seconds < 1 || seconds > 30) {
      throw RangeError.range(seconds, 1, 30, 'seconds');
    }
    if (getBook(bookId) == null) {
      throw StateError('Cannot record activity for an unknown book');
    }
    // Enforcement belongs at the storage boundary, not just the toggle
    // widget: late Timer callbacks cannot silently override an opt-out.
    if (!isReadingActivityTrackingEnabled) return;
    final day = readingLocalDate(at ?? DateTime.now());
    _database.execute('''
      INSERT INTO reading_activity_daily(book_id, local_day, mode, seconds)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(book_id, local_day, mode)
      DO UPDATE SET seconds = seconds + excluded.seconds
    ''', [bookId, day, mode.name, seconds]);
  }

  /// Explicit user-requested deletion of locally recorded activity only.
  /// Returning affected aggregate rows lets the UI report accurately.
  /// The goal, books, reading progress, bookmarks and TTS settings survive.
  ///
  /// A book-scoped clear rejects an unknown ID; an unscoped clear affects
  /// every book, including items hidden by library filters.
  int clearReadingActivity({String? bookId}) {
    if (bookId != null && getBook(bookId) == null) {
      throw StateError('Cannot clear activity for an unknown book');
    }
    if (bookId == null) {
      _database.execute('DELETE FROM reading_activity_daily');
    } else {
      _database.execute(
        'DELETE FROM reading_activity_daily WHERE book_id = ?', [bookId],
      );
    }
    return _database.select(
      'SELECT changes() AS affected',
    ).single['affected'] as int;
  }

  /// Local-only toggle. Disabling keeps all existing aggregate rows and
  /// the user's goal intact; re-enabling starts recording new time only.
  bool get isReadingActivityTrackingEnabled =>
      (_database.select('''
        SELECT tracking_enabled FROM reading_activity_settings
        WHERE slot = 1
      ''').single['tracking_enabled'] as int) == 1;

  void saveReadingActivityTrackingEnabled(bool enabled) {
    _database.execute('''
      UPDATE reading_activity_settings
      SET tracking_enabled = ? WHERE slot = 1
    ''', [enabled ? 1 : 0]);
  }

  int get dailyReadingGoalMinutes =>
      _database.select(
        'SELECT goal_minutes FROM reading_activity_settings WHERE slot = 1',
      ).single['goal_minutes'] as int;

  void saveDailyReadingGoalMinutes(int minutes) {
    if (minutes < 0 || minutes > 240) {
      throw RangeError.range(minutes, 0, 240, 'minutes');
    }
    _database.execute('''
      UPDATE reading_activity_settings SET goal_minutes = ? WHERE slot = 1
    ''', [minutes]);
  }

  /// Rolling seven LOCAL calendar dates. Uses aggregated row counts, never
  /// claims a last-opened timestamp is a timed reading session.
  WeeklyReadingActivity weeklyReadingActivity({
    DateTime? now,
    String? bookId,
  }) {
    if (bookId != null && getBook(bookId) == null) {
      throw StateError('Cannot summarize an unknown book');
    }
    final local = (now ?? DateTime.now()).toLocal();
    final days = [
      for (var i = 6; i >= 0; i--)
        readingLocalDate(DateTime(
          local.year, local.month, local.day - i,
        )),
    ];
    final totals = <String, Map<ReadingActivityMode, int>>{
      for (final day in days) day: {
        ReadingActivityMode.visual: 0,
        ReadingActivityMode.tts: 0,
      },
    };
    for (final row in _database.select('''
      SELECT local_day, mode, SUM(seconds) AS total_seconds
      FROM reading_activity_daily
      WHERE local_day BETWEEN ? AND ?
      ${bookId == null ? '' : 'AND book_id = ?'}
      GROUP BY local_day, mode
    ''', [days.first, days.last, if (bookId != null) bookId])) {
      final day = row['local_day'] as String;
      final mode = ReadingActivityMode.values.byName(row['mode'] as String);
      totals[day]?[mode] = row['total_seconds'] as int;
    }
    return WeeklyReadingActivity(
      goalMinutes: dailyReadingGoalMinutes,
      days: List.unmodifiable([
        for (final day in days)
          ReadingActivityDay(
            date: day,
            visualSeconds: totals[day]![ReadingActivityMode.visual]!,
            ttsSeconds: totals[day]![ReadingActivityMode.tts]!,
          ),
      ]),
    );
  }

  /// The most active books in seven local calendar days (max 50).
  /// One bounded SQL query, without per-book scans or text extraction.
  List<BookReadingActivityTotals> mostActiveReadingBooks({
    DateTime? now,
    int limit = 10,
  }) {
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final local = (now ?? DateTime.now()).toLocal();
    final first = readingLocalDate(
        DateTime(local.year, local.month, local.day - 6));
    final last = readingLocalDate(local);
    final rows = _database.select('''
      SELECT b.id AS book_id, b.title AS title,
        SUM(CASE WHEN a.mode = 'visual' THEN a.seconds ELSE 0 END)
          AS visual_seconds,
        SUM(CASE WHEN a.mode = 'tts' THEN a.seconds ELSE 0 END)
          AS tts_seconds
      FROM reading_activity_daily a
      JOIN books b ON b.id = a.book_id
      WHERE a.local_day BETWEEN ? AND ?
      GROUP BY b.id, b.title
      HAVING SUM(a.seconds) > 0
      ORDER BY SUM(a.seconds) DESC, b.title COLLATE NOCASE ASC, b.id ASC
      LIMIT ?
    ''', [first, last, limit]);
    return List.unmodifiable(rows.map((row) => BookReadingActivityTotals(
      bookId: row['book_id'] as String,
      title: row['title'] as String,
      visualSeconds: row['visual_seconds'] as int,
      ttsSeconds: row['tts_seconds'] as int,
    )));
  }

  /// All recorded time for one existing book, including previous weeks.
  BookReadingActivityTotals bookReadingLifetimeTotals(String bookId) {
    final book = getBook(bookId);
    if (book == null) {
      throw StateError('Cannot summarize an unknown book');
    }
    final rows = _database.select('''
      SELECT mode, SUM(seconds) AS total_seconds
      FROM reading_activity_daily
      WHERE book_id = ?
      GROUP BY mode
    ''', [bookId]);
    var visual = 0;
    var tts = 0;
    for (final row in rows) {
      if (row['mode'] == 'visual') {
        visual = row['total_seconds'] as int;
      } else if (row['mode'] == 'tts') {
        tts = row['total_seconds'] as int;
      }
    }
    return BookReadingActivityTotals(
      bookId: bookId,
      title: book.title,
      visualSeconds: visual,
      ttsSeconds: tts,
    );
  }

  List<BookRecord> get books => _database
      .select('SELECT * FROM books ORDER BY imported_at DESC, title COLLATE NOCASE')
      .map(_fromRow)
      .toList();

  /// Collections are book classifications, never book directories.
  List<BookCollection> get collections => _database.select('''
    SELECT id, name, created_at FROM book_collections
    ORDER BY name COLLATE NOCASE, id
  ''').map((row) => BookCollection(
    id: row['id'] as String,
    name: row['name'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  )).toList();

  BookCollection createCollection(String name) {
    final clean = BookCollection.cleanName(name);
    if ((_database.select('SELECT COUNT(*) AS n FROM book_collections')
            .first['n'] as int) >= 1000) {
      throw StateError('Too many collections');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(1 << 32)}';
    final created = DateTime.now().toUtc();
    _database.execute('''
      INSERT INTO book_collections (id, name, created_at) VALUES (?, ?, ?)
    ''', [id, clean, created.toIso8601String()]);
    return BookCollection(id: id, name: clean, createdAt: created);
  }

  BookCollection renameCollection(String id, String name) {
    final clean = BookCollection.cleanName(name);
    _database.execute(
      'UPDATE book_collections SET name = ? WHERE id = ?', [clean, id],
    );
    if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
      throw StateError('Cannot rename an unknown collection');
    }
    return collections.firstWhere((item) => item.id == id);
  }

  void deleteCollection(String id) {
    _database.execute('DELETE FROM book_collections WHERE id = ?', [id]);
    if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
      throw StateError('Cannot delete an unknown collection');
    }
    // The foreign key cascades membership only, never books themselves.
  }

  List<BookCollection> listBookCollections(String bookId) {
    if (getBook(bookId) == null) throw StateError('Unknown book');
    return _database.select('''
      SELECT c.id, c.name, c.created_at
      FROM book_collections c
      INNER JOIN book_collection_members m ON c.id = m.collection_id
      WHERE m.book_id = ?
      ORDER BY c.name COLLATE NOCASE, c.id
    ''', [bookId]).map((row) => BookCollection(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    )).toList();
  }

  Set<String> collectionBookIds(String collectionId) {
    if (!_database.select('SELECT id FROM book_collections WHERE id = ?',
        [collectionId]).isNotEmpty) {
      throw StateError('Unknown collection');
    }
    return _database.select(
      'SELECT book_id FROM book_collection_members WHERE collection_id = ?',
      [collectionId],
    ).map((row) => row['book_id'] as String).toSet();
  }

  void setBookCollection(
      String bookId, String collectionId, bool included) {
    if (getBook(bookId) == null) throw StateError('Unknown book');
    if (_database.select('SELECT id FROM book_collections WHERE id = ?',
        [collectionId]).isEmpty) {
      throw StateError('Unknown collection');
    }
    if (included) {
      _database.execute('''
        INSERT OR IGNORE INTO book_collection_members
          (collection_id, book_id) VALUES (?, ?)
      ''', [collectionId, bookId]);
    } else {
      _database.execute('''
        DELETE FROM book_collection_members
        WHERE collection_id = ? AND book_id = ?
      ''', [collectionId, bookId]);
    }
  }

  /// Reuse local collection identities; imported names are untrusted
  /// until validated by the independent backup inspector.
  String _ensureRestoredCollection(String name) {
    final clean = BookCollection.cleanName(name);
    if (clean != name) {
      throw const FormatException('Noncanonical collection name');
    }
    final existing = _database.select(
      'SELECT id FROM book_collections WHERE name = ? COLLATE NOCASE',
      [name],
    );
    if (existing.isNotEmpty) return existing.single['id'] as String;
    final count = _database.select(
      'SELECT COUNT(*) AS n FROM book_collections',
    ).single['n'] as int;
    if (count >= 1000) {
      throw const FormatException('Too many restored collections');
    }
    final id = 'restore_'
        '${sha256.convert(utf8.encode(name))}';
    _database.execute('''
      INSERT INTO book_collections (id, name, created_at)
      VALUES (?, ?, ?)
    ''', [id, clean, DateTime.now().toUtc().toIso8601String()]);
    return id;
  }

  /// Star/unstar a known book. Catalog-only; neither a reading event nor
  /// a TTS operation. The change is visible on the next library query.
  BookRecord setBookFavorite(String bookId, bool favorite) {
    _database.execute(
      'UPDATE books SET is_favorite = ? WHERE id = ?',
      [favorite ? 1 : 0, bookId],
    );
    if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
      throw StateError('Cannot favorite an unknown book');
    }
    return getBook(bookId)!;
  }

  /// User-selected shelf; does not read or modify any narration state.
  BookRecord setBookReadingStatus(String bookId, BookReadingStatus status) {
    _database.execute(
      'UPDATE books SET reading_status = ? WHERE id = ?',
      [status.name, bookId],
    );
    if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
      throw StateError('Cannot set reading status of an unknown book');
    }
    return getBook(bookId)!;
  }

  /// User catalog edits do not rewrite a book's identity, source, progress,
  /// bookmarks, speaker cast or narration consent.
  BookRecord updateBookMetadata(
    String bookId, {
    required String title,
    String? author,
    String? series,
    String? language,
  }) {
    String normalize(String value, String field, {bool mustBeNonempty = false}) {
      final clean = value.trim();
      if ((mustBeNonempty && clean.isEmpty) ||
          clean.length > 160 ||
          clean.runes.any((unit) => unit < 32 || unit == 127)) {
        throw FormatException('Invalid $field metadata');
      }
      return clean;
    }
    final cleanTitle = normalize(title, 'title', mustBeNonempty: true);
    final cleanAuthor = normalize(author ?? '', 'author');
    final cleanSeries = normalize(series ?? '', 'series');
    final cleanLanguage = (language ?? '').trim();
    if (cleanLanguage.isNotEmpty &&
        !RegExp(r'^[a-zA-Z]{2,8}([-_][a-zA-Z0-9]{2,8})?$')
            .hasMatch(cleanLanguage)) {
      throw const FormatException('Use a locale such as it-IT or en-US');
    }
    _transaction(_database, () {
      _database.execute('''
        UPDATE books SET title = ?, author = ?, series = ?, language = ?
        WHERE id = ?
      ''', [
        cleanTitle,
        cleanAuthor.isEmpty ? null : cleanAuthor,
        cleanSeries.isEmpty ? null : cleanSeries,
        cleanLanguage.isEmpty ? null : cleanLanguage.replaceAll('_', '-'),
        bookId,
      ]);
      if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
        throw StateError('Cannot edit an unknown book');
      }
    });
    return getBook(bookId)!;
  }

  /// Explicit, opt-in enrichment of already imported EPUB books. A null
  /// field is filled from the local OPF, but previously set/user-edited
  /// fields (including the display title) are never replaced.
  Future<BookRecord> fillMissingEpubMetadata(String bookId) async {
    final existing = getBook(bookId);
    if (existing == null) throw StateError('Unknown book');
    if (existing.format != BookFormat.epub) {
      throw const FormatException('Only EPUB has OPF metadata');
    }
    final source = File(existing.localPath);
    final length = await source.length();
    if (length < 4 || length > 100 * 1024 * 1024) {
      throw const FormatException('Invalid EPUB size for metadata recovery');
    }
    final bytes = await source.readAsBytes();
    final catalog = await Isolate.run(
      () => const EpubCatalogMetadataReader().read(bytes),
      debugName: 'EReader recover EPUB catalog',
    );
    _transaction(_database, () {
      _database.execute('''
        UPDATE books SET
          author = COALESCE(author, ?),
          series = COALESCE(series, ?),
          language = COALESCE(language, ?)
        WHERE id = ?
      ''', [catalog.author, catalog.series, catalog.language, bookId]);
    });
    await _persistCover(bookId, catalog);
    return getBook(bookId)!;
  }

  BookRecord? getBook(String id) {
    final rows = _database.select('SELECT * FROM books WHERE id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// The most recent explicit book-opening action, after an app restart.
  /// Deleted/missing private files are not offered as a resume shortcut.
  /// Position always comes from the existing source-anchor record.
  BookRecord? get lastOpenedBook {
    final rows = _database.select('''
      SELECT * FROM books WHERE last_opened_at IS NOT NULL
      ORDER BY last_opened_at DESC, id DESC
    ''');
    for (final row in rows) {
      final book = _fromRow(row);
      if (_isManagedPath(book.localPath) &&
          File(book.localPath).existsSync()) return book;
    }
    return null;
  }

  /// Exists only in memory for the *current launch*, after startup has
  /// consumed any checkpoint left by a terminated prior process.
  /// A missing/deleted book never leaks an unusable recovery prompt.
  BookRecord? get interruptedNarrationBook {
    final bookId = _startupInterruptedBookId;
    if (bookId == null) return null;
    final book = getBook(bookId);
    if (book == null || !_isManagedPath(book.localPath) ||
        !File(book.localPath).existsSync()) return null;
    return book;
  }

  void dismissInterruptedNarration() {
    _startupInterruptedBookId = null;
  }

  /// Called only when the user opens a reader. It never grants TTS/LLM
  /// consent and intentionally doesn't change the saved reading anchor.
  Future<void> markBookOpened(String bookId) async {
    _database.execute('''
      UPDATE books SET last_opened_at = ? WHERE id = ?
    ''', [DateTime.now().toUtc().toIso8601String(), bookId]);
    if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
      throw StateError('Cannot resume an unknown book');
    }
    if (_startupInterruptedBookId == bookId) {
      _startupInterruptedBookId = null;
    }
  }

  /// The PDF renderer's page number, independent from speech/text offsets.
  /// Defaults to page one for a new/legacy PDF without a visual bookmark.
  int getPdfVisualPage(String bookId) {
    final rows = _database.select(
      "SELECT pdf_visual_page FROM books WHERE id = ? AND format = 'pdf'",
      [bookId],
    );
    if (rows.isEmpty) throw StateError('Unknown PDF book');
    return rows.first['pdf_visual_page'] as int? ?? 1;
  }

  /// Called only for a real page transition from the PDF viewer. This does
  /// not change saved read-aloud anchor, timestamp, or TTS authorization.
  void savePdfVisualPage(String bookId, int pageNumber) {
    if (pageNumber < 1 || pageNumber > 100000) {
      throw RangeError.range(pageNumber, 1, 100000, 'pageNumber');
    }
    _database.execute(
      "UPDATE books SET pdf_visual_page = ? "
      "WHERE id = ? AND format = 'pdf'",
      [pageNumber, bookId],
    );
    if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
      throw StateError('Unknown PDF book');
    }
  }

  /// Physical page bookmarks, including image-only/scanned PDFs.
  /// Always distinct from BookBookmark, TTS text positions and consent.
  List<PdfVisualBookmark> listPdfVisualBookmarks(String bookId) {
    final book = getBook(bookId);
    if (book == null || book.format != BookFormat.pdf) {
      throw StateError('Unknown PDF book for visual bookmarks');
    }
    final rows = _database.select('''
      SELECT id, book_id, title, page_number, created_at
      FROM pdf_visual_bookmarks
      WHERE book_id = ? ORDER BY page_number, created_at, id
    ''', [bookId]);
    return rows.map((row) => PdfVisualBookmark(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      title: row['title'] as String,
      pageNumber: row['page_number'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    )).toList();
  }

  void addPdfVisualBookmark(PdfVisualBookmark bookmark) {
    bookmark.validate();
    final book = getBook(bookmark.bookId);
    if (book == null || book.format != BookFormat.pdf) {
      throw StateError('Cannot visually bookmark a non-PDF book');
    }
    _database.execute('''
      INSERT INTO pdf_visual_bookmarks
        (id, book_id, title, page_number, created_at)
      VALUES (?, ?, ?, ?, ?)
    ''', [
      bookmark.id, bookmark.bookId, bookmark.title,
      bookmark.pageNumber, bookmark.createdAt.toUtc().toIso8601String(),
    ]);
  }

  void deletePdfVisualBookmark(String bookId, String bookmarkId) {
    if (getBook(bookId)?.format != BookFormat.pdf) {
      throw StateError('Unknown PDF book');
    }
    _database.execute(
      'DELETE FROM pdf_visual_bookmarks WHERE id = ? AND book_id = ?',
      [bookmarkId, bookId],
    );
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

      EpubCatalogMetadata? catalog;
      if (format == BookFormat.epub) {
        try {
          // Never block the UI isolate with OPF ZIP/XML parsing, and do not
          // require fully readable XHTML simply to import a book.
          catalog = await Isolate.run(
            () => const EpubCatalogMetadataReader().read(bytes),
            debugName: 'EReader EPUB catalog metadata',
          );
        } catch (_) {
          // EPUB signature alone does not guarantee readable OPF content.
          // Let the user import it under its filename; the reader's decoder
          // will report corruption when the file is opened.
        }
      }
      final record = BookRecord(
        id: id,
        title: catalog?.title ?? p.basenameWithoutExtension(displayName),
        author: catalog?.author,
        series: catalog?.series,
        language: catalog?.language,
        localPath: target.path,
        format: format,
        importedAt: DateTime.now().toUtc(),
      );
      _transaction(_database, () => _insert(_database, record));
      if (catalog != null) await _persistCover(id, catalog);
      return record;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  /// Synchronous and atomic: if Android kills the process after this
  /// returns, either the new source anchor AND the interrupted-session
  /// marker survive, or neither does. The player must call this *before*
  /// attempting native/cloud synthesis of each segment.
  void recordSpeechSegmentStart(String bookId, int offset,
      {ReadingAnchor? anchor}) {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    _transaction(_database, () {
      _database.execute(
        'UPDATE books SET progress_offset = ?, progress_anchor = ? '
        'WHERE id = ?',
        [offset, anchor == null ? null : jsonEncode(anchor.toJson()), bookId],
      );
      if ((_database.select('SELECT changes() AS n').first['n'] as int) != 1) {
        throw StateError('Cannot checkpoint speech for an unknown book');
      }
      _database.execute('''
        INSERT INTO speech_recovery_marker (slot, book_id, started_at)
        VALUES (1, ?, ?)
        ON CONFLICT(slot) DO UPDATE SET
          book_id = excluded.book_id, started_at = excluded.started_at
      ''', [bookId, DateTime.now().toUtc().toIso8601String()]);
    });
  }

  /// A normal user Pause, completed book, error or reader teardown is not
  /// a process crash. Only clear the matching book's checkpoint, so an old
  /// reader cannot erase a newer session after an asynchronous handoff.
  void clearSpeechRecoveryMarker(String bookId) {
    _database.execute(
      'DELETE FROM speech_recovery_marker WHERE book_id = ?', [bookId],
    );
  }

  Future<void> savePosition(String bookId, int offset,
      {ReadingAnchor? anchor}) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    _database.execute(
        'UPDATE books SET progress_offset = ?, progress_anchor = ? WHERE id = ?',
        [offset, anchor == null ? null : jsonEncode(anchor.toJson()), bookId]);
    if ((_database.select('SELECT changes() AS n').first['n'] as int) == 1) {
      _manualPositionRevisions[bookId] =
          manualPositionRevision(bookId) + 1;
    }
  }

  /// Includes global rules and (if supplied) rules for the specified book.
  /// This is intended to be read when opening a book or its settings editor.
  List<PronunciationRule> listPronunciationRules({String? bookId}) {
    final rows = bookId == null
        ? _database.select(
            'SELECT * FROM pronunciation_rules WHERE book_id IS NULL '
            'ORDER BY phrase COLLATE NOCASE, id')
        : _database.select(
            'SELECT * FROM pronunciation_rules '
            'WHERE book_id IS NULL OR book_id = ? '
            'ORDER BY book_id DESC, phrase COLLATE NOCASE, id', [bookId]);
    return rows.map((row) => PronunciationRule(
      id: row['id'] as String,
      bookId: row['book_id'] as String?,
      pattern: row['phrase'] as String,
      replacement: row['spoken_as'] as String,
      wholeWord: (row['whole_word'] as int) == 1,
      caseSensitive: (row['case_sensitive'] as int) == 1,
      enabled: (row['enabled'] as int) == 1,
    )).toList();
  }

  Future<void> upsertPronunciationRule(PronunciationRule rule) async {
    rule.validate();
    if (rule.bookId != null && getBook(rule.bookId!) == null) {
      throw StateError('Unknown book for pronunciation rule');
    }
    _database.execute('''
      INSERT INTO pronunciation_rules (
        id, book_id, phrase, spoken_as, whole_word, case_sensitive, enabled
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        book_id = excluded.book_id,
        phrase = excluded.phrase,
        spoken_as = excluded.spoken_as,
        whole_word = excluded.whole_word,
        case_sensitive = excluded.case_sensitive,
        enabled = excluded.enabled
    ''', [
      rule.id, rule.bookId, rule.pattern, rule.replacement,
      rule.wholeWord ? 1 : 0, rule.caseSensitive ? 1 : 0,
      rule.enabled ? 1 : 0,
    ]);
  }

  Future<void> deletePronunciationRule(String id) async {
    _database.execute('DELETE FROM pronunciation_rules WHERE id = ?', [id]);
  }

  /// Book preferences completely override global preferences when present.
  /// Secrets belong in secure storage, NEVER in this JSON blob.
  SpeechPreferences getSpeechPreferences({String? bookId}) {
    if (bookId != null) {
      final book = _database.select(
        'SELECT value_json FROM speech_preferences WHERE scope_id = ?',
        ['book:$bookId'],
      );
      if (book.isNotEmpty) return _decodeSpeechPrefs(book.first);
    }
    final global = _database.select(
      "SELECT value_json FROM speech_preferences WHERE scope_id = 'global'",
    );
    if (global.isNotEmpty) return _decodeSpeechPrefs(global.first);
    // Only the absence of BOTH persisted scopes permits auto-language.
    // Per-book and global voice choices always win, including their locale.
    // Never write this inferred language back to SQLite: future metadata
    // edits can then affect only books without an explicit speech profile.
    final inferred = bookId == null
        ? null
        : speechLocaleForBookMetadata(getBook(bookId)?.language);
    return inferred == null
        ? const SpeechPreferences()
        : const SpeechPreferences().copyWith(language: inferred);
  }

  Future<void> saveSpeechPreferences(SpeechPreferences preferences,
      {String? bookId}) async {
    preferences.validate();
    if (bookId != null && getBook(bookId) == null) {
      throw StateError('Unknown book for speech settings');
    }
    final scope = bookId == null ? 'global' : 'book:$bookId';
    _database.execute('''
      INSERT INTO speech_preferences (scope_id, value_json)
      VALUES (?, ?)
      ON CONFLICT(scope_id) DO UPDATE SET value_json = excluded.value_json
    ''', [scope, jsonEncode(preferences.toJson())]);
  }

  Future<void> clearBookSpeechPreferences(String bookId) async {
    _database.execute(
        'DELETE FROM speech_preferences WHERE scope_id = ?', ['book:$bookId']);
  }

  static SpeechPreferences _decodeSpeechPrefs(Row row) =>
      SpeechPreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['value_json'] as String) as Map),
      );

  /// A book's appearance overrides the global palette/typography.
  /// Visual settings are never mixed with TTS, model or cloud consent.
  ReadingPreferences getReadingPreferences({String? bookId}) {
    if (bookId != null) {
      final book = _database.select(
        'SELECT value_json FROM reading_preferences WHERE scope_id = ?',
        ['book:$bookId'],
      );
      if (book.isNotEmpty) {
        return _decodeReadingPrefs(book.first);
      }
    }
    final global = _database.select(
      "SELECT value_json FROM reading_preferences WHERE scope_id = 'global'",
    );
    return global.isEmpty
        ? const ReadingPreferences()
        : _decodeReadingPrefs(global.first);
  }

  void saveReadingPreferences(ReadingPreferences preferences,
      {String? bookId}) {
    preferences.validate();
    if (bookId != null && getBook(bookId) == null) {
      throw StateError('Unknown book for reading appearance');
    }
    final scope = bookId == null ? 'global' : 'book:$bookId';
    _database.execute('''
      INSERT INTO reading_preferences (scope_id, value_json)
      VALUES (?, ?)
      ON CONFLICT(scope_id) DO UPDATE SET value_json = excluded.value_json
    ''', [scope, jsonEncode(preferences.toJson())]);
  }

  void clearBookReadingPreferences(String bookId) {
    _database.execute(
      'DELETE FROM reading_preferences WHERE scope_id = ?',
      ['book:$bookId'],
    );
  }

  static ReadingPreferences _decodeReadingPrefs(Row row) =>
      ReadingPreferences.fromJson(
        Map<String, dynamic>.from(
            jsonDecode(row['value_json'] as String) as Map),
      );

  List<BookBookmark> listBookmarks(String bookId) {
    final rows = _database.select('''
      SELECT * FROM bookmarks
      WHERE book_id = ? ORDER BY created_at, id
    ''', [bookId]);
    return rows.map((row) => BookBookmark(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      title: row['title'] as String,
      globalOffset: row['global_offset'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      anchor: row['anchor_json'] is String
          ? ReadingAnchor.fromJson(Map<String, dynamic>.from(
              jsonDecode(row['anchor_json'] as String) as Map))
          : null,
    )).toList();
  }

  Future<void> addBookmark(BookBookmark bookmark) async {
    bookmark.validate();
    if (getBook(bookmark.bookId) == null) {
      throw StateError('Cannot bookmark an unknown book');
    }
    _database.execute('''
      INSERT INTO bookmarks (
        id, book_id, title, global_offset, anchor_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    ''', [
      bookmark.id, bookmark.bookId, bookmark.title,
      bookmark.globalOffset,
      bookmark.anchor == null ? null : jsonEncode(bookmark.anchor!.toJson()),
      bookmark.createdAt.toIso8601String(),
    ]);
  }

  Future<void> deleteBookmark(String id) async {
    _database.execute('DELETE FROM bookmarks WHERE id = ?', [id]);
  }

  @override
  CloudSpeechConsent getConsent(String bookId, String providerId) {
    final rows = _database.select('''
      SELECT * FROM cloud_speech_consent
      WHERE book_id = ? AND provider_id = ?
    ''', [bookId, providerId]);
    if (rows.isEmpty) {
      return CloudSpeechConsent(
        bookId: bookId,
        providerId: providerId,
        allowed: false,
        maxCharacters: 0,
        usedCharacters: 0,
      );
    }
    final row = rows.first;
    return CloudSpeechConsent(
      bookId: bookId,
      providerId: providerId,
      allowed: (row['allowed'] as int) == 1,
      maxCharacters: row['max_chars'] as int,
      usedCharacters: row['used_chars'] as int,
      approvedAt: row['approved_at'] is String
          ? DateTime.parse(row['approved_at'] as String)
          : null,
    );
  }

  /// Explicit user action only. Re-authorizing never resets consumed quota.
  /// Disabled means NO API request can be made, even if a key exists.
  Future<void> configureCloudConsent(
    String bookId,
    String providerId, {
    required bool allowed,
    required int maxCharacters,
  }) async {
    if (providerId != 'openai-speech' || getBook(bookId) == null) {
      throw StateError('Unknown book or unsupported cloud provider');
    }
    if (maxCharacters < 0 || maxCharacters > 10000000) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters');
    }
    _transaction(_database, () {
      _database.execute('''
        INSERT INTO cloud_speech_consent (
          book_id, provider_id, allowed, max_chars, used_chars, approved_at
        ) VALUES (?, ?, ?, ?, 0, ?)
        ON CONFLICT(book_id, provider_id) DO UPDATE SET
          allowed = excluded.allowed,
          max_chars = excluded.max_chars,
          approved_at = excluded.approved_at
        WHERE cloud_speech_consent.used_chars <= excluded.max_chars
      ''', [
        bookId, providerId, allowed ? 1 : 0, maxCharacters,
        allowed ? DateTime.now().toUtc().toIso8601String() : null,
      ]);
      final changed = _database.select('SELECT changes() AS n')
          .first['n'] as int;
      if (changed != 1) {
        throw StateError('Budget cannot be less than already used characters');
      }
    });
  }

  /// Reserves BEFORE sending text, including requests that later fail.
  /// The comparison and increment are one atomic SQLite transaction, so
  /// concurrent providers cannot accidentally exceed the local hard limit.
  @override
  Future<void> reserveCharacters(
    String bookId, String providerId, int characters,
  ) async {
    if (characters <= 0 || characters > 4096) {
      throw ArgumentError.value(characters, 'characters');
    }
    _transaction(_database, () {
      _database.execute('''
        UPDATE cloud_speech_consent
        SET used_chars = used_chars + ?
        WHERE book_id = ? AND provider_id = ? AND allowed = 1
          AND max_chars - used_chars >= ?
      ''', [characters, bookId, providerId, characters]);
      final changed = _database.select('SELECT changes() AS n')
          .first['n'] as int;
      if (changed != 1) {
        throw const CloudSpeechBlocked(
          'No explicit book consent or character budget exhausted',
        );
      }
    });
  }

  /// Separate privacy gate from cloud speech. Nothing is authorized by
  /// default, even when the user already enabled paid cloud narration.
  @override
  LlmAnalysisConsent getLlmAnalysisConsent(String bookId) {
    final rows = _database.select('''
      SELECT * FROM llm_analysis_consent WHERE book_id = ?
    ''', [bookId]);
    if (rows.isEmpty) {
      return LlmAnalysisConsent(bookId: bookId, allowed: false,
          maxInputCharacters: 0, usedInputCharacters: 0);
    }
    final row = rows.first;
    return LlmAnalysisConsent(
      bookId: bookId,
      allowed: (row['allowed'] as int) == 1,
      maxInputCharacters: row['max_input_chars'] as int,
      usedInputCharacters: row['used_input_chars'] as int,
      approvedAt: row['approved_at'] is String
          ? DateTime.parse(row['approved_at'] as String)
          : null,
    );
  }

  /// Only invoked after a distinct explicit user permission dialog.
  /// Updating limits does not reset earlier usage. False is a hard revoke.
  Future<void> configureLlmAnalysisConsent(String bookId, {
    required bool allowed,
    required int maxInputCharacters,
  }) async {
    if (getBook(bookId) == null) throw StateError('Unknown analysis book');
    if (maxInputCharacters < 0 || maxInputCharacters > 10000000) {
      throw ArgumentError.value(maxInputCharacters, 'maxInputCharacters');
    }
    _transaction(_database, () {
      _database.execute('''
        INSERT INTO llm_analysis_consent (
          book_id, allowed, max_input_chars, used_input_chars, approved_at
        ) VALUES (?, ?, ?, 0, ?)
        ON CONFLICT(book_id) DO UPDATE SET
          allowed = excluded.allowed,
          max_input_chars = excluded.max_input_chars,
          approved_at = excluded.approved_at
        WHERE llm_analysis_consent.used_input_chars <=
              excluded.max_input_chars
      ''', [
        bookId, allowed ? 1 : 0, maxInputCharacters,
        allowed ? DateTime.now().toUtc().toIso8601String() : null,
      ]);
      if ((_database.select('SELECT changes() AS n')
              .first['n'] as int) != 1) {
        throw StateError('Limit is below previously reserved input');
      }
    });
  }

  /// Reserve BEFORE HTTPS. Conservative local character-count budget, not
  /// a token or monetary cap. Failed and timed-out requests are counted.
  @override
  Future<void> reserveLlmAnalysisInput(
      String bookId, int characters) async {
    if (characters <= 0 || characters > 20000) {
      throw ArgumentError.value(characters, 'characters');
    }
    _transaction(_database, () {
      _database.execute('''
        UPDATE llm_analysis_consent
        SET used_input_chars = used_input_chars + ?
        WHERE book_id = ? AND allowed = 1
          AND max_input_chars - used_input_chars >= ?
      ''', [characters, bookId, characters]);
      if ((_database.select('SELECT changes() AS n')
              .first['n'] as int) != 1) {
        throw const LlmAnalysisDenied(
          'Approval missing or input-character limit reached',
        );
      }
    });
  }

  List<CharacterCandidate> listCharacterCandidates(String bookId) {
    return _database.select('''
      SELECT * FROM character_candidates
      WHERE book_id = ? ORDER BY mention_start, id
    ''', [bookId]).map((row) => CharacterCandidate(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      name: row['proposed_name'] as String,
      start: row['mention_start'] as int,
      end: row['mention_end'] as int,
      sourceDigest: row['source_sha256'] as String,
      confidence: (row['confidence'] as num).toDouble(),
      status: CharacterCandidateStatus.values.byName(
          row['status'] as String),
      createdCharacterId: row['created_character_id'] as String?,
    )).toList();
  }

  /// Untrusted model output enters a separate pending-only queue.
  /// Import never modifies the roster or assigns a voice.
  Future<void> importCharacterCandidates(
    List<CharacterCandidate> candidates, String source,
  ) async {
    if (candidates.length > 60) {
      throw const FormatException('Too many character suggestions');
    }
    _transaction(_database, () {
      for (final candidate in candidates) {
        candidate.validate();
        if (candidate.status != CharacterCandidateStatus.proposed ||
            candidate.createdCharacterId != null ||
            !candidate.matchesSource(source)) {
          throw const FormatException('Candidate is not pending/source-aligned');
        }
        if (getBook(candidate.bookId) == null) {
          throw StateError('Character suggestion belongs to unknown book');
        }
        final roster = listCastCharacters(candidate.bookId);
        final existing = <String>[
          for (final person in roster) person.name,
          for (final person in roster) ...person.aliases,
        ];
        if (candidateConflictsWithCast(candidate.name, existing)) continue;
        // Do not silently regenerate the same proposed character from
        // another chapter; let the user review an existing pending row.
        final duplicates = listCharacterCandidates(candidate.bookId);
        if (duplicates.any((other) =>
            other.status == CharacterCandidateStatus.proposed &&
            CharacterCandidate.normalizeName(other.name) ==
                CharacterCandidate.normalizeName(candidate.name))) continue;
        _database.execute('''
          INSERT OR IGNORE INTO character_candidates (
            id, book_id, proposed_name, mention_start, mention_end,
            source_sha256, confidence, status
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 'proposed')
        ''', [
          candidate.id, candidate.bookId, candidate.name,
          candidate.start, candidate.end,
          candidate.sourceDigest, candidate.confidence,
        ]);
      }
    });
  }

  /// Explicit user review is the ONLY path from candidate to cast member.
  /// The transaction ensures a crash cannot create a person without
  /// consuming the corresponding review decision (or vice versa).
  Future<void> reviewCharacterCandidate(
    String candidateId, {
    required bool approve,
    required String source,
    String? displayName,
    String? newCharacterId,
  }) async {
    _transaction(_database, () {
      final rows = _database.select(
        'SELECT book_id FROM character_candidates WHERE id = ?',
        [candidateId],
      );
      if (rows.isEmpty) throw StateError('Unknown character suggestion');
      final bookId = rows.first['book_id'] as String;
      final candidates = listCharacterCandidates(bookId);
      final candidate = candidates.firstWhere((c) => c.id == candidateId);
      if (candidate.status != CharacterCandidateStatus.proposed) {
        throw StateError('Character suggestion was already reviewed');
      }
      // Stale, edited source is a reason to reject the candidate; it
      // must never block the user from clearing an obsolete proposal.
      if (!approve) {
        _database.execute('''
          UPDATE character_candidates SET status = 'rejected'
          WHERE id = ? AND status = 'proposed'
        ''', [candidateId]);
        return;
      }
      if (!candidate.matchesSource(source)) {
        throw const FormatException(
            'Original character mention changed; cannot approve');
      }
      if (displayName == null || newCharacterId == null) {
        throw const FormatException('Approved person needs confirmed name/ID');
      }
      final person = CastCharacter(
        id: newCharacterId,
        bookId: bookId,
        name: displayName.trim(),
      );
      person.validate();
      final roster = listCastCharacters(bookId);
      final names = <String>[
        for (final member in roster) member.name,
        for (final member in roster) ...member.aliases,
      ];
      if (candidateConflictsWithCast(person.name, names)) {
        throw StateError('Character name or alias already exists in the cast');
      }
      _database.execute('''
        INSERT INTO cast_characters (
          id, book_id, display_name, aliases_json
        ) VALUES (?, ?, ?, '[]')
      ''', [person.id, person.bookId, person.name]);
      _database.execute('''
        UPDATE character_candidates
        SET status = 'accepted', created_character_id = ?
        WHERE id = ? AND status = 'proposed'
      ''', [person.id, candidateId]);
    });
  }

  /// Indirect narrative references are metadata only. They are NEVER queried
  /// by the playback resolver or automatically imported into cast_spans.
  List<NarrativeReferenceCandidate> listNarrativeReferences(String bookId) {
    return _database.select('''
      SELECT * FROM narrative_references
      WHERE book_id = ? ORDER BY mention_start, id
    ''', [bookId]).map((row) => NarrativeReferenceCandidate(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      start: row['mention_start'] as int,
      end: row['mention_end'] as int,
      referenceText: row['mention_text'] as String,
      sourceDigest: row['source_sha256'] as String,
      kind: NarrativeReferenceKind.values.byName(
          row['mention_kind'] as String),
      proposedCharacterId: row['proposed_character_id'] as String?,
      approvedCharacterId: row['approved_character_id'] as String?,
      confidence: (row['confidence'] as num).toDouble(),
      ambiguous: (row['ambiguous'] as int) == 1,
      status: NarrativeReferenceStatus.values.byName(row['status'] as String),
      evidence: row['evidence_json'] is String
          ? CastSpanEvidence.fromJson(Map<String, dynamic>.from(
              jsonDecode(row['evidence_json'] as String) as Map))
          : null,
    )).toList();
  }

  Future<void> importNarrativeReferences(
      List<NarrativeReferenceCandidate> proposals, String source) async {
    if (proposals.length > 80) {
      throw const FormatException('Too many reference proposals');
    }
    _transaction(_database, () {
      for (final proposal in proposals) {
        proposal.validate();
        if (proposal.status != NarrativeReferenceStatus.proposed ||
            proposal.approvedCharacterId != null ||
            !proposal.matchesSource(source)) {
          throw const FormatException('Reference is not pending/source-exact');
        }
        if (getBook(proposal.bookId) == null) {
          throw StateError('Reference belongs to a missing book');
        }
        if (proposal.proposedCharacterId != null &&
            !listCastCharacters(proposal.bookId).any(
              (person) => person.id == proposal.proposedCharacterId)) {
          throw StateError('Referenced person is absent from this book');
        }
        // One review record per source position. Re-running analysis must
        // never silently overwrite a prior human decision or model conflict.
        _database.execute('''
          INSERT OR IGNORE INTO narrative_references (
            id, book_id, mention_start, mention_end, mention_text,
            source_sha256, mention_kind, proposed_character_id,
            confidence, ambiguous, evidence_json, status
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'proposed')
        ''', [
          proposal.id, proposal.bookId, proposal.start, proposal.end,
          proposal.referenceText, proposal.sourceDigest, proposal.kind.name,
          proposal.proposedCharacterId, proposal.confidence,
          proposal.ambiguous ? 1 : 0,
          proposal.evidence == null
              ? null : jsonEncode(proposal.evidence!.toJson()),
        ]);
      }
    });
  }

  /// Explicit approval links a narrative mention to a reviewed character.
  /// This does NOT touch cast_spans, segment_cast or voice settings.
  Future<void> reviewNarrativeReference(String proposalId, {
    required bool approve,
    required String source,
    String? confirmedCharacterId,
  }) async {
    _transaction(_database, () {
      final matches = _database.select('''
        SELECT book_id FROM narrative_references WHERE id = ?
      ''', [proposalId]);
      if (matches.isEmpty) throw StateError('Unknown narrative reference');
      final bookId = matches.single['book_id'] as String;
      final proposal = listNarrativeReferences(bookId)
          .firstWhere((item) => item.id == proposalId);
      if (proposal.status != NarrativeReferenceStatus.proposed) {
        throw StateError('Narrative reference already reviewed');
      }
      if (!approve) {
        _database.execute('''
          UPDATE narrative_references SET status = 'rejected'
          WHERE id = ? AND status = 'proposed'
        ''', [proposalId]);
        return; // Even stale proposals can be cleared from the review queue.
      }
      if (!proposal.matchesSource(source)) {
        throw const FormatException('Reference or supporting quote is stale');
      }
      if (confirmedCharacterId == null ||
          !listCastCharacters(bookId).any(
              (person) => person.id == confirmedCharacterId)) {
        throw StateError('Select an existing person from this book');
      }
      _database.execute('''
        UPDATE narrative_references
        SET status = 'accepted', approved_character_id = ?
        WHERE id = ? AND status = 'proposed'
      ''', [confirmedCharacterId, proposalId]);
    });
  }

  List<AliasCandidate> listAliasCandidates(String bookId) {
    return _database.select('''
      SELECT * FROM alias_candidates
      WHERE book_id = ? ORDER BY mention_start, id
    ''', [bookId]).map((row) => AliasCandidate(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      alias: row['alias_text'] as String,
      targetCharacterId: (row['status'] as String) == 'accepted'
          ? row['approved_character_id'] as String?
          : row['suggested_character_id'] as String?,
      start: row['mention_start'] as int,
      end: row['mention_end'] as int,
      sourceDigest: row['source_sha256'] as String,
      confidence: (row['confidence'] as num).toDouble(),
      status: AliasCandidateStatus.values.byName(row['status'] as String),
      evidence: row['evidence_json'] is String
          ? CastSpanEvidence.fromJson(Map<String, dynamic>.from(
              jsonDecode(row['evidence_json'] as String) as Map))
          : null,
    )).toList();
  }

  /// The model can populate a *pending* queue, never the character roster.
  Future<void> importAliasCandidates(
      List<AliasCandidate> candidates, String source) async {
    if (candidates.length > 60) {
      throw const FormatException('Too many alias suggestions');
    }
    _transaction(_database, () {
      for (final alias in candidates) {
        alias.validate();
        if (alias.status != AliasCandidateStatus.proposed ||
            !alias.matchesSource(source) || alias.targetCharacterId == null) {
          throw const FormatException('Alias must be pending and source-exact');
        }
        final people = listCastCharacters(alias.bookId);
        final target = people.where((c) => c.id == alias.targetCharacterId);
        if (target.isEmpty) {
          throw StateError('Suggested character does not belong to this book');
        }
        final taken = <String>[
          for (final person in people) person.name,
          for (final person in people) ...person.aliases,
        ];
        if (candidateConflictsWithCast(alias.alias, taken)) continue;
        // Cross-window disagreement is not automatically resolved.
        final sameAlias = listAliasCandidates(alias.bookId)
            .where((p) => p.status == AliasCandidateStatus.proposed &&
              CharacterCandidate.normalizeName(p.alias) ==
                  CharacterCandidate.normalizeName(alias.alias));
        if (sameAlias.isNotEmpty) {
          if (sameAlias.any((p) =>
              p.targetCharacterId != alias.targetCharacterId)) {
            throw StateError('Conflicting proposed owners for this alias');
          }
          continue;
        }
        _database.execute('''
          INSERT OR IGNORE INTO alias_candidates (
            id, book_id, alias_text, suggested_character_id,
            mention_start, mention_end, source_sha256, evidence_json,
            confidence, status
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'proposed')
        ''', [
          alias.id, alias.bookId, alias.alias, alias.targetCharacterId,
          alias.start, alias.end, alias.sourceDigest,
          alias.evidence == null ? null : jsonEncode(alias.evidence!.toJson()),
          alias.confidence,
        ]);
      }
    });
  }

  /// Single atomic user decision. No alias may silently claim the name or
  /// existing alias of a different person; the confirmed target must belong
  /// to the same book and must still exist at review time.
  Future<void> reviewAliasCandidate(String candidateId, {
    required bool approve,
    required String source,
    String? confirmedCharacterId,
  }) async {
    _transaction(_database, () {
      final entries = _database.select('''
        SELECT book_id FROM alias_candidates WHERE id = ?
      ''', [candidateId]);
      if (entries.isEmpty) throw StateError('Unknown alias suggestion');
      final bookId = entries.first['book_id'] as String;
      final alias = listAliasCandidates(bookId)
          .firstWhere((p) => p.id == candidateId);
      if (alias.status != AliasCandidateStatus.proposed) {
        throw StateError('Alias suggestion already reviewed');
      }
      if (!approve) {
        _database.execute('''
          UPDATE alias_candidates SET status = 'rejected'
          WHERE id = ? AND status = 'proposed'
        ''', [candidateId]);
        return;
      }
      if (!alias.matchesSource(source)) {
        throw const FormatException('Alias mention or evidence changed');
      }
      final targetId = confirmedCharacterId;
      if (targetId == null) {
        throw const FormatException('Choose an existing character for alias');
      }
      final characters = listCastCharacters(bookId);
      CastCharacter? target;
      for (final character in characters) {
        if (character.id == targetId) target = character;
      }
      if (target == null) {
        throw StateError('Alias owner is not a current book character');
      }
      final allNames = <String>[
        for (final character in characters) character.name,
        for (final character in characters) ...character.aliases,
      ];
      if (candidateConflictsWithCast(alias.alias, allNames)) {
        throw StateError('Name/alias already in use in this book');
      }
      if (target.aliases.length >= 50) {
        throw StateError('Maximum number of character aliases reached');
      }
      final merged = [...target.aliases, alias.alias];
      _database.execute('''
        UPDATE cast_characters SET aliases_json = ?
        WHERE id = ? AND book_id = ?
      ''', [jsonEncode(merged), target.id, bookId]);
      _database.execute('''
        UPDATE alias_candidates
        SET status = 'accepted', approved_character_id = ?
        WHERE id = ? AND status = 'proposed'
      ''', [target.id, candidateId]);
    });
  }

  int _mergeReferenceCount(String table, String column, String id) {
    // Only call with fixed, developer-owned column names, never with user text.
    return _database.select('SELECT COUNT(*) AS n FROM $table '
        'WHERE $column = ?', [id]).first['n'] as int;
  }

  /// Include the identity, source hash and review state of every dependent
  /// row in the optimistic preview. Counts alone are insufficient: a speaker
  /// label can change without affecting the number of rows.
  Map<String, Object> _mergeReferencedSnapshot(
      String sourceId, String targetId) => {
    'legacy': [
      for (final row in _database.select('''
        SELECT book_id, start_offset, end_offset, source_sha256,
               character_id, anchor_json
        FROM segment_cast WHERE character_id IN (?, ?)
        ORDER BY book_id, start_offset, end_offset
      ''', [sourceId, targetId]))
        [row['book_id'], row['start_offset'], row['end_offset'],
         row['source_sha256'], row['character_id'], row['anchor_json']],
    ],
    'fine': [
      for (final row in _database.select('''
        SELECT id, start_offset, end_offset, speaker_id,
               source_sha256, status, locked_by_user
        FROM cast_spans WHERE speaker_id IN (?, ?) ORDER BY id
      ''', [sourceId, targetId]))
        [row['id'], row['start_offset'], row['end_offset'],
         row['speaker_id'], row['source_sha256'], row['status'],
         row['locked_by_user']],
    ],
    'discoveries': [
      for (final row in _database.select('''
        SELECT id, status, created_character_id FROM character_candidates
        WHERE created_character_id IN (?, ?) ORDER BY id
      ''', [sourceId, targetId]))
        [row['id'], row['status'], row['created_character_id']],
    ],
    'aliasLinks': [
      for (final row in _database.select('''
        SELECT id, status, alias_text, suggested_character_id,
               approved_character_id
        FROM alias_candidates
        WHERE suggested_character_id IN (?, ?) OR
              approved_character_id IN (?, ?)
        ORDER BY id
      ''', [sourceId, targetId, sourceId, targetId]))
        [row['id'], row['status'], row['alias_text'],
         row['suggested_character_id'], row['approved_character_id']],
    ],
    'narrativeReferences': [
      for (final row in _database.select('''
        SELECT id, status, mention_start, mention_end, source_sha256,
               proposed_character_id, approved_character_id
        FROM narrative_references
        WHERE proposed_character_id IN (?, ?) OR
              approved_character_id IN (?, ?)
        ORDER BY id
      ''', [sourceId, targetId, sourceId, targetId]))
        [row['id'], row['status'], row['mention_start'], row['mention_end'],
         row['source_sha256'], row['proposed_character_id'],
         row['approved_character_id']],
    ],
  };

  /// Recompute a full book-scoped preview without writing any cast data.
  /// The two identities must already belong to this exact book.
  CastMergePreview previewCastMerge(
    String bookId, String sourceId, String targetId,
  ) {
    if (sourceId == targetId) {
      throw const FormatException('Choose two different characters');
    }
    final people = listCastCharacters(bookId);
    CastCharacter? source, target;
    for (final person in people) {
      if (person.id == sourceId) source = person;
      if (person.id == targetId) target = person;
    }
    if (source == null || target == null) {
      throw StateError('Both characters must belong to the same book');
    }

    final combined = <String>[];
    final normalized = <String>{
      CharacterCandidate.normalizeName(target.name),
    };
    for (final alias in [
      ...target.aliases, source.name, ...source.aliases,
    ]) {
      final key = CharacterCandidate.normalizeName(alias);
      if (normalized.add(key)) combined.add(alias);
    }
    if (combined.length > 50) {
      throw StateError('Merge exceeds maximum of 50 aliases');
    }
    for (final other in people) {
      if (other.id == sourceId || other.id == targetId) continue;
      final taken = <String>[
        other.name, ...other.aliases,
      ];
      for (final name in taken) {
        if (normalized.contains(CharacterCandidate.normalizeName(name))) {
          throw StateError('Alias conflicts with another surviving character');
        }
      }
    }

    final voices = listCastVoices(bookId);
    final srcVoices = {
      for (final voice in voices)
        if (voice.characterId == sourceId) voice.providerId: voice,
    };
    final dstVoices = {
      for (final voice in voices)
        if (voice.characterId == targetId) voice.providerId: voice,
    };
    final conflicts = <CastMergeVoiceConflict>[];
    for (final entry in srcVoices.entries) {
      final dst = dstVoices[entry.key];
      if (dst != null &&
          (dst.voiceName != entry.value.voiceName ||
           dst.voiceLocale != entry.value.voiceLocale)) {
        conflicts.add(CastMergeVoiceConflict(
          providerId: entry.key, source: entry.value, target: dst,
        ));
      }
    }
    conflicts.sort((a, b) => a.providerId.compareTo(b.providerId));

    final counts = <String, int>{
      'dialogue_segments': _mergeReferenceCount(
          'segment_cast', 'character_id', sourceId),
      'precise_spans': _mergeReferenceCount(
          'cast_spans', 'speaker_id', sourceId),
      'reviewed_character_candidates': _mergeReferenceCount(
          'character_candidates', 'created_character_id', sourceId),
      'proposed_alias_links': _mergeReferenceCount(
          'alias_candidates', 'suggested_character_id', sourceId),
      'approved_alias_links': _mergeReferenceCount(
          'alias_candidates', 'approved_character_id', sourceId),
      'proposed_narrative_references': _mergeReferenceCount(
          'narrative_references', 'proposed_character_id', sourceId),
      'approved_narrative_references': _mergeReferenceCount(
          'narrative_references', 'approved_character_id', sourceId),
      'provider_voices': srcVoices.length,
    };

    // Optimistic fingerprint stops an old confirmation from merging after
    // someone edits names/voices or adds dependent references meanwhile.
    final snapshot = jsonEncode({
      'book': bookId,
      'from': sourceId, 'into': targetId,
      'roster': [
        for (final person in people)
          [person.id, person.name, ...person.aliases],
      ],
      'voices': [
        for (final voice in voices)
          [voice.characterId, voice.providerId,
           voice.voiceName, voice.voiceLocale],
      ],
      'counts': counts,
      'reference_rows': _mergeReferencedSnapshot(sourceId, targetId),
    });
    return CastMergePreview(
      source: source, target: target,
      resultingAliases: List.unmodifiable(combined),
      providerConflicts: List.unmodifiable(conflicts),
      counts: Map.unmodifiable(counts),
      snapshotDigest: sha256.convert(utf8.encode(snapshot)).toString(),
    );
  }

  /// Transactional merge: retain target identity and its saved narrator
  /// bindings; retarget ALL known foreign keys before deleting source.
  /// Conflicting timbres are never resolved without explicit choices.
  Future<CastMergeResult> mergeCastCharacters(
      CastMergeDecision decision) async {
    late CastMergeResult completed;
    _transaction(_database, () {
      final current = previewCastMerge(
        decision.bookId,
        decision.sourceCharacterId,
        decision.targetCharacterId,
      );
      if (current.snapshotDigest != decision.expectedSnapshotDigest) {
        throw StateError('Cast changed after preview: review merge again');
      }
      final expected = {
        for (final conflict in current.providerConflicts)
          conflict.providerId,
      };
      if (decision.providerChoices.length != expected.length ||
          decision.providerChoices.keys.any((key) => !expected.contains(key)) ||
          decision.providerChoices.values.any(
              (value) => value != 'source' && value != 'target')) {
        throw StateError('Choose which voice to retain for every conflict');
      }

      final sourceId = decision.sourceCharacterId;
      final targetId = decision.targetCharacterId;
      final previousVoices = listCastVoices(decision.bookId);
      final targetByProvider = {
        for (final voice in previousVoices)
          if (voice.characterId == targetId) voice.providerId: voice,
      };
      for (final voice in previousVoices) {
        if (voice.characterId != sourceId) continue;
        final currentTarget = targetByProvider[voice.providerId];
        if (currentTarget != null &&
            (currentTarget.voiceName != voice.voiceName ||
             currentTarget.voiceLocale != voice.voiceLocale) &&
            decision.providerChoices[voice.providerId] != 'source') {
          continue; // User explicitly chose the target provider voice.
        }
        // Equal voices or provider available only on source are preserved.
        _database.execute('''
          INSERT INTO cast_voices(
            character_id, provider_id, voice_name, voice_locale
          ) VALUES (?, ?, ?, ?)
          ON CONFLICT(character_id, provider_id) DO UPDATE SET
            voice_name = excluded.voice_name,
            voice_locale = excluded.voice_locale
        ''', [targetId, voice.providerId, voice.voiceName, voice.voiceLocale]);
      }

      _database.execute('''
        UPDATE cast_characters SET aliases_json = ?
        WHERE id = ? AND book_id = ?
      ''', [jsonEncode(current.resultingAliases), targetId, decision.bookId]);
      _database.execute('''
        UPDATE segment_cast SET character_id = ?
        WHERE book_id = ? AND character_id = ?
      ''', [targetId, decision.bookId, sourceId]);
      _database.execute('''
        UPDATE cast_spans SET speaker_id = ?
        WHERE book_id = ? AND speaker_id = ?
      ''', [targetId, decision.bookId, sourceId]);
      _database.execute('''
        UPDATE character_candidates SET created_character_id = ?
        WHERE book_id = ? AND created_character_id = ?
      ''', [targetId, decision.bookId, sourceId]);
      _database.execute('''
        UPDATE alias_candidates SET suggested_character_id = ?
        WHERE book_id = ? AND suggested_character_id = ?
      ''', [targetId, decision.bookId, sourceId]);
      _database.execute('''
        UPDATE alias_candidates SET approved_character_id = ?
        WHERE book_id = ? AND approved_character_id = ?
      ''', [targetId, decision.bookId, sourceId]);
      _database.execute('''
        UPDATE narrative_references SET proposed_character_id = ?
        WHERE book_id = ? AND proposed_character_id = ?
      ''', [targetId, decision.bookId, sourceId]);
      _database.execute('''
        UPDATE narrative_references SET approved_character_id = ?
        WHERE book_id = ? AND approved_character_id = ?
      ''', [targetId, decision.bookId, sourceId]);

      // Only the old character and the old voice rows cascade-delete:
      // all documented references were retargeted above.
      _database.execute('''
        DELETE FROM cast_characters WHERE id = ? AND book_id = ?
      ''', [sourceId, decision.bookId]);
      if ((_database.select('SELECT changes() AS n')
             .first['n'] as int) != 1) {
        throw StateError('Merge failed to delete exactly one old identity');
      }

      _database.execute('''
        INSERT INTO cast_merges(
          book_id, old_character_id, kept_character_id,
          old_name, kept_name, snapshot_sha256,
          voice_choices_json, updated_records_json, merged_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        decision.bookId, sourceId, targetId,
        current.source.name, current.target.name,
        current.snapshotDigest, jsonEncode(decision.providerChoices),
        jsonEncode(current.counts),
        DateTime.now().toUtc().toIso8601String(),
      ]);
      completed = CastMergeResult(
        mergedName: current.target.name,
        keptCharacterId: targetId,
        movedRecordCount: current.counts.values.fold<int>(
            0, (total, count) => total + count),
      );
    });
    return completed;
  }

  /// Manual character roster; not an automatic character detector.
  List<CastCharacter> listCastCharacters(String bookId) {
    return _database.select('''
      SELECT * FROM cast_characters
      WHERE book_id = ? ORDER BY display_name COLLATE NOCASE, id
    ''', [bookId]).map((row) => CastCharacter(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      name: row['display_name'] as String,
      aliases: List<String>.from(
        jsonDecode(row['aliases_json'] as String) as List),
    )).toList();
  }

  Future<void> saveCastCharacter(CastCharacter character) async {
    character.validate();
    _transaction(_database, () {
      if (getBook(character.bookId) == null) {
        throw StateError('Unknown book for cast character');
      }
      final exists = _database.select(
        'SELECT book_id FROM cast_characters WHERE id = ?', [character.id]);
      if (exists.isNotEmpty &&
          exists.first['book_id'] != character.bookId) {
        throw StateError('Cannot move character between books');
      }
      final normalized = <String>{};
      for (final name in [character.name, ...character.aliases]) {
        final token = CharacterCandidate.normalizeName(name);
        if (token.isEmpty || !normalized.add(token)) {
          throw const FormatException('Duplicate name or alias on character');
        }
      }
      for (final other in listCastCharacters(character.bookId)) {
        if (other.id == character.id) continue;
        for (final occupied in [other.name, ...other.aliases]) {
          if (normalized.contains(
              CharacterCandidate.normalizeName(occupied))) {
            throw StateError('Name or alias belongs to another character');
          }
        }
      }
      _database.execute('''
        INSERT INTO cast_characters (id, book_id, display_name, aliases_json)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          display_name = excluded.display_name,
          aliases_json = excluded.aliases_json
      ''', [
        character.id, character.bookId, character.name,
        jsonEncode(character.aliases),
      ]);
    });
  }

  Future<void> deleteCastCharacter(String characterId) async {
    // SQLite foreign-key cascade removes affected voice and speaker
    // assignments; those segments automatically revert to narrator.
    _database.execute('DELETE FROM cast_characters WHERE id = ?',
        [characterId]);
  }

  List<CastVoiceAssignment> listCastVoices(String bookId) {
    return _database.select('''
      SELECT v.* FROM cast_voices v
      JOIN cast_characters c ON v.character_id = c.id
      WHERE c.book_id = ?
      ORDER BY v.character_id, v.provider_id
    ''', [bookId]).map((row) => CastVoiceAssignment(
      characterId: row['character_id'] as String,
      providerId: row['provider_id'] as String,
      voiceName: row['voice_name'] as String,
      voiceLocale: row['voice_locale'] as String,
    )).toList();
  }

  Future<void> saveCastVoice(CastVoiceAssignment voice) async {
    voice.validate();
    final exists = _database.select(
      'SELECT id FROM cast_characters WHERE id = ?',
      [voice.characterId],
    );
    if (exists.isEmpty) throw StateError('Unknown cast character');
    _database.execute('''
      INSERT INTO cast_voices (
        character_id, provider_id, voice_name, voice_locale
      ) VALUES (?, ?, ?, ?)
      ON CONFLICT(character_id, provider_id) DO UPDATE SET
        voice_name = excluded.voice_name,
        voice_locale = excluded.voice_locale
    ''', [
      voice.characterId, voice.providerId,
      voice.voiceName, voice.voiceLocale,
    ]);
  }

  Future<void> deleteCastVoice(String characterId, String providerId) async {
    _database.execute('''
      DELETE FROM cast_voices
      WHERE character_id = ? AND provider_id = ?
    ''', [characterId, providerId]);
  }

  List<SegmentCastAssignment> listSegmentCast(String bookId) {
    return _database.select('''
      SELECT * FROM segment_cast
      WHERE book_id = ? ORDER BY start_offset, end_offset
    ''', [bookId]).map((row) => SegmentCastAssignment(
      bookId: row['book_id'] as String,
      start: row['start_offset'] as int,
      end: row['end_offset'] as int,
      sourceDigest: row['source_sha256'] as String,
      characterId: row['character_id'] as String,
      anchor: row['anchor_json'] is String
          ? ReadingAnchor.fromJson(Map<String, dynamic>.from(
              jsonDecode(row['anchor_json'] as String) as Map))
          : null,
    )).toList();
  }

  Future<void> saveSegmentCast(SegmentCastAssignment attribution) async {
    attribution.validate();
    if (getBook(attribution.bookId) == null) {
      throw StateError('Unknown book for segment attribution');
    }
    final character = _database.select('''
      SELECT book_id FROM cast_characters WHERE id = ?
    ''', [attribution.characterId]);
    if (character.isEmpty ||
        character.first['book_id'] != attribution.bookId) {
      throw StateError('Speaker must belong to the same book');
    }
    _database.execute('''
      INSERT INTO segment_cast (
        book_id, start_offset, end_offset, source_sha256,
        character_id, anchor_json
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(book_id, start_offset, end_offset) DO UPDATE SET
        source_sha256 = excluded.source_sha256,
        character_id = excluded.character_id,
        anchor_json = excluded.anchor_json
    ''', [
      attribution.bookId, attribution.start, attribution.end,
      attribution.sourceDigest, attribution.characterId,
      attribution.anchor == null ? null : jsonEncode(attribution.anchor!.toJson()),
    ]);
  }

  Future<void> deleteSegmentCast(
      String bookId, int start, int end) async {
    _database.execute('''
      DELETE FROM segment_cast
      WHERE book_id = ? AND start_offset = ? AND end_offset = ?
    ''', [bookId, start, end]);
  }

  /// Fine-grained manual labels and future *unapproved* LLM suggestions.
  List<CastSpan> listCastSpans(String bookId) {
    final rows = _database.select('''
      SELECT * FROM cast_spans
      WHERE book_id = ? ORDER BY start_offset, end_offset, id
    ''', [bookId]);
    return rows.map((row) => CastSpan(
      id: row['id'] as String,
      bookId: row['book_id'] as String,
      start: row['start_offset'] as int,
      end: row['end_offset'] as int,
      sourceDigest: row['source_sha256'] as String,
      speakerId: row['speaker_id'] as String?,
      origin: CastSpanOrigin.values.byName(row['origin'] as String),
      status: CastSpanStatus.values.byName(row['status'] as String),
      lockedByUser: (row['locked_by_user'] as int) == 1,
      confidence: (row['confidence'] as num?)?.toDouble(),
      evidence: row['evidence_json'] is String
          ? CastSpanEvidence.fromJson(Map<String, dynamic>.from(
              jsonDecode(row['evidence_json'] as String) as Map))
          : null,
      anchor: row['anchor_json'] is String
          ? ReadingAnchor.fromJson(Map<String, dynamic>.from(
              jsonDecode(row['anchor_json'] as String) as Map))
          : null,
    )).toList();
  }

  void _assertCastSpeaker(String bookId, String? speakerId) {
    if (getBook(bookId) == null) {
      throw StateError('Cannot cast a book that is not imported');
    }
    if (speakerId == null) return; // explicit "unknown"/narrator
    final found = _database.select('''
      SELECT book_id FROM cast_characters WHERE id = ?
    ''', [speakerId]);
    if (found.isEmpty || found.first['book_id'] != bookId) {
      throw StateError('Cast speaker must belong to this book');
    }
  }

  void _assertNoAcceptedOverlap(CastSpan span) {
    final overlap = _database.select('''
      SELECT id FROM cast_spans WHERE book_id = ?
        AND status = 'accepted' AND id <> ?
        AND start_offset < ? AND end_offset > ?
      LIMIT 1
    ''', [span.bookId, span.id, span.end, span.start]);
    if (overlap.isNotEmpty) {
      throw StateError('An approved cast span overlaps this passage');
    }
  }

  void _writeCastSpan(CastSpan span) {
    _database.execute('''
      INSERT INTO cast_spans (
        id, book_id, start_offset, end_offset, source_sha256,
        speaker_id, anchor_json, origin, status, confidence,
        locked_by_user, evidence_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        start_offset = excluded.start_offset,
        end_offset = excluded.end_offset,
        source_sha256 = excluded.source_sha256,
        speaker_id = excluded.speaker_id,
        anchor_json = excluded.anchor_json,
        origin = excluded.origin,
        status = excluded.status,
        confidence = excluded.confidence,
        locked_by_user = excluded.locked_by_user,
        evidence_json = excluded.evidence_json
      WHERE cast_spans.book_id = excluded.book_id
    ''', [
      span.id, span.bookId, span.start, span.end, span.sourceDigest,
      span.speakerId,
      span.anchor == null ? null : jsonEncode(span.anchor!.toJson()),
      span.origin.name, span.status.name, span.confidence,
      span.lockedByUser ? 1 : 0,
      span.evidence == null ? null : jsonEncode(span.evidence!.toJson()),
    ]);
  }

  /// Requires exact source text, including UTF-16 boundaries. The manual
  /// label is accepted/locked and can never be displaced by an LLM import.
  Future<void> saveManualCastSpan(CastSpan span, String source) async {
    span.validate();
    if (span.origin != CastSpanOrigin.user ||
        !span.lockedByUser || span.status != CastSpanStatus.accepted) {
      throw const FormatException('Only locked manual labels accepted here');
    }
    if (!CastSpan.validUtf16Range(source, span.start, span.end) ||
        CastSpan.digest(source.substring(span.start, span.end))
            != span.sourceDigest) {
      throw const FormatException('Selected excerpt differs from book source');
    }
    _transaction(_database, () {
      _assertCastSpeaker(span.bookId, span.speakerId);
      // A newly authored manual correction overrides an earlier approved
      // machine proposal, but cannot silently replace another manual lock.
      _database.execute('''
        UPDATE cast_spans
        SET status = 'rejected', locked_by_user = 1
        WHERE book_id = ? AND id <> ?
          AND origin = 'llm' AND status = 'accepted'
          AND start_offset < ? AND end_offset > ?
      ''', [span.bookId, span.id, span.end, span.start]);
      _assertNoAcceptedOverlap(span);
      _writeCastSpan(span);
    });
  }

  /// Schema-checked proposals are deliberately pending. A response cannot
  /// replace a manual row or automatically enable a new speaker.
  Future<void> importCastProposals(
      List<CastSpan> proposals, String source) async {
    _transaction(_database, () {
      for (final proposal in proposals) {
        proposal.validate();
        if (proposal.origin != CastSpanOrigin.llm ||
            proposal.status != CastSpanStatus.proposed ||
            proposal.lockedByUser) {
          throw const FormatException('Import requires pending LLM candidates');
        }
        if (!CastSpan.validUtf16Range(
              source, proposal.start, proposal.end) ||
            CastSpan.digest(source.substring(proposal.start, proposal.end))
                != proposal.sourceDigest ||
            (proposal.evidence != null &&
                !proposal.evidence!.matchesSource(source))) {
          throw const FormatException('LLM attribution/evidence is not source-aligned');
        }
        _assertCastSpeaker(proposal.bookId, proposal.speakerId);
        _database.execute('''
          INSERT OR IGNORE INTO cast_spans (
            id, book_id, start_offset, end_offset, source_sha256,
            speaker_id, anchor_json, origin, status, confidence,
            locked_by_user, evidence_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
        ''', [
          proposal.id, proposal.bookId, proposal.start, proposal.end,
          proposal.sourceDigest, proposal.speakerId,
          proposal.anchor == null ? null : jsonEncode(proposal.anchor!.toJson()),
          'llm', 'proposed', proposal.confidence,
          proposal.evidence == null
              ? null : jsonEncode(proposal.evidence!.toJson()),
        ]);
      }
    });
  }

  /// Explicit review event; automatic LLM output is never promoted to active
  /// narration without the user's decision. Rejected spans remain auditable.
  Future<void> reviewCastProposal(String id, {
    required bool approve,
    String? currentSource,
    int? resolvedStart,
  }) async {
    _transaction(_database, () {
      final found = listCastSpansById(id);
      if (found == null || found.origin != CastSpanOrigin.llm ||
          found.status != CastSpanStatus.proposed) {
        throw StateError('No pending suggestion with that identifier');
      }
      if (approve) {
        if (found.evidence != null && currentSource == null) {
          throw StateError('Source verification required for cited evidence');
        }
        if (currentSource != null &&
            (!found.matchesSource(currentSource, (_) => resolvedStart) ||
             (found.evidence != null &&
              !found.evidence!.matchesSource(currentSource)))) {
          throw const FormatException('Source/evidence changed before approval');
        }
        _assertCastSpeaker(found.bookId, found.speakerId);
        _assertNoAcceptedOverlap(found);
      }
      _database.execute('''
        UPDATE cast_spans SET status = ?, locked_by_user = 1 WHERE id = ?
      ''', [approve ? 'accepted' : 'rejected', id]);
    });
  }

  CastSpan? listCastSpansById(String id) {
    final rows = _database.select(
      'SELECT book_id FROM cast_spans WHERE id = ?', [id]);
    return rows.isEmpty ? null :
        listCastSpans(rows.first['book_id'] as String)
            .where((span) => span.id == id).firstOrNull;
  }

  Future<void> deleteCastSpan(String id) async {
    _database.execute('DELETE FROM cast_spans WHERE id = ?', [id]);
  }

  Future<void> removeBook(String bookId) async {
    final book = getBook(bookId);
    if (book == null) return;
    _transaction(_database, () {
      _database.execute('DELETE FROM pronunciation_rules WHERE book_id = ?',
          [bookId]);
      _database.execute('DELETE FROM speech_preferences WHERE scope_id = ?',
          ['book:$bookId']);
      _database.execute('DELETE FROM reading_preferences WHERE scope_id = ?',
          ['book:$bookId']);
      _database.execute('DELETE FROM books WHERE id = ?', [bookId]);
    });
    if (_isManagedPath(book.localPath)) {
      final file = File(book.localPath);
      if (await file.exists()) await file.delete();
    }
    // Remove only local derived covers for this book's validated digest.
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(bookId)) {
      for (final ext in ['jpg', 'png']) {
        final cover = File(p.join(_coversDir.path, '$bookId.$ext'));
        try {
          if (await FileSystemEntity.type(cover.path, followLinks: false) ==
              FileSystemEntityType.file) await cover.delete();
        } on FileSystemException {
          // Native Windows image handles may delay cache deletion.
        }
      }
    }
    // Derived speech is private book data too; delete it with the book.
    // Do not derive a filesystem path from untrusted legacy identifiers.
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(bookId)) {
      final cache = Directory(p.join(_home!.path, 'speech-cache', bookId));
      try {
        if (await cache.exists()) await cache.delete(recursive: true);
      } on FileSystemException {
        // Windows may lock an MP3 during playback; do not delete outside cache.
      }
    }
  }

    bool _isManagedPath(String path) =>
      _home != null && p.isWithin(_booksDir.absolute.path, p.absolute(path));

  void dispose() {
    // Closing the SQLite connection is not equivalent to normal narration
    // termination: a crashed process leaves the checkpoint behind.
    _db?.dispose();
    _db = null;
    _startupInterruptedBookId = null;
  }

  static BookRecord _fromRow(Row row) => BookRecord(
        id: row['id'] as String,
        title: row['title'] as String,
        localPath: row['local_path'] as String,
        format: BookFormat.values.byName(row['format'] as String),
        importedAt: DateTime.parse(row['imported_at'] as String),
        lastOpenedAt: row['last_opened_at'] is String
            ? DateTime.parse(row['last_opened_at'] as String)
            : null,
        author: row['author'] as String?,
        series: row['series'] as String?,
        language: row['language'] as String?,
        progressOffset: row['progress_offset'] as int,
        isFavorite: (row['is_favorite'] as int) == 1,
        readingStatus: BookReadingStatus.values.byName(
            row['reading_status'] as String),
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
        progress_anchor, author, series, language, is_favorite,
        reading_status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      record.author,
      record.series,
      record.language,
      record.isFavorite ? 1 : 0,
      record.readingStatus.name,
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

  /// An older schema-version marker can coexist with already-added columns
  /// after a partial migration or an intentionally downgraded test fixture.
  /// Only fixed, internal table/column names are passed to this helper.
  /// A missing table still fails the subsequent migration; it is not
  /// silently treated as a successfully upgraded database.
  static bool _hasSqliteColumn(Database db, String table, String column) =>
      db.select('PRAGMA table_info($table)')
          .any((row) => row['name'] == column);

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
