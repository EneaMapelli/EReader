import 'dart:convert';
import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:crypto/crypto.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/pronunciation_rule.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/book_bookmark.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/domain/cast_span.dart';
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

}
