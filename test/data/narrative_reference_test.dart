import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/cast_merge.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/narrative_reference.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/narrative_antecedent_finder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory home;
  late LibraryStore store;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-coref-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  const text = 'Mira entered. She spoke to the captain.';

  Future<String> createBook(String label) async {
    final file = File(p.join(home.path, label + '.txt'));
    await file.writeAsString(text);
    final book = await store.importFile(file.path);
    return book.id;
  }

  NarrativeReferenceCandidate proposal(String bookId, {
    String id = 'ref1',
    String? suggested = 'mira',
    bool ambiguous = false,
    CastSpanEvidence? evidence,
  }) {
    const quote = 'She';
    final start = text.indexOf(quote);
    return NarrativeReferenceCandidate(
      id: id, bookId: bookId,
      start: start, end: start + quote.length,
      referenceText: quote,
      sourceDigest: CastSpan.digest(quote),
      kind: NarrativeReferenceKind.pronoun,
      proposedCharacterId: suggested,
      status: NarrativeReferenceStatus.proposed,
      confidence: ambiguous ? 0 : 0.75,
      ambiguous: ambiguous,
      evidence: evidence,
    );
  }

  Future<void> createCast(String bookId) async {
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: bookId, name: 'Mira'));
    await store.saveCastCharacter(CastCharacter(
      id: 'anna', bookId: bookId, name: 'Anna'));
  }

  test('LLM coreference proposals never create speaker voice assignments',
      () async {
    final book = await createBook('metadata');
    await createCast(book);
    await store.importNarrativeReferences(
        [proposal(book)], text);
    expect(store.listCastSpans(book), isEmpty);
    expect(store.listSegmentCast(book), isEmpty);
    expect(store.listCastVoices(book), isEmpty);
    expect(store.listNarrativeReferences(book).single.status,
        NarrativeReferenceStatus.proposed);

    await store.reviewNarrativeReference(
      'ref1', approve: true, source: text,
      confirmedCharacterId: 'mira');
    final saved = store.listNarrativeReferences(book).single;
    expect(saved.status, NarrativeReferenceStatus.accepted);
    expect(saved.approvedCharacterId, 'mira');
    expect(store.listCastSpans(book), isEmpty);
    expect(store.listSegmentCast(book), isEmpty);
    expect(store.listCastVoices(book), isEmpty);

    store.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.listNarrativeReferences(book).single.approvedCharacterId,
        'mira');
  });

  test('model disagreements can be resolved only by manual cast selection',
      () async {
    final book = await createBook('ambiguous');
    await createCast(book);
    await store.importNarrativeReferences(
      [proposal(book, suggested: null, ambiguous: true)], text);
    final saved = store.listNarrativeReferences(book).single;
    expect(saved.ambiguous, isTrue);
    expect(saved.proposedCharacterId, isNull);
    await expectLater(store.reviewNarrativeReference(
      saved.id, approve: true, source: text,
      confirmedCharacterId: 'foreign-book-id'), throwsStateError);
    expect(store.listNarrativeReferences(book).single.status,
        NarrativeReferenceStatus.proposed);
    await store.reviewNarrativeReference(
      saved.id, approve: true, source: text,
      confirmedCharacterId: 'anna');
    expect(store.listNarrativeReferences(book).single.approvedCharacterId,
        'anna');
  });

  test('stale source/evidence blocks approval; rejection always works',
      () async {
    final book = await createBook('stale');
    await createCast(book);
    await store.importNarrativeReferences([
      proposal(book, evidence: CastSpanEvidence(
        start: 0, end: 4, sourceDigest: CastSpan.digest('Mira'),
      )),
    ], text);
    await expectLater(store.reviewNarrativeReference('ref1',
      approve: true, source: text.replaceFirst('Mira', 'Anna'),
      confirmedCharacterId: 'mira'), throwsFormatException);
    expect(store.listNarrativeReferences(book).single.status,
        NarrativeReferenceStatus.proposed);
    await store.reviewNarrativeReference('ref1', approve: false,
      source: text.replaceFirst('Mira', 'Anna'));
    expect(store.listNarrativeReferences(book).single.status,
        NarrativeReferenceStatus.rejected);
  });

  test('second LLM run cannot overwrite existing reviewer decision', () async {
    final book = await createBook('duplicate');
    await createCast(book);
    await store.importNarrativeReferences([proposal(book)], text);
    await store.reviewNarrativeReference(
      'ref1', approve: true, source: text,
      confirmedCharacterId: 'mira');
    await store.importNarrativeReferences([
      proposal(book, id: 'second', suggested: 'anna'),
    ], text);
    final all = store.listNarrativeReferences(book);
    expect(all, hasLength(1));
    expect(all.single.approvedCharacterId, 'mira');
  });

  test('cross-book suggestion and invalid evidence cannot be imported',
      () async {
    final book = await createBook('other');
    await createCast(book);
    final wrong = proposal(book, id: 'wrong',
      suggested: 'character-from-another-book');
    await expectLater(store.importNarrativeReferences([wrong], text),
        throwsStateError);
    final invalid = proposal(book, id: 'invalid',
      evidence: CastSpanEvidence(
        start: 0, end: 4, sourceDigest: CastSpan.digest('Anna'),
      ));
    await expectLater(store.importNarrativeReferences([invalid], text),
        throwsFormatException);
    expect(store.listNarrativeReferences(book), isEmpty);
  });

  test('manual duplicate-identity merge preserves reviewed and pending refs',
      () async {
    final book = await createBook('merge');
    await createCast(book);
    await store.importNarrativeReferences([
      proposal(book, id: 'accepted'),
      NarrativeReferenceCandidate(
        id: 'waiting', bookId: book,
        start: text.indexOf('the captain'),
        end: text.indexOf('the captain') + 'the captain'.length,
        referenceText: 'the captain',
        sourceDigest: CastSpan.digest('the captain'),
        kind: NarrativeReferenceKind.titleOrDescription,
        status: NarrativeReferenceStatus.proposed,
        proposedCharacterId: 'mira',
        confidence: 0.55,
      ),
    ], text);
    await store.reviewNarrativeReference(
      'accepted', approve: true, source: text,
      confirmedCharacterId: 'mira');
    final preview = store.previewCastMerge(book, 'mira', 'anna');
    expect(preview.counts['proposed_narrative_references'], 2);
    expect(preview.counts['approved_narrative_references'], 1);
    await store.mergeCastCharacters(CastMergeDecision(
      bookId: book, sourceCharacterId: 'mira',
      targetCharacterId: 'anna',
      expectedSnapshotDigest: preview.snapshotDigest,
      providerChoices: const {},
    ));
    final refs = store.listNarrativeReferences(book);
    expect(refs, hasLength(2));
    expect(refs.every((ref) => ref.proposedCharacterId == 'anna'), isTrue);
    expect(refs.singleWhere((ref) => ref.id == 'accepted')
        .approvedCharacterId, 'anna');
    // The offline antecedent view follows the merged stable character ID,
    // without creating any new voice or model-generated speaker attribution.
    final from = text.indexOf('the captain');
    final hints = const NarrativeAntecedentFinder().inspect(
      bookId: book, source: text, scopeStart: 0,
      referenceStart: from, referenceEnd: from + 'the captain'.length,
      cast: store.listCastCharacters(book),
      reviewedReferences: refs,
    );
    expect(hints.cues, hasLength(1));
    expect(hints.cues.single.characterId, 'anna');
    expect(hints.cues.single.matchedText, 'She');
    expect(hints.cues.single.kind,
        AntecedentCueKind.reviewedNarrativeLink);
  });

  test('SQLite v12-to-v13 migration retains book, cast and voice history',
      () async {
    final book = await createBook('migrate');
    await createCast(book);
    await store.saveCastVoice(const CastVoiceAssignment(
      characterId: 'mira', providerId: 'system',
      voiceName: 'English Voice', voiceLocale: 'en-US',
    ));
    store.dispose();
    final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
    db.execute('DROP TABLE narrative_references');
    db.execute('PRAGMA user_version = 12');
    db.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(store.listCastCharacters(book), hasLength(2));
    expect(store.listCastVoices(book).single.voiceName, 'English Voice');
    expect(store.listNarrativeReferences(book), isEmpty);
    await store.importNarrativeReferences([proposal(book)], text);
    await store.removeBook(book);
    expect(store.listNarrativeReferences(book), isEmpty);
  });
}
