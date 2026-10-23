import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/dialogue_turn_review.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;
  late LibraryStore store;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ereader-turns-');
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await home.exists()) await home.delete(recursive: true);
  });

  test('manual whole-turn label survives persistence and never rewrites text',
      () async {
    const source = '— Ciao!\n— Aspetta—\n«Cosa?»';
    final file = File(p.join(home.path, 'turns.txt'));
    await file.writeAsString(source);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira',
    ));

    List<DialogueReviewTurn> inspect() =>
        const DialogueTurnReviewPlanner().build(
          bookId: book.id, source: source, from: 0, to: source.length,
          reachesScopeEnd: true,
          precise: store.listCastSpans(book.id),
          legacy: store.listSegmentCast(book.id),
          offsetFromAnchor: (_) => null,
        );

    expect(inspect(), hasLength(3));
    final target = inspect().first;
    expect(target.fullyAttributed, isFalse);
    expect(target.hasUnknown, isTrue);
    await store.saveManualCastSpan(CastSpan(
      id: 'turn-first', bookId: book.id,
      start: target.start, end: target.end,
      sourceDigest: CastSpan.digest(target.text),
      speakerId: 'mira', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
    ), source);

    expect(inspect().first.fullyAttributed, isTrue);
    expect(inspect().first.labels.single.speakerId, 'mira');
    expect(inspect()[1].hasUnknown, isTrue);
    expect(inspect()[1].ending, DialogueEnd.interrupted);
    expect(await file.readAsString(), source);

    store.dispose();
    store = LibraryStore(homeDirectory: home);
    await store.initialize();
    expect(inspect().first.labels.single.speakerId, 'mira');
  });

  test('manual locks cannot be replaced by a second overlapping turn label',
      () async {
    const source = '«First part, second part.»';
    final file = File(p.join(home.path, 'overlap.txt'));
    await file.writeAsString(source);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira'));
    await store.saveCastCharacter(CastCharacter(
      id: 'anna', bookId: book.id, name: 'Anna'));
    final existing = CastSpan(
      id: 'original', bookId: book.id,
      start: source.indexOf('First'), end: source.indexOf('First') + 5,
      sourceDigest: CastSpan.digest('First'),
      speakerId: 'mira', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
    );
    await store.saveManualCastSpan(existing, source);

    final dialogue = const DialogueTurnReviewPlanner().build(
      bookId: book.id, source: source,
      from: 0, to: source.length, reachesScopeEnd: true,
      precise: store.listCastSpans(book.id), legacy: const [],
      offsetFromAnchor: (_) => null,
    ).single;
    expect(dialogue.isPartiallyAttributed, isTrue);
    await expectLater(store.saveManualCastSpan(CastSpan(
      id: 'second', bookId: book.id,
      start: dialogue.start, end: dialogue.end,
      sourceDigest: CastSpan.digest(dialogue.text),
      speakerId: 'anna', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
    ), source), throwsStateError);
    expect(store.listCastSpans(book.id), hasLength(1));
    expect(store.listCastSpans(book.id).single.speakerId, 'mira');
  });

  test('stale or forged turn source cannot be assigned', () async {
    const source = '«Hello, world!»';
    final file = File(p.join(home.path, 'stale.txt'));
    await file.writeAsString(source);
    final book = await store.importFile(file.path);
    await store.saveCastCharacter(CastCharacter(
      id: 'mira', bookId: book.id, name: 'Mira'));
    await expectLater(store.saveManualCastSpan(CastSpan(
      id: 'wrong', bookId: book.id, start: 0, end: source.length,
      sourceDigest: CastSpan.digest('«False, world!»'),
      speakerId: 'mira', origin: CastSpanOrigin.user,
      status: CastSpanStatus.accepted, lockedByUser: true,
    ), source), throwsFormatException);
    expect(store.listCastSpans(book.id), isEmpty);
  });
}
