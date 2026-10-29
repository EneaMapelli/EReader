import 'dart:convert';
import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/data/picked_book_import.dart';
import 'package:crypto/crypto.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/pronunciation_rule.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/book_bookmark.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/character_candidate.dart';
import 'package:ereader/domain/alias_candidate.dart';
import 'package:ereader/domain/cloud_speech_consent.dart';
import 'package:ereader/domain/llm_analysis_consent.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-test-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('imports, deduplicates and restores progress after restart', () async {
    final source = File(p.join(root.path, 'import.txt'));
    await source.writeAsString('Once upon a time...', flush: true);
    final first = await store.importFile(
      source.path, originalName: 'Story.TXT',
    );
    final duplicate = await store.importFile(source.path);
    expect(first.id, duplicate.id);
    expect(store.books, hasLength(1));
    expect(first.title, 'Story');

    await store.savePosition(first.id, 42);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(first.id)!.progressOffset, 42);
    expect(File(store.books.single.localPath).existsSync(), isTrue);
  });


  test('catalog details persist, remain searchable, and never reset position',
      () async {
    final input = File(p.join(root.path, 'catalog-details.txt'));
    await input.writeAsString('A local book with a saved position.');
    final book = await store.importFile(input.path);
    await store.savePosition(book.id, 19);
    final edited = store.updateBookMetadata(book.id,
      title: '  Revised title  ',
      author: '  Ada Example  ',
      series: '  Example Cycle ',
      language: 'it_IT',
    );
    expect(edited.title, 'Revised title');
    expect(edited.author, 'Ada Example');
    expect(edited.series, 'Example Cycle');
    expect(edited.language, 'it-IT');
    expect(edited.progressOffset, 19);
    expect(edited.id, book.id);
    expect(edited.localPath, book.localPath);
    expect((await store.importFile(input.path)).title, 'Revised title');

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final restored = store.getBook(book.id)!;
    expect(restored.title, 'Revised title');
    expect(restored.author, 'Ada Example');
    expect(restored.series, 'Example Cycle');
    expect(restored.language, 'it-IT');
    expect(restored.progressOffset, 19);
    expect(restored.atOffset(21).author, 'Ada Example');
    expect(BookRecord.fromJson(restored.toJson()).series, 'Example Cycle');

    final cleared = store.updateBookMetadata(
      book.id, title: restored.title, author: '', series: '', language: '',
    );
    expect(cleared.author, isNull);
    expect(cleared.series, isNull);
    expect(cleared.language, isNull);
    expect(cleared.progressOffset, 19);
  });

  test('invalid book metadata never changes the stored record', () async {
    final source = File(p.join(root.path, 'metadata-validation.txt'));
    await source.writeAsString('Validation does not rewrite the source');
    final book = await store.importFile(source.path);
    expect(() => store.updateBookMetadata(book.id,
      title: '  ', author: 'Other'), throwsFormatException);
    expect(() => store.updateBookMetadata(book.id,
      title: 'Legitimate', language: '../unsafe'), throwsFormatException);
    expect(() => store.updateBookMetadata(book.id,
      title: 'Line\nBreak'), throwsFormatException);
    expect(() => store.updateBookMetadata('unknown',
      title: 'Legitimate'), throwsStateError);
    expect(store.getBook(book.id)!.title, book.title);
    expect(store.getBook(book.id)!.author, isNull);
  });

  test('stream-only picker import deduplicates in the real SQLite library',
      () async {
    final source = utf8.encode('The same EPUB-independent reading source.');
    var openedStream = 0;
    Future<BookRecord> importStream() => importPickedBook<BookRecord>(
      originalName: 'Reader copy.txt',
      pickedPath: null,
      stagingParent: root,
      readAsByteStream: () {
        openedStream++;
        return Stream<List<int>>.fromIterable([
          source.sublist(0, 8),
          source.sublist(8),
        ]);
      },
      importFile: store.importFile,
    );
    final first = await importStream();
    expect(first.title, 'Reader copy');
    expect(first.format, BookFormat.txt);
    expect(await File(first.localPath).readAsBytes(), source);
    await store.savePosition(first.id, 17);
    final second = await importStream();
    expect(second.id, first.id);
    expect(store.books, hasLength(1));
    expect(store.getBook(first.id)?.progressOffset, 17);
    expect(openedStream, 2);
    final remainingStageDirectories = await root.list()
        .where((entry) => entry is Directory &&
            p.basename(entry.path).startsWith('ereader-picker-'))
        .toList();
    expect(remainingStageDirectories, isEmpty);
  });

  test('v2 EPUB context survives existing SQLite progress-anchor JSON column',
      () async {
    final source = File(p.join(root.path, 'anchor.txt'));
    await source.writeAsString('Local reading content');
    final book = await store.importFile(source.path);
    final before = List.filled(32, 'a').join();
    final after = List.filled(32, 'b').join();
    final anchor = ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'chapter-1',
      localOffset: 7, contextBefore: before, contextAfter: after,
    );
    await store.savePosition(book.id, 7, anchor: anchor);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final loaded = store.getBook(book.id)!;
    expect(loaded.progressOffset, 7);
    expect(loaded.progressAnchor?.sourceId, 'chapter-1');
    expect(loaded.progressAnchor?.localOffset, 7);
    expect(loaded.progressAnchor?.hasContext, isTrue);
    expect(loaded.progressAnchor?.contextBefore, before);
    expect(loaded.progressAnchor?.contextAfter, after);
  });

  test('rejects invalid extensions, signature and negative positions', () async {
    final source = File(p.join(root.path, 'fake.epub'));
    await source.writeAsString('Not a ZIP');
    await expectLater(store.importFile(source.path), throwsFormatException);
    expect(store.books, isEmpty);
    await expectLater(store.savePosition('anything', -1), throwsArgumentError);
  });

  test('reimport repairs a lost managed file without resetting progress', () async {
    final source = File(p.join(root.path, 'repair.txt'));
    await source.writeAsString('Restorable content', flush: true);
    final imported = await store.importFile(source.path);
    await store.savePosition(imported.id, 7);
    await File(imported.localPath).delete();

    final repaired = await store.importFile(source.path);
    expect(repaired.id, imported.id);
    expect(repaired.progressOffset, 7);
    expect(File(repaired.localPath).existsSync(), isTrue);
    expect(store.books, hasLength(1));
  });

  test('adopts an intact orphan file left after interrupted SQLite commit',
      () async {
    final source = File(p.join(root.path, 'orphan.txt'));
    final bytes = 'Interrupted transaction'.codeUnits;
    await source.writeAsBytes(bytes);
    final id = sha256.convert(bytes).toString();
    final target = File(p.join(root.path, 'books', '$id.txt'));
    await target.writeAsBytes(bytes, flush: true);
    final imported = await store.importFile(source.path);
    expect(imported.id, id);
    expect(store.books, hasLength(1));
    expect(await target.readAsBytes(), bytes);
  });

  test('removing a book leaves the original import file intact', () async {
    final source = File(p.join(root.path, 'book.txt'));
    await source.writeAsString('Book text', flush: true);
    final book = await store.importFile(source.path);
    await store.removeBook(book.id);
    expect(store.books, isEmpty);
    expect(File(book.localPath).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
  });

  test('legacy JSON migrates and retains progress across multiple starts',
      () async {
    store.dispose();
    await File(p.join(root.path, 'library.sqlite')).delete();
    final managed = Directory(p.join(root.path, 'books'));
    await managed.create(recursive: true);
    final bookPath = p.join(managed.path, 'existing.txt');
    await File(bookPath).writeAsString('Legacy contents');
    await File(p.join(root.path, 'library.json')).writeAsString(jsonEncode([
      {
        'id': 'legacy',
        'title': 'Legacy',
        'localPath': bookPath,
        'format': 'txt',
        'importedAt': '2026-10-21T00:00:00.000Z',
        'progressOffset': 87,
      }
    ]));
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.books, hasLength(1));
    expect(store.getBook('legacy')!.progressOffset, 87);
    expect(File(p.join(root.path, 'library.migrated.json')).existsSync(), true);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.books, hasLength(1));
  });

  test('malformed legacy index is not destroyed', () async {
    store.dispose();
    await File(p.join(root.path, 'library.sqlite')).delete();
    final legacy = File(p.join(root.path, 'library.json'));
    await legacy.writeAsString('{"invalid":true}');
    store = LibraryStore(homeDirectory: root);
    await expectLater(store.initialize(), throwsFormatException);
    expect(legacy.existsSync(), isTrue);
  });
  test('SQLite v2 persists source anchor and clears it on legacy writes', () async {
    final source = File(p.join(root.path, 'anchored.txt'));
    await source.writeAsString('A document', flush: true);
    final book = await store.importFile(source.path);
    await store.savePosition(book.id, 5,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 5));
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id)!.progressAnchor!.localOffset, 5);
    await store.savePosition(book.id, 8);
    expect(store.getBook(book.id)!.progressOffset, 8);
    expect(store.getBook(book.id)!.progressAnchor, isNull);
  });

  test('upgrade from SQLite v1 preserves existing progress', () async {
    store.dispose();
    final dbFile = File(p.join(root.path, 'library.sqlite'));
    await dbFile.delete();
    final old = sqlite3.open(dbFile.path);
    old.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        local_path TEXT NOT NULL,
        format TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        progress_offset INTEGER NOT NULL DEFAULT 0
      )
    ''');
    old.execute('PRAGMA user_version = 1');
    old.execute('''
      INSERT INTO books
        (id, title, local_path, format, imported_at, progress_offset)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', ['old-id', 'A classic', p.join(root.path, 'books', 'old.txt'),
          'txt', '2026-10-22T00:00:00.000Z', 77]);
    old.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final restored = store.getBook('old-id')!;
    expect(restored.progressOffset, 77);
    expect(restored.progressAnchor, isNull);
    await store.savePosition('old-id', 78,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 78));
    expect(store.getBook('old-id')!.progressAnchor!.localOffset, 78);
  });


  test('SQLite v3 keeps global and per-book pronunciations across restart',
      () async {
    final input = File(p.join(root.path, 'novel.txt'));
    await input.writeAsString('Aeryn moved.');
    final book = await store.importFile(input.path);
    await store.upsertPronunciationRule(const PronunciationRule(
      id: 'g1', pattern: 'Aeryn', replacement: 'Erin',
    ));
    await store.upsertPronunciationRule(PronunciationRule(
      id: 'b1', bookId: book.id, pattern: 'Aeryn',
      replacement: 'Air-in',
    ));
    expect(store.listPronunciationRules(bookId: book.id), hasLength(2));
    expect(store.listPronunciationRules(), hasLength(1));

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final loaded = store.listPronunciationRules(bookId: book.id);
    expect(loaded, hasLength(2));
    expect(loaded.singleWhere((r) => r.id == 'b1').replacement, 'Air-in');
    await store.deletePronunciationRule('b1');
    expect(store.listPronunciationRules(bookId: book.id), hasLength(1));
  });

  test('speech preferences fall back to global and support book override',
      () async {
    final input = File(p.join(root.path, 'speech.txt'));
    await input.writeAsString('Voice settings.');
    final book = await store.importFile(input.path);
    expect(store.getSpeechPreferences(bookId: book.id).rate, 0.5);

    await store.saveSpeechPreferences(const SpeechPreferences(
      language: 'en-US', rate: 0.8, pitch: 1.1,
    ));
    expect(store.getSpeechPreferences(bookId: book.id).rate, 0.8);
    await store.saveSpeechPreferences(const SpeechPreferences(
      language: 'it-IT', rate: 0.3, pitch: 1.0,
      voiceName: 'Test voice', voiceLocale: 'it-IT',
    ), bookId: book.id);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getSpeechPreferences(bookId: book.id).rate, 0.3);
    expect(store.getSpeechPreferences(bookId: book.id).voiceName,
        'Test voice');
    expect(store.getSpeechPreferences().rate, 0.8);
    await store.clearBookSpeechPreferences(book.id);
    expect(store.getSpeechPreferences(bookId: book.id).rate, 0.8);
  });


  test('book language drives TTS only with no saved speech profile',
      () async {
    final source = File(p.join(root.path, 'book-language.txt'));
    await source.writeAsString('Test source, no network or cloud calls.');
    final book = await store.importFile(source.path);
    expect(store.getSpeechPreferences(bookId: book.id).language, 'it-IT');

    store.updateBookMetadata(
      book.id, title: book.title, language: 'en',
    );
    expect(store.getSpeechPreferences(bookId: book.id).language, 'en-US');
    expect(store.getSpeechPreferences().language, 'it-IT',
        reason: 'Global default must not be mutated by inference');

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getSpeechPreferences(bookId: book.id).language, 'en-US');

    store.updateBookMetadata(
      book.id, title: book.title, language: 'fr_FR',
    );
    expect(store.getSpeechPreferences(bookId: book.id).language, 'fr-FR');

    await store.saveSpeechPreferences(
      const SpeechPreferences(language: 'de-DE', rate: 0.7),
    );
    expect(store.getSpeechPreferences(bookId: book.id).language, 'de-DE');
    expect(store.getSpeechPreferences(bookId: book.id).rate, 0.7);

    await store.saveSpeechPreferences(
      const SpeechPreferences(language: 'es-ES', rate: 0.4),
      bookId: book.id,
    );
    expect(store.getSpeechPreferences(bookId: book.id).language, 'es-ES');
    await store.clearBookSpeechPreferences(book.id);
    expect(store.getSpeechPreferences(bookId: book.id).language, 'de-DE');
  });

  test('unrecognized metadata falls back without persisting a voice',
      () async {
    final source = File(p.join(root.path, 'unknown-language.txt'));
    await source.writeAsString('No voice configuration.');
    final book = await store.importFile(source.path);
    store.updateBookMetadata(
      book.id, title: book.title, language: 'xx',
    );
    expect(store.getSpeechPreferences(bookId: book.id).language, 'it-IT');
    store.updateBookMetadata(
      book.id, title: book.title, language: 'en-GB',
    );
    expect(store.getSpeechPreferences(bookId: book.id).language, 'en-GB');
    expect(store.getSpeechPreferences().language, 'it-IT');
  });

  test('deleting a book removes its voice data, preserving global rules',
      () async {
    final source = File(p.join(root.path, 'cleanup.txt'));
    await source.writeAsString('Cleanup');
    final book = await store.importFile(source.path);
    await store.upsertPronunciationRule(const PronunciationRule(
      id: 'global', pattern: 'X', replacement: 'Z',
    ));
    await store.upsertPronunciationRule(PronunciationRule(
      id: 'local', bookId: book.id, pattern: 'X', replacement: 'Y',
    ));
    await store.saveSpeechPreferences(
        const SpeechPreferences(rate: 0.6), bookId: book.id);
    await store.removeBook(book.id);
    expect(store.listPronunciationRules(), hasLength(1));
    expect(store.listPronunciationRules(bookId: book.id), hasLength(1));
    expect(store.getSpeechPreferences(bookId: book.id).rate, 0.5);
  });

  test('v2 SQLite migrates to v3 without losing anchors', () async {
    final source = File(p.join(root.path, 'v2.txt'));
    await source.writeAsString('Before migration');
    final book = await store.importFile(source.path);
    await store.savePosition(book.id, 4,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 4));
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE pronunciation_rules');
    db.execute('DROP TABLE speech_preferences');
    db.execute('PRAGMA user_version = 2');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id)!.progressAnchor!.localOffset, 4);
    await store.upsertPronunciationRule(const PronunciationRule(
      id: 'migrated', pattern: 'Before', replacement: 'Bee-four',
    ));
    expect(store.listPronunciationRules(), hasLength(1));
  });


  test('bookmarks persist source anchors across restart', () async {
    final input = File(p.join(root.path, 'marks.txt'));
    await input.writeAsString('Several chapters');
    final book = await store.importFile(input.path);
    await store.addBookmark(BookBookmark(
      id: 'bookmark-1',
      bookId: book.id,
      title: 'Important passage',
      globalOffset: 7,
      createdAt: DateTime.utc(2026, 10, 22),
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 7),
    ));
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final marks = store.listBookmarks(book.id);
    expect(marks, hasLength(1));
    expect(marks.single.globalOffset, 7);
    expect(marks.single.anchor!.sourceId, 'body');
    await store.deleteBookmark('bookmark-1');
    expect(store.listBookmarks(book.id), isEmpty);
  });

  test('book deletion cascades into bookmarks', () async {
    final input = File(p.join(root.path, 'cascade.txt'));
    await input.writeAsString('A text');
    final book = await store.importFile(input.path);
    await store.addBookmark(BookBookmark(
      id: 'mark-deleted',
      bookId: book.id,
      title: 'Chapter',
      globalOffset: 0,
      createdAt: DateTime.utc(2026, 10, 22),
    ));
    await store.removeBook(book.id);
    expect(store.listBookmarks(book.id), isEmpty);
  });

  test('partially downgraded v8 schema skips already existing later columns',
      () async {
    final source = File(p.join(root.path, 'partial-upgrade.txt'));
    await source.writeAsString('Resumable story');
    final book = await store.importFile(source.path);
    await store.savePosition(book.id, 8, anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 8));
    store.dispose();

    final file = p.join(root.path, 'library.sqlite');
    final old = sqlite3.open(file);
    final castColumns = old.select('PRAGMA table_info(cast_spans)')
        .map((row) => row['name']).toSet();
    final bookColumns = old.select('PRAGMA table_info(books)')
        .map((row) => row['name']).toSet();
    expect(castColumns, contains('evidence_json'));
    expect(bookColumns, containsAll(['progress_anchor',
        'last_opened_at', 'pdf_visual_page']));
    // Exercise recovery from a database whose version marker was
    // rolled back after ADD COLUMN operations had already completed.
    old.execute('PRAGMA user_version = 8');
    old.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id)!.progressOffset, 8);
    expect(store.getBook(book.id)!.progressAnchor?.localOffset, 8);
    store.dispose();

    final upgraded = sqlite3.open(file);
    expect(upgraded.select('PRAGMA user_version').single['user_version'],
        22);
    expect(upgraded.select('PRAGMA table_info(books)')
        .where((row) => row['name'] == 'last_opened_at').length, 1);
    expect(upgraded.select('PRAGMA table_info(cast_spans)')
        .where((row) => row['name'] == 'evidence_json').length, 1);
    upgraded.dispose();
  });

  test('legacy v1 version marker with present anchor column migrates once',
      () async {
    final source = File(p.join(root.path, 'partial-v1.txt'));
    await source.writeAsString('Persist existing progress.');
    final book = await store.importFile(source.path);
    await store.savePosition(book.id, 6);
    store.dispose();
    final dbFile = p.join(root.path, 'library.sqlite');
    final old = sqlite3.open(dbFile);
    old.execute('PRAGMA user_version = 1');
    old.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id)!.progressOffset, 6);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id)!.progressOffset, 6);
    expect(store.books, hasLength(1));
  });

  test('SQLite schema v3 migrates bookmarks without changing old data',
      () async {
    final input = File(p.join(root.path, 'legacy-v3.txt'));
    await input.writeAsString('Saved');
    final book = await store.importFile(input.path);
    await store.savePosition(book.id, 4);
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE bookmarks');
    db.execute('PRAGMA user_version = 3');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id)!.progressOffset, 4);
    expect(store.listBookmarks(book.id), isEmpty);
  });


  test('cloud is denied by default and reservations stay below hard quota',
      () async {
    final input = File(p.join(root.path, 'secure-cloud.txt'));
    await input.writeAsString('External excerpts');
    final book = await store.importFile(input.path);
    expect(store.getConsent(book.id, 'openai-speech').allowed, isFalse);
    await expectLater(
      store.reserveCharacters(book.id, 'openai-speech', 5),
      throwsA(isA<CloudSpeechBlocked>()),
    );
    await store.configureCloudConsent(book.id, 'openai-speech',
        allowed: true, maxCharacters: 10);
    await store.reserveCharacters(book.id, 'openai-speech', 7);
    await expectLater(
      store.reserveCharacters(book.id, 'openai-speech', 4),
      throwsA(isA<CloudSpeechBlocked>()),
    );
    final consent = store.getConsent(book.id, 'openai-speech');
    expect(consent.usedCharacters, 7);
    expect(consent.remainingCharacters, 3);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getConsent(book.id, 'openai-speech').usedCharacters, 7);
    await store.configureCloudConsent(book.id, 'openai-speech',
        allowed: false, maxCharacters: 10);
    await expectLater(
      store.reserveCharacters(book.id, 'openai-speech', 1),
      throwsA(isA<CloudSpeechBlocked>()),
    );
  });

  test('raising limit retains consumed quota and reducing below used fails',
      () async {
    final input = File(p.join(root.path, 'quota.txt'));
    await input.writeAsString('A book');
    final book = await store.importFile(input.path);
    await store.configureCloudConsent(book.id, 'openai-speech',
        allowed: true, maxCharacters: 10);
    await store.reserveCharacters(book.id, 'openai-speech', 9);
    await expectLater(
      store.configureCloudConsent(book.id, 'openai-speech',
          allowed: true, maxCharacters: 8),
      throwsStateError,
    );
    await store.configureCloudConsent(book.id, 'openai-speech',
        allowed: true, maxCharacters: 20);
    expect(store.getConsent(book.id, 'openai-speech').usedCharacters, 9);
    expect(store.getConsent(book.id, 'openai-speech').remainingCharacters, 11);
    await store.removeBook(book.id);
    expect(store.getConsent(book.id, 'openai-speech').allowed, isFalse);
  });

  test('SQLite v4 upgrades cloud policy without dropping bookmarks',
      () async {
    final input = File(p.join(root.path, 'v4-cloud.txt'));
    await input.writeAsString('Privacy matters');
    final book = await store.importFile(input.path);
    await store.addBookmark(BookBookmark(
      id: 'bookmark-cloud', bookId: book.id,
      title: 'A bookmark', globalOffset: 3,
      createdAt: DateTime.utc(2026, 10, 22),
    ));
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE cloud_speech_consent');
    db.execute('PRAGMA user_version = 4');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listBookmarks(book.id), hasLength(1));
    expect(store.getConsent(book.id, 'openai-speech').allowed, isFalse);
  });


  test('SQLite v6 preserves cast and source-anchored speaker turns',
      () async {
    final source = File(p.join(root.path, 'dialogue.txt'));
    await source.writeAsString('Say hello. Narrator speaking.');
    final book = await store.importFile(source.path);
    final person = CastCharacter(
      id: 'speaker-1', bookId: book.id, name: 'Aeryn',
      aliases: const ['The scout'],
    );
    await store.saveCastCharacter(person);
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'speaker-1', providerId: 'system',
      voiceName: 'Windows Voice', voiceLocale: 'en-US',
    ));
    final attribution = SegmentCastAssignment(
      bookId: book.id, start: 0, end: 10,
      sourceDigest: SegmentCastAssignment.fingerprint('Say hello.'),
      characterId: 'speaker-1',
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 0,
      ),
    );
    await store.saveSegmentCast(attribution);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listCastCharacters(book.id).single.name, 'Aeryn');
    expect(store.listCastCharacters(book.id).single.aliases, ['The scout']);
    expect(store.listCastVoices(book.id).single.voiceName, 'Windows Voice');
    expect(store.listSegmentCast(book.id).single.sourceDigest,
        SegmentCastAssignment.fingerprint('Say hello.'));

    await store.saveCastCharacter(CastCharacter(
      id: 'speaker-1', bookId: book.id, name: 'Aeryn the Scout',
    ));
    expect(store.listCastCharacters(book.id).single.name,
        'Aeryn the Scout');
    expect(store.listSegmentCast(book.id), hasLength(1));
  });

  test('cast is book-isolated and removing a person reverts to narrator',
      () async {
    final first = File(p.join(root.path, 'one.txt'));
    final second = File(p.join(root.path, 'two.txt'));
    await first.writeAsString('First book');
    await second.writeAsString('Second book');
    final b1 = await store.importFile(first.path);
    final b2 = await store.importFile(second.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'speaker-1', bookId: b1.id, name: 'First',
    ));
    await expectLater(
      store.saveSegmentCast(SegmentCastAssignment(
        bookId: b2.id, start: 0, end: 5,
        sourceDigest: SegmentCastAssignment.fingerprint('Other'),
        characterId: 'speaker-1',
      )),
      throwsStateError,
    );
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'speaker-1',
      providerId: 'system',
      voiceName: 'Voice One',
      voiceLocale: 'en-US',
    ));
    await store.saveSegmentCast(SegmentCastAssignment(
      bookId: b1.id, start: 0, end: 5,
      sourceDigest: SegmentCastAssignment.fingerprint('First'),
      characterId: 'speaker-1',
    ));
    await store.deleteCastCharacter('speaker-1');
    expect(store.listSegmentCast(b1.id), isEmpty);
    expect(store.listCastVoices(b1.id), isEmpty);
    expect(store.listCastCharacters(b2.id), isEmpty);
  });

  test('SQLite v5 to v6 retains cloud usage and the library',
      () async {
    final source = File(p.join(root.path, 'upgrade-cast.txt'));
    await source.writeAsString('An older library');
    final book = await store.importFile(source.path);
    await store.configureCloudConsent(
      book.id, 'openai-speech',
      allowed: true, maxCharacters: 200,
    );
    await store.reserveCharacters(book.id, 'openai-speech', 10);
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE segment_cast');
    db.execute('DROP TABLE cast_voices');
    db.execute('DROP TABLE cast_characters');
    db.execute('PRAGMA user_version = 5');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getBook(book.id), isNotNull);
    expect(store.getConsent(book.id, 'openai-speech').usedCharacters, 10);
    expect(store.listCastCharacters(book.id), isEmpty);
    await store.saveCastCharacter(CastCharacter(
      id: 'new-speaker', bookId: book.id, name: 'A new character',
    ));
    expect(store.listCastCharacters(book.id).single.name, 'A new character');
  });


  test('SQLite v7 persists precise manual speaker labels across reopening',
      () async {
    final file = File(p.join(root.path, 'selection.txt'));
    const text = 'Narrator: «Hello!» and then narrator.';
    await file.writeAsString(text);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'actor', bookId: book.id, name: 'Actor',
    ));
    final start = text.indexOf('«');
    final end = text.indexOf('»') + 1;
    final manual = CastSpan(
      id: 'manual-1', bookId: book.id,
      start: start, end: end,
      sourceDigest: CastSpan.digest(text.substring(start, end)),
      speakerId: 'actor',
      origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted,
      lockedByUser: true,
      anchor: ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: start,
      ),
    );
    await store.saveManualCastSpan(manual, text);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final restored = store.listCastSpans(book.id);
    expect(restored, hasLength(1));
    expect(restored.single.speakerId, 'actor');
    expect(restored.single.lockedByUser, isTrue);
    expect(restored.single.sourceDigest, manual.sourceDigest);
    expect(restored.single.anchor!.localOffset, start);
  });

  test('overlapping manual assignments are rejected atomically', () async {
    final file = File(p.join(root.path, 'overlap.txt'));
    const content = 'abcdef ghijkl';
    await file.writeAsString(content);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'actor', bookId: book.id, name: 'Actor',
    ));
    CastSpan span(String id, int a, int b) => CastSpan(
      id: id, bookId: book.id,
      start: a, end: b,
      sourceDigest: CastSpan.digest(content.substring(a, b)),
      speakerId: 'actor',
      origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted,
      lockedByUser: true,
    );
    await store.saveManualCastSpan(span('a', 0, 6), content);
    await expectLater(
      store.saveManualCastSpan(span('b', 2, 4), content),
      throwsStateError,
    );
    expect(store.listCastSpans(book.id), hasLength(1));
  });

  test('LLM proposals remain pending and cannot overwrite manual labels',
      () async {
    final file = File(p.join(root.path, 'review.txt'));
    const content = 'one two three';
    await file.writeAsString(content);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'actor', bookId: book.id, name: 'Actor',
    ));
    final original = CastSpan(
      id: 'existing', bookId: book.id, start: 0, end: 3,
      sourceDigest: CastSpan.digest('one'),
      speakerId: 'actor', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
    );
    await store.saveManualCastSpan(original, content);
    CastSpan suggestion(String id, int from, int until) => CastSpan(
      id: id, bookId: book.id,
      start: from, end: until,
      sourceDigest: CastSpan.digest(content.substring(from, until)),
      speakerId: 'actor',
      origin: CastSpanOrigin.llm,
      status: CastSpanStatus.proposed,
      lockedByUser: false,
      confidence: 0.91,
    );
    await store.importCastProposals([
      suggestion('existing', 0, 3), // Must never replace the manual row.
      suggestion('conflict', 1, 6),
      suggestion('safe', 8, 13),
    ], content);
    expect(store.listCastSpans(book.id), hasLength(3));
    expect(store.listCastSpans(book.id).firstWhere(
      (s) => s.id == 'existing').origin, CastSpanOrigin.user);
    await expectLater(
      store.reviewCastProposal('conflict', approve: true),
      throwsStateError,
    );
    await store.reviewCastProposal('safe', approve: true);
    expect(store.listCastSpans(book.id).firstWhere(
      (s) => s.id == 'safe').status, CastSpanStatus.accepted);
    // The user may replace an earlier approved machine label explicitly.
    await store.saveManualCastSpan(CastSpan(
      id: 'corrected-by-user', bookId: book.id,
      start: 8, end: 13, sourceDigest: CastSpan.digest('three'),
      speakerId: null,
      origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
    ), content);
    expect(store.listCastSpans(book.id).firstWhere(
      (s) => s.id == 'safe').status, CastSpanStatus.rejected);
    expect(store.listCastSpans(book.id).firstWhere(
      (s) => s.id == 'corrected-by-user').lockedByUser, isTrue);
    await store.reviewCastProposal('conflict', approve: false);
    expect(store.listCastSpans(book.id).firstWhere(
      (s) => s.id == 'conflict').status, CastSpanStatus.rejected);
  });

  test('SQLite v6-to-v7 preserves legacy cast and cloud consent', () async {
    final file = File(p.join(root.path, 'cast-v6.txt'));
    await file.writeAsString('Legacy character');
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'legacy-actor', bookId: book.id, name: 'Legacy Actor',
    ));
    await store.configureCloudConsent(book.id, 'openai-speech',
      allowed: true, maxCharacters: 100);
    await store.reserveCharacters(book.id, 'openai-speech', 12);
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE cast_spans');
    db.execute('PRAGMA user_version = 6');
    db.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listCastCharacters(book.id).single.name, 'Legacy Actor');
    expect(store.getConsent(book.id, 'openai-speech').usedCharacters, 12);
    expect(store.listCastSpans(book.id), isEmpty);
  });


  test('LLM analysis is opt-in independently from paid speech', () async {
    final file = File(p.join(root.path, 'analysis-no-optin.txt'));
    await file.writeAsString('A narrated chapter.');
    final book = await store.importFile(file.path);
    await store.configureCloudConsent(book.id, 'openai-speech',
        allowed: true, maxCharacters: 100);
    expect(store.getLlmAnalysisConsent(book.id).allowed, isFalse);
    await expectLater(
      store.reserveLlmAnalysisInput(book.id, 150),
      throwsA(isA<LlmAnalysisDenied>()),
    );
    expect(store.getLlmAnalysisConsent(book.id).usedInputCharacters, 0);
    await store.configureLlmAnalysisConsent(book.id,
        allowed: true, maxInputCharacters: 2000);
    await store.reserveLlmAnalysisInput(book.id, 600);
    expect(store.getLlmAnalysisConsent(book.id).remainingInputCharacters, 1400);
    expect(store.getConsent(book.id, 'openai-speech').usedCharacters, 0);
  });

  test('analysis quota persists and cannot be reduced below prior usage',
      () async {
    final file = File(p.join(root.path, 'analysis-quota.txt'));
    await file.writeAsString('Small dialogue.');
    final book = await store.importFile(file.path);
    await store.configureLlmAnalysisConsent(book.id,
        allowed: true, maxInputCharacters: 2000);
    await store.reserveLlmAnalysisInput(book.id, 1800);
    await expectLater(
      store.configureLlmAnalysisConsent(book.id,
          allowed: true, maxInputCharacters: 1600),
      throwsStateError,
    );
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.getLlmAnalysisConsent(book.id).usedInputCharacters, 1800);
    await expectLater(
      store.reserveLlmAnalysisInput(book.id, 250),
      throwsA(isA<LlmAnalysisDenied>()),
    );
    await store.configureLlmAnalysisConsent(book.id,
        allowed: false, maxInputCharacters: 2000);
    await expectLater(
      store.reserveLlmAnalysisInput(book.id, 1),
      throwsA(isA<LlmAnalysisDenied>()),
    );
    expect(store.getLlmAnalysisConsent(book.id).usedInputCharacters, 1800);
  });

  test('SQLite v7-to-v8 keeps existing cast, voice and consent history',
      () async {
    final file = File(p.join(root.path, 'upgrade-analysis.txt'));
    await file.writeAsString('Dialogue chapter.');
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'cast-member', bookId: book.id, name: 'Speaker',
    ));
    await store.configureCloudConsent(book.id, 'openai-speech',
        allowed: true, maxCharacters: 1000);
    await store.reserveCharacters(book.id, 'openai-speech', 25);
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE llm_analysis_consent');
    db.execute('PRAGMA user_version = 7');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listCastCharacters(book.id).single.name, 'Speaker');
    expect(store.getConsent(book.id, 'openai-speech').usedCharacters, 25);
    expect(store.getLlmAnalysisConsent(book.id).allowed, isFalse);
    await store.configureLlmAnalysisConsent(book.id,
        allowed: true, maxInputCharacters: 3500);
    await store.reserveLlmAnalysisInput(book.id, 1900);
    expect(store.getLlmAnalysisConsent(book.id).usedInputCharacters, 1900);
    await store.removeBook(book.id);
    expect(store.getLlmAnalysisConsent(book.id).allowed, isFalse);
  });


  test('SQLite v9 persists verified backward-only LLM evidence',
      () async {
    const source = 'Anna entered. «Hello!»';
    const prior = 'Anna entered.';
    const quote = '«Hello!»';
    final textFile = File(p.join(root.path, 'evidence.txt'));
    await textFile.writeAsString(source);
    final book = await store.importFile(textFile.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'actor', bookId: book.id, name: 'Anna',
    ));
    final quoteStart = source.indexOf(quote);
    final proposal = CastSpan(
      id: 'llm-grounded', bookId: book.id,
      start: quoteStart, end: quoteStart + quote.length,
      sourceDigest: CastSpan.digest(quote),
      speakerId: 'actor',
      origin: CastSpanOrigin.llm, status: CastSpanStatus.proposed,
      lockedByUser: false, confidence: 0.8,
      evidence: CastSpanEvidence(
        start: 0, end: prior.length,
        sourceDigest: CastSpan.digest(prior),
      ),
    );
    await store.importCastProposals([proposal], source);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();

    final restored = store.listCastSpans(book.id).single;
    expect(restored.evidence!.matchesSource(source), isTrue);
    expect(restored.evidence!.sourceDigest, CastSpan.digest(prior));

    await expectLater(
      store.reviewCastProposal('llm-grounded', approve: true),
      throwsStateError,
    );
    await expectLater(
      store.reviewCastProposal('llm-grounded', approve: true,
          currentSource: source.replaceFirst('Anna', 'Elsa'),
          resolvedStart: quoteStart),
      throwsFormatException,
    );
    expect(store.listCastSpans(book.id).single.status,
        CastSpanStatus.proposed);
    await store.reviewCastProposal('llm-grounded', approve: true,
      currentSource: source, resolvedStart: quoteStart);
    expect(store.listCastSpans(book.id).single.status,
        CastSpanStatus.accepted);
  });

  test('SQLite v8-to-v9 migration preserves existing cast and approval',
      () async {
    const source = 'An old attribution';
    final input = File(p.join(root.path, 'schema-v8.txt'));
    await input.writeAsString(source);
    final book = await store.importFile(input.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'older', bookId: book.id, name: 'Narrator One',
    ));
    await store.saveManualCastSpan(CastSpan(
      id: 'before-migration', bookId: book.id,
      start: 0, end: source.length,
      sourceDigest: CastSpan.digest(source),
      speakerId: 'older',
      origin: CastSpanOrigin.user, status: CastSpanStatus.accepted,
      lockedByUser: true,
    ), source);
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('ALTER TABLE cast_spans DROP COLUMN evidence_json');
    db.execute('PRAGMA user_version = 8');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final old = store.listCastSpans(book.id).single;
    expect(old.speakerId, 'older');
    expect(old.lockedByUser, isTrue);
    expect(old.evidence, isNull);
    expect(store.getBook(book.id), isNotNull);
  });


  test('character discovery is persistent and does not create cast silently',
      () async {
    const source = 'Anna said: Mira joined the group.';
    final input = File(p.join(root.path, 'new-character.txt'));
    await input.writeAsString(source);
    final book = await store.importFile(input.path);
    final start = source.indexOf('Mira');
    final candidate = CharacterCandidate(
      id: 'discovered-1',
      bookId: book.id,
      name: 'Mira',
      start: start,
      end: start + 4,
      sourceDigest: CharacterCandidate.fingerprint('Mira'),
      confidence: 0.8,
      status: CharacterCandidateStatus.proposed,
    );
    await store.importCharacterCandidates([candidate], source);
    expect(store.listCastCharacters(book.id), isEmpty);
    expect(store.listCharacterCandidates(book.id).single.status,
        CharacterCandidateStatus.proposed);

    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listCharacterCandidates(book.id).single.name, 'Mira');
    expect(store.listCastCharacters(book.id), isEmpty);

    await store.reviewCharacterCandidate(
      'discovered-1',
      approve: true,
      source: source,
      newCharacterId: 'character-mira',
      displayName: 'Mira',
    );
    expect(store.listCastCharacters(book.id).single.name, 'Mira');
    final reviewed = store.listCharacterCandidates(book.id).single;
    expect(reviewed.status, CharacterCandidateStatus.accepted);
    expect(reviewed.createdCharacterId, 'character-mira');
    expect(store.listCastVoices(book.id), isEmpty);
    expect(store.listSegmentCast(book.id), isEmpty);
  });

  test('forged names and cross-book characters cannot enter cast', () async {
    const source = 'Anna introduces Mira.';
    final one = File(p.join(root.path, 'one-person.txt'));
    final two = File(p.join(root.path, 'other-person.txt'));
    await one.writeAsString(source);
    const secondSource = 'Another novel';
    await two.writeAsString(secondSource);
    final b1 = await store.importFile(one.path);
    final b2 = await store.importFile(two.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'known', bookId: b1.id, name: 'Anna', aliases: const ['Annie'],
    ));
    final illegal = CharacterCandidate(
      id: 'candidate-bad', bookId: b2.id,
      name: 'Mira',
      start: source.indexOf('Mira'), end: source.length - 1,
      sourceDigest: CharacterCandidate.fingerprint('Mira'),
      confidence: 0.6,
      status: CharacterCandidateStatus.proposed,
    );
    await expectLater(
      store.importCharacterCandidates([illegal], secondSource),
      throwsFormatException,
    );
    expect(store.listCharacterCandidates(b1.id), isEmpty);
    expect(store.listCharacterCandidates(b2.id), isEmpty);

    final start = source.indexOf('Anna');
    await store.importCharacterCandidates([
      CharacterCandidate(
        id: 'candidate-known', bookId: b1.id,
        name: 'Anna', start: start, end: start + 4,
        sourceDigest: CharacterCandidate.fingerprint('Anna'),
        confidence: 0.9, status: CharacterCandidateStatus.proposed,
      ),
    ], source);
    expect(store.listCharacterCandidates(b1.id), isEmpty);
  });

  test('duplicate case-folded names do not create a second cast member',
      () async {
    const source = 'Captain Mira arrived.';
    final input = File(p.join(root.path, 'duplicate.txt'));
    await input.writeAsString(source);
    final book = await store.importFile(input.path);
    final start = source.indexOf('Captain Mira');
    final proposed = CharacterCandidate(
      id: 'candidate-duplicate', bookId: book.id,
      name: 'Captain Mira', start: start,
      end: start + 'Captain Mira'.length,
      sourceDigest: CharacterCandidate.fingerprint('Captain Mira'),
      confidence: 0.8,
      status: CharacterCandidateStatus.proposed,
    );
    await store.importCharacterCandidates([proposed], source);
    await store.saveCastCharacter(CastCharacter(
      id: 'existing-cast', bookId: book.id,
      name: 'Mira', aliases: const ['Captain Mira'],
    ));
    await expectLater(store.reviewCharacterCandidate(
      proposed.id,
      approve: true,
      source: source,
      newCharacterId: 'duplicate-person',
      displayName: 'captain  MIRA',
    ), throwsStateError);
    expect(store.listCastCharacters(book.id), hasLength(1));
    expect(store.listCharacterCandidates(book.id).single.status,
        CharacterCandidateStatus.proposed);
    await store.reviewCharacterCandidate(
      proposed.id, approve: false, source: source,
    );
    expect(store.listCharacterCandidates(book.id).single.status,
        CharacterCandidateStatus.rejected);
  });

  test('SQLite v9 upgrades to v10 without affecting cast and analysis consent',
      () async {
    final input = File(p.join(root.path, 'migrate-v10.txt'));
    await input.writeAsString('Named character.');
    final book = await store.importFile(input.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'old-person', bookId: book.id, name: 'Earlier Character',
    ));
    await store.configureLlmAnalysisConsent(
      book.id, allowed: true, maxInputCharacters: 4000,
    );
    await store.reserveLlmAnalysisInput(book.id, 123);
    store.dispose();

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE character_candidates');
    db.execute('PRAGMA user_version = 9');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listCastCharacters(book.id).single.name,
        'Earlier Character');
    expect(store.getLlmAnalysisConsent(book.id).usedInputCharacters, 123);
    expect(store.listCharacterCandidates(book.id), isEmpty);
    await store.removeBook(book.id);
    expect(store.listCharacterCandidates(book.id), isEmpty);
  });


  test('SQLite v11 stores pending nicknames and requires explicit attachment',
      () async {
    const source = 'Mira greeted the Captain warmly.';
    final input = File(p.join(root.path, 'alias-book.txt'));
    await input.writeAsString(source);
    final book = await store.importFile(input.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira',
    ));
    final start = source.indexOf('the Captain');
    final proposed = AliasCandidate(
      id: 'alias-1', bookId: book.id,
      alias: 'the Captain', targetCharacterId: 'mira',
      start: start, end: start + 'the Captain'.length,
      sourceDigest: AliasCandidate.fingerprint('the Captain'),
      status: AliasCandidateStatus.proposed, confidence: 0.72,
      evidence: CastSpanEvidence(
        start: 0, end: 4, sourceDigest: CastSpan.digest('Mira')),
    );
    await store.importAliasCandidates([proposed], source);
    expect(store.listCastCharacters(book.id).single.aliases, isEmpty);
    expect(store.listAliasCandidates(book.id).single.status,
        AliasCandidateStatus.proposed);
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listAliasCandidates(book.id).single.evidence!
        .matchesSource(source), isTrue);
    await store.reviewAliasCandidate(proposed.id,
      approve: true, source: source, confirmedCharacterId: 'mira');
    expect(store.listCastCharacters(book.id).single.aliases, ['the Captain']);
    expect(store.listCastVoices(book.id), isEmpty);
    expect(store.listSegmentCast(book.id), isEmpty);
    expect(store.listAliasCandidates(book.id).single.status,
        AliasCandidateStatus.accepted);
  });

  test('alias collisions cannot move a nickname to another character',
      () async {
    const source = 'Anna heard the Captain approaching.';
    final file = File(p.join(root.path, 'alias-conflict.txt'));
    await file.writeAsString(source);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'anna', bookId: book.id, name: 'Anna',
    ));
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira',
    ));
    final from = source.indexOf('the Captain');
    final candidate = AliasCandidate(
      id: 'unclaimed', bookId: book.id,
      alias: 'the Captain', targetCharacterId: 'mira',
      start: from, end: from + 'the Captain'.length,
      sourceDigest: AliasCandidate.fingerprint('the Captain'),
      confidence: 0.8, status: AliasCandidateStatus.proposed,
    );
    await store.importAliasCandidates([candidate], source);
    await store.saveCastCharacter(CastCharacter(
      id: 'anna', bookId: book.id, name: 'Anna',
      aliases: const ['the Captain'],
    ));
    await expectLater(store.reviewAliasCandidate(
      'unclaimed', approve: true, source: source,
      confirmedCharacterId: 'mira',
    ), throwsStateError);
    expect(store.listCastCharacters(book.id).where((p) => p.id == 'mira')
        .single.aliases, isEmpty);
    expect(store.listAliasCandidates(book.id).single.status,
        AliasCandidateStatus.proposed);
    await expectLater(store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira',
      aliases: const ['THE CAPTAIN'],
    )), throwsStateError);
    expect(store.listCastCharacters(book.id), hasLength(2));
    await store.reviewAliasCandidate('unclaimed',
      approve: false, source: source);
    expect(store.listAliasCandidates(book.id).single.status,
        AliasCandidateStatus.rejected);
  });

  test('stale evidence blocks approval, but stale alias can be rejected',
      () async {
    const source = 'Mira becomes the Captain.';
    final file = File(p.join(root.path, 'alias-evidence.txt'));
    await file.writeAsString(source);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira',
    ));
    final from = source.indexOf('the Captain');
    await store.importAliasCandidates([
      AliasCandidate(
        id: 'stale', bookId: book.id,
        alias: 'the Captain', targetCharacterId: 'mira',
        start: from, end: from + 'the Captain'.length,
        sourceDigest: AliasCandidate.fingerprint('the Captain'),
        status: AliasCandidateStatus.proposed, confidence: 0.65,
        evidence: CastSpanEvidence(
          start: 0, end: 4, sourceDigest: CastSpan.digest('Mira'),
        ),
      ),
    ], source);
    await expectLater(store.reviewAliasCandidate('stale',
      approve: true,
      source: source.replaceFirst('Mira', 'Nora'),
      confirmedCharacterId: 'mira',
    ), throwsFormatException);
    expect(store.listCastCharacters(book.id).single.aliases, isEmpty);
    await store.reviewAliasCandidate('stale',
      approve: false, source: source.replaceFirst('Mira', 'Nora'));
    expect(store.listAliasCandidates(book.id).single.status,
        AliasCandidateStatus.rejected);
  });

  test('SQLite v10 to v11 migration retains cast, consent and discoveries',
      () async {
    const text = 'Anna met Mira.';
    final file = File(p.join(root.path, 'upgrade-alias.txt'));
    await file.writeAsString(text);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'anna', bookId: book.id, name: 'Anna',
    ));
    final from = text.indexOf('Mira');
    await store.importCharacterCandidates([
      CharacterCandidate(
        id: 'new-mira', bookId: book.id, name: 'Mira',
        start: from, end: from + 4,
        sourceDigest: CharacterCandidate.fingerprint('Mira'),
        confidence: 0.8, status: CharacterCandidateStatus.proposed,
      ),
    ], text);
    await store.configureLlmAnalysisConsent(book.id,
      allowed: true, maxInputCharacters: 1500);
    await store.reserveLlmAnalysisInput(book.id, 100);
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE alias_candidates');
    db.execute('PRAGMA user_version = 10');
    db.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.listCastCharacters(book.id).single.name, 'Anna');
    expect(store.listCharacterCandidates(book.id).single.name, 'Mira');
    expect(store.getLlmAnalysisConsent(book.id).usedInputCharacters, 100);
    expect(store.listAliasCandidates(book.id), isEmpty);
    await store.removeBook(book.id);
    expect(store.listAliasCandidates(book.id), isEmpty);
  });

}
