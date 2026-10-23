import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/book.dart';
import '../domain/reading_anchor.dart';
import '../domain/pronunciation_rule.dart';
import '../domain/speech_preferences.dart';
import '../domain/book_bookmark.dart';
import '../domain/cloud_speech_consent.dart';
import '../domain/voice_cast.dart';

/// Local, transactional Windows/Android library. Inject homeDirectory in tests.
class LibraryStore implements CloudSpeechAccess {
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
      if (version > 6) {
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
    return global.isEmpty
        ? const SpeechPreferences()
        : _decodeSpeechPrefs(global.first);
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
    if (getBook(character.bookId) == null) {
      throw StateError('Unknown book for cast character');
    }
    // Do not permit moving an existing character to another book.
    final exists = _database.select(
      'SELECT book_id FROM cast_characters WHERE id = ?', [character.id]);
    if (exists.isNotEmpty &&
        exists.first['book_id'] != character.bookId) {
      throw StateError('Cannot move character to a different book');
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

  Future<void> removeBook(String bookId) async {
    final book = getBook(bookId);
    if (book == null) return;
    _transaction(_database, () {
      _database.execute('DELETE FROM pronunciation_rules WHERE book_id = ?',
          [bookId]);
      _database.execute('DELETE FROM speech_preferences WHERE scope_id = ?',
          ['book:$bookId']);
      _database.execute('DELETE FROM books WHERE id = ?', [bookId]);
    });
    if (_isManagedPath(book.localPath)) {
      final file = File(book.localPath);
      if (await file.exists()) await file.delete();
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
