import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-speech-crash-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> book(String filename, String text) async {
    final source = File(p.join(root.path, filename));
    await source.writeAsString(text, flush: true);
    return (await store.importFile(source.path)).id;
  }

  Future<void> restart() async {
    store.dispose(); // Simulate process loss; NO reader.pause()/dispose().
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  }

  test('crashed narration is offered once; no speech is restarted', () async {
    final id = await book('novel.txt', 'Beginning and following passage.');
    await store.markBookOpened(id);
    store.recordSpeechSegmentStart(id, 10,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 10),
    );
    expect(store.interruptedNarrationBook, isNull,
      reason: 'A live process never mistakes its own session for a crash');
    await restart();
    final interrupted = store.interruptedNarrationBook;
    expect(interrupted?.id, id);
    expect(interrupted?.progressOffset, 10);
    expect(interrupted?.progressAnchor?.localOffset, 10);
    // SQLite marker was consumed at startup, so another restart shows none.
    await restart();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('normal pause, completion or explicit stop clears crash marker',
      () async {
    final id = await book('normal.txt', 'A book with several sentences.');
    store.recordSpeechSegmentStart(id, 2);
    store.clearSpeechRecoveryMarker(id);
    await restart();
    expect(store.interruptedNarrationBook, isNull);
    expect(store.getBook(id)!.progressOffset, 2);
  });

  test('reopening interrupted book dismisses notice but never auto-plays',
      () async {
    final id = await book('reopen.txt', 'A source.');
    store.recordSpeechSegmentStart(id, 3);
    await restart();
    expect(store.interruptedNarrationBook?.id, id);
    await store.markBookOpened(id);
    expect(store.interruptedNarrationBook, isNull);
    expect(store.getBook(id)!.progressOffset, 3);
    // No new active narration is persisted by marking a book as opened.
    await restart();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('dismiss notice is memory-only and does not alter reading anchor',
      () async {
    final id = await book('dismiss.txt', 'Source text.');
    store.recordSpeechSegmentStart(id, 5,
      anchor: const ReadingAnchor(
        kind: AnchorKind.text, sourceId: 'body', localOffset: 5),
    );
    await restart();
    store.dismissInterruptedNarration();
    expect(store.interruptedNarrationBook, isNull);
    expect(store.getBook(id)!.progressAnchor?.localOffset, 5);
    await restart();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('old reader cannot clear a newer book checkpoint', () async {
    final first = await book('first.txt', 'First source.');
    final second = await book('second.txt', 'Second source.');
    store.recordSpeechSegmentStart(first, 1);
    store.recordSpeechSegmentStart(second, 4);
    store.clearSpeechRecoveryMarker(first);
    await restart();
    expect(store.interruptedNarrationBook?.id, second);
    expect(store.getBook(first)!.progressOffset, 1);
    expect(store.getBook(second)!.progressOffset, 4);
  });

  test('deleting book cascades cleanup of its recovery checkpoint',
      () async {
    final id = await book('delete.txt', 'Deleted source.');
    store.recordSpeechSegmentStart(id, 3);
    await store.removeBook(id);
    await restart();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('missing original managed file does not offer a broken shortcut',
      () async {
    final id = await book('lost.txt', 'Content later removed.');
    store.recordSpeechSegmentStart(id, 4);
    final managed = store.getBook(id)!.localPath;
    await File(managed).delete();
    await restart();
    expect(store.interruptedNarrationBook, isNull);
    expect(store.getBook(id)!.progressOffset, 4);
  });

  test('unknown book fails atomically without a zombie crash marker',
      () async {
    expect(
      () => store.recordSpeechSegmentStart('not-a-book', 6),
      throwsStateError,
    );
    expect(
      () => store.recordSpeechSegmentStart('not-a-book', -1),
      throwsArgumentError,
    );
    await restart();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('SQLite v15 upgrade preserves visual PDF position and TTS anchor',
      () async {
    final source = File(p.join(root.path, 'last.pdf'));
    await source.writeAsBytes('%PDF-1.4\nmock\n'.codeUnits);
    final id = (await store.importFile(source.path)).id;
    store.savePdfVisualPage(id, 17);
    await store.savePosition(id, 9,
      anchor: const ReadingAnchor(
        kind: AnchorKind.pdfPage, sourceId: '3', localOffset: 2),
    );
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE speech_recovery_marker');
    db.execute('PRAGMA user_version = 15');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.interruptedNarrationBook, isNull);
    expect(store.getPdfVisualPage(id), 17);
    expect(store.getBook(id)!.progressAnchor?.sourceId, '3');
    expect(store.getBook(id)!.progressOffset, 9);
    store.recordSpeechSegmentStart(id, 11);
    await restart();
    expect(store.interruptedNarrationBook?.id, id);
    expect(store.getPdfVisualPage(id), 17);
    expect(store.getBook(id)!.progressOffset, 11);
  });

  test('checkpoint records only book ID and timestamp, not secret or text',
      () async {
    final id = await book('privacy.txt', 'Sensitive words not for storage.');
    store.recordSpeechSegmentStart(id, 1);
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    final row = db.select('SELECT * FROM speech_recovery_marker').single;
    expect(row.keys.toSet(), {'slot', 'book_id', 'started_at'});
    expect(row['book_id'], id);
    expect(row['slot'], 1);
    expect(row.values.join(' '), isNot(contains('Sensitive words')));
    db.dispose();
  });
}
