import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/alias_candidate.dart';
import 'package:ereader/domain/cast_merge.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/character_candidate.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory home;
  late LibraryStore store;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-merge-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  Future<String> createBook(String name, String source) async {
    final input = File(p.join(home.path, '$name.txt'));
    await input.writeAsString(source);
    final book = await store.importFile(input.path);
    return book.id;
  }

  Future<void> twoCharacters(String bookId) async {
    await store.saveCastCharacter(CastCharacter(
      id: 'survivor', bookId: bookId, name: 'Mira',
      aliases: const ['the Scout'],
    ));
    await store.saveCastCharacter(CastCharacter(
      id: 'duplicate', bookId: bookId, name: 'Captain Mira',
      aliases: const ['the Commander'],
    ));
  }

  test('merge retargets all dialogue references and preserves voice choices',
      () async {
    const source = 'Captain Mira greeted Mira. The Commander nodded.';
    final bookId = await createBook('merging', source);
    await twoCharacters(bookId);

    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'survivor', providerId: 'system',
      voiceName: 'Narrator-voice', voiceLocale: 'en-US',
    ));
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'duplicate', providerId: 'system',
      voiceName: 'Captain-voice', voiceLocale: 'en-US',
    ));
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'duplicate', providerId: 'openai-speech',
      voiceName: 'nova', voiceLocale: 'en-US',
    ));

    const quote = 'Captain Mira';
    await store.saveSegmentCast(SegmentCastAssignment(
      bookId: bookId, start: 0, end: quote.length,
      sourceDigest: SegmentCastAssignment.fingerprint(quote),
      characterId: 'duplicate',
    ));
    await store.saveManualCastSpan(CastSpan(
      id: 'precise-dialogue', bookId: bookId,
      start: 0, end: quote.length,
      sourceDigest: CastSpan.digest(quote), speakerId: 'duplicate',
      origin: CastSpanOrigin.user, status: CastSpanStatus.accepted,
      lockedByUser: true,
    ), source);

    // Approved character-discovery record must retain its new character FK.
    await store.importCharacterCandidates([
      CharacterCandidate(
        id: 'discovered-duplicate', bookId: bookId,
        name: 'Captain Mira', start: 0, end: quote.length,
        sourceDigest: CharacterCandidate.fingerprint(quote),
        confidence: 0.9, status: CharacterCandidateStatus.proposed,
      ),
    ], source);
    // The candidate is already known, so it was correctly ignored. Test
    // the FK in a separate book-approved candidate below instead.

    const unknownName = 'The Commander';
    final index = source.indexOf(unknownName);
    await store.importAliasCandidates([
      AliasCandidate(
        id: 'proposed-alias', bookId: bookId,
        alias: 'The Commander', targetCharacterId: 'duplicate',
        start: index, end: index + unknownName.length,
        sourceDigest: AliasCandidate.fingerprint(unknownName),
        confidence: 0.8, status: AliasCandidateStatus.proposed,
      ),
    ], source);
    // Already listed as an alias on duplicate; pending import is ignored.
    expect(store.listAliasCandidates(bookId), isEmpty);

    // Make a source-grounded NEW pending alias pointing at duplicate.
    const freshAlias = 'nodded';
    final aliasStart = source.indexOf(freshAlias);
    await store.importAliasCandidates([
      AliasCandidate(
        id: 'pending-alias', bookId: bookId,
        alias: freshAlias, targetCharacterId: 'duplicate',
        start: aliasStart, end: aliasStart + freshAlias.length,
        sourceDigest: AliasCandidate.fingerprint(freshAlias),
        confidence: 0.1, status: AliasCandidateStatus.proposed,
      ),
    ], source);

    final preview = store.previewCastMerge(
        bookId, 'duplicate', 'survivor');
    expect(preview.providerConflicts.map((c) => c.providerId), ['system']);
    expect(preview.resultingAliases,
      ['the Scout', 'Captain Mira', 'the Commander']);
    expect(preview.counts['dialogue_segments'], 1);
    expect(preview.counts['precise_spans'], 1);
    expect(preview.counts['proposed_alias_links'], 1);

    await store.mergeCastCharacters(CastMergeDecision(
      bookId: bookId, sourceCharacterId: 'duplicate',
      targetCharacterId: 'survivor',
      expectedSnapshotDigest: preview.snapshotDigest,
      providerChoices: const {'system': 'source'},
    ));
    final cast = store.listCastCharacters(bookId);
    expect(cast, hasLength(1));
    expect(cast.single.id, 'survivor');
    expect(cast.single.aliases,
        ['the Scout', 'Captain Mira', 'the Commander']);
    expect(store.listSegmentCast(bookId).single.characterId, 'survivor');
    expect(store.listCastSpans(bookId).single.speakerId, 'survivor');
    final voices = store.listCastVoices(bookId);
    expect(voices, hasLength(2));
    expect(voices.firstWhere((v) => v.providerId == 'system').voiceName,
        'Captain-voice');
    expect(voices.firstWhere((v) => v.providerId == 'openai-speech').voiceName,
        'nova');
    expect(store.listAliasCandidates(bookId).single.targetCharacterId,
        'survivor');

    store.dispose();
    final raw = sqlite3.open(p.join(home.path, 'library.sqlite'));
    expect(raw.select('SELECT COUNT(*) AS n FROM cast_merges')
        .first['n'], 1);
    expect(raw.select('SELECT old_character_id FROM cast_merges')
        .single['old_character_id'], 'duplicate');
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    raw.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.listSegmentCast(bookId).single.characterId, 'survivor');
  });

  test('missing voice conflict decisions never causes partial changes',
      () async {
    final bookId = await createBook('choices', 'One. Two.');
    await twoCharacters(bookId);
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'survivor', providerId: 'system',
      voiceName: 'VoiceA', voiceLocale: 'en-US'));
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'duplicate', providerId: 'system',
      voiceName: 'VoiceB', voiceLocale: 'en-US'));
    final preview = store.previewCastMerge(bookId, 'duplicate', 'survivor');

    await expectLater(store.mergeCastCharacters(CastMergeDecision(
      bookId: bookId, sourceCharacterId: 'duplicate',
      targetCharacterId: 'survivor',
      expectedSnapshotDigest: preview.snapshotDigest,
      providerChoices: const {},
    )), throwsStateError);
    expect(store.listCastCharacters(bookId), hasLength(2));
    expect(store.listCastVoices(bookId), hasLength(2));

    await store.mergeCastCharacters(CastMergeDecision(
      bookId: bookId, sourceCharacterId: 'duplicate',
      targetCharacterId: 'survivor',
      expectedSnapshotDigest: preview.snapshotDigest,
      providerChoices: const {'system': 'target'},
    ));
    expect(store.listCastVoices(bookId).single.voiceName, 'VoiceA');
  });

  test('preview becomes invalid after cast changed', () async {
    final bookId = await createBook('changed', 'A tale.');
    await twoCharacters(bookId);
    final preview = store.previewCastMerge(bookId, 'duplicate', 'survivor');
    await store.saveCastCharacter(CastCharacter(
      id: 'survivor', bookId: bookId,
      name: 'Mira the Bold', aliases: const ['the Scout'],
    ));
    await expectLater(store.mergeCastCharacters(CastMergeDecision(
      bookId: bookId, sourceCharacterId: 'duplicate',
      targetCharacterId: 'survivor',
      expectedSnapshotDigest: preview.snapshotDigest,
      providerChoices: const {},
    )), throwsStateError);
    expect(store.listCastCharacters(bookId), hasLength(2));
  });

  test('merge fails across books or onto the same character', () async {
    final bookId = await createBook('first', 'First narrative');
    final anotherId = await createBook('second', 'Second narrative');
    await twoCharacters(bookId);
    await store.saveCastCharacter(CastCharacter(
      id: 'foreign', bookId: anotherId, name: 'Visitor',
    ));
    expect(() => store.previewCastMerge(
      bookId, 'duplicate', 'foreign'), throwsStateError);
    expect(() => store.previewCastMerge(
      bookId, 'duplicate', 'duplicate'), throwsFormatException);
  });

  test('SQLite v11 upgrade adds merge audit without altering saved cast',
      () async {
    final bookId = await createBook('upgrade', 'Preserved people');
    await twoCharacters(bookId);
    store.dispose();
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    db.execute('DROP TABLE cast_merges');
    db.execute('PRAGMA user_version = 11');
    db.dispose();

    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.listCastCharacters(bookId), hasLength(2));
    final preview = store.previewCastMerge(bookId, 'duplicate', 'survivor');
    expect(preview.providerConflicts, isEmpty);
    await store.mergeCastCharacters(CastMergeDecision(
      bookId: bookId, sourceCharacterId: 'duplicate',
      targetCharacterId: 'survivor',
      expectedSnapshotDigest: preview.snapshotDigest,
      providerChoices: const {},
    ));
    expect(store.listCastCharacters(bookId), hasLength(1));
  });
}
