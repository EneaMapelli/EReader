import 'dart:io';

import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _MissingTextDecoder implements DocumentDecoder {
  @override
  Future<DocumentContent> read(BookRecord record) async {
    throw const FormatException('No selectable text');
  }
}

void main() {
  late Directory root;
  late LibraryStore store;
  late String alpha;
  late String beta;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-fts-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final first = File(p.join(root.path, 'first.txt'));
    final second = File(p.join(root.path, 'second.txt'));
    await first.writeAsString('The friendly blue dragon sings at dawn.');
    await second.writeAsString('A dragon sleeps under the silent moon.');
    alpha = (await store.importFile(first.path)).id;
    beta = (await store.importFile(second.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('fresh v26 is opt-out, no virtual table or silent indexing', () {
    expect(store.isFullTextIndexEnabled, isFalse);
    expect(store.fullTextIndexedBooks, 0);
    expect(store.searchIndexedBookContents('dragon'), isEmpty);
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(db.select('PRAGMA user_version').single['user_version'], 26);
    expect(db.select("SELECT name FROM sqlite_master WHERE name = "
        "'library_fulltext_fts'"), isEmpty);
    db.dispose();
    expect(store.books, hasLength(2));
  });

  test('explicit opt-in indexes local TXT and returns bounded literal hits',
      () async {
    store.setFullTextIndexEnabled(true);
    expect(store.isFullTextIndexEnabled, isTrue);
    expect(store.fullTextIndexedBooks, 0);
    expect(store.fullTextPendingBooks, 2);
    final report = await store.indexNextFullTextBatch();
    expect(report.indexed, 2);
    expect(report.skipped, 0);
    expect(report.remaining, 0);
    expect(report.cancelled, isFalse);
    expect(store.fullTextIndexedBooks, 2);

    final results = store.searchIndexedBookContents('dragon');
    expect(results.map((hit) => hit.bookId).toSet(), {alpha, beta});
    for (final result in results) {
      final destination = store.fullTextJumpForHit(result.bookId, 'dragon');
      expect(destination, isNotNull);
      expect(destination!.expectedText.toLowerCase(), 'dragon');
      expect(destination.sourceOffset, greaterThan(0));
    }
    expect(store.getBook(alpha)!.progressOffset, 0);
    expect(store.getBook(beta)!.progressOffset, 0);
    expect(results.first.excerpt.toLowerCase(), contains('dragon'));
    expect(store.searchIndexedBookContents('blue dragon')
        .map((hit) => hit.bookId).toSet(), {alpha});
    expect(store.searchIndexedBookContents('dragon notexisting'), isEmpty);
    expect(store.searchIndexedBookContents(''), isEmpty);
    expect(store.searchIndexedBookContents('x' * 121), isEmpty);
    expect(store.searchIndexedBookContents('OR = --'), isEmpty);
    expect(() => store.searchIndexedBookContents('dragon', limit: 101),
        throwsRangeError);
    expect(store.books, hasLength(2));
  });

  test('full-text hit picks nearest multiword passage on selected book',
      () async {
    final path = store.getBook(alpha)!.localPath;
    final source = 'dragon in the distant opening. ' +
        ('unrelated ' * 80) +
        'A blue dragon guards the tower.';
    await File(path).writeAsString(source);
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();

    // FTS itself does not load entire sources for each row/snippet.
    final hits = store.searchIndexedBookContents('dragon blue');
    expect(hits.map((hit) => hit.bookId), contains(alpha));
    final jump = store.fullTextJumpForHit(alpha, 'dragon blue');
    expect(jump, isNotNull);
    expect(jump!.sourceOffset, source.lastIndexOf('blue'));
    expect(jump.expectedText, 'blue');
    expect(jump.validatedOffset(source), jump.sourceOffset);
    expect(store.getBook(alpha)!.progressOffset, 0);

    // A changed phrase with the same starting word is still stale.
    final changed = source.replaceFirst(
        'blue dragon guards', 'blue dracon guards');
    expect(jump.validatedOffset(changed), isNull);
    // A fresh manual change scan will purge the old FTS results.
    await File(path).writeAsString('$changed extra');
    expect(await store.refreshChangedFullTextBooks(), 1);
    expect(store.searchIndexedBookContents('blue dragon'), isEmpty);
  });

  test('opt-out drops private FTS5 table, persists after restart', () async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    store.setFullTextIndexEnabled(false);
    expect(store.isFullTextIndexEnabled, isFalse);
    expect(store.fullTextIndexedBooks, 0);
    expect(store.searchIndexedBookContents('dragon'), isEmpty);

    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(db.select("SELECT name FROM sqlite_master WHERE name = "
        "'library_fulltext_fts'"), isEmpty);
    db.dispose();
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.isFullTextIndexEnabled, isFalse);
    expect(store.books, hasLength(2));
    store.setFullTextIndexEnabled(true);
    expect(store.fullTextPendingBooks, 2);
    expect(store.searchIndexedBookContents('dragon'), isEmpty);
  });

  test('reset clears snippets and skipped-book markers, not consent',
      () async {
    store.setFullTextIndexEnabled(true);
    final skipped = await store.indexNextFullTextBatch(
        decoder: _MissingTextDecoder());
    expect(skipped.skipped, 2);
    expect(skipped.remaining, 0);
    expect(store.fullTextIndexedBooks, 0);
    store.resetFullTextIndex();
    expect(store.isFullTextIndexEnabled, isTrue);
    expect(store.fullTextPendingBooks, 2);
    expect((await store.indexNextFullTextBatch()).indexed, 2);
    expect(store.searchIndexedBookContents('dragon'), hasLength(2));
    store.resetFullTextIndex();
    expect(store.searchIndexedBookContents('dragon'), isEmpty);
    expect(store.fullTextPendingBooks, 2);
  });

  test('cancel between books leaves a resumable batch, no duplicate text',
      () async {
    store.setFullTextIndexEnabled(true);
    var completed = 0;
    final report = await store.indexNextFullTextBatch(
      shouldCancel: () => completed == 1,
      onProgress: (done, total) {
        completed = done;
        expect(total, 2);
      },
    );
    expect(report.cancelled, isTrue);
    expect(report.processed, 1);
    expect(report.remaining, 1);
    expect(store.fullTextIndexedBooks, 1);
    expect((await store.indexNextFullTextBatch()).indexed, 1);
    expect(store.searchIndexedBookContents('dragon'), hasLength(2));
    expect(store.fullTextIndexedBooks, 2);
  });

  test('explicit change check queues only modified books and drops stale hits',
      () async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    expect(await store.refreshChangedFullTextBooks(), 0);
    expect(store.fullTextPendingBooks, 0);
    final path = store.getBook(alpha)!.localPath;
    await File(path).writeAsString('A turquoise fox wakes at sunrise.');
    final changed = await store.refreshChangedFullTextBooks();
    expect(changed, 1);
    expect(store.fullTextIndexedBooks, 1);
    expect(store.fullTextPendingBooks, 1);
    expect(store.searchIndexedBookContents('blue'), isEmpty);
    expect(store.searchIndexedBookContents('dragon').single.bookId, beta);
    final reindexed = await store.indexNextFullTextBatch();
    expect(reindexed.indexed, 1);
    expect(reindexed.remaining, 0);
    expect(store.searchIndexedBookContents('turquoise').single.bookId, alpha);
    expect(store.searchIndexedBookContents('blue'), isEmpty);
    expect(await store.refreshChangedFullTextBooks(), 0);
  });

  test('changed-file recheck can stop between books without deleting others',
      () async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    final path = store.getBook(alpha)!.localPath;
    await File(path).writeAsString('A white fox.');
    var examined = 0;
    final changed = await store.refreshChangedFullTextBooks(
      shouldCancel: () => examined > 0,
      onProgress: (done, total) {
        examined = done;
        expect(total, 2);
      },
    );
    expect(examined, 1);
    expect(changed, inInclusiveRange(0, 1));
    // A second explicit check completes any interrupted inspection.
    await store.refreshChangedFullTextBooks();
    expect(store.fullTextPendingBooks, 1);
    expect((await store.indexNextFullTextBatch()).indexed, 1);
  });

  test('book removal purges indexed text and keeps unrelated books',
      () async {
    store.setFullTextIndexEnabled(true);
    await store.indexNextFullTextBatch();
    await store.removeBook(alpha);
    expect(store.fullTextIndexedBooks, 1);
    expect(store.searchIndexedBookContents('blue'), isEmpty);
    expect(store.searchIndexedBookContents('dragon').single.bookId, beta);
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(db.select(
      'SELECT COUNT(*) AS n FROM library_fulltext_fts WHERE book_id = ?',
      [alpha],
    ).single['n'], 0);
    db.dispose();
  });

  test('v25 upgrade creates only opt-out state, preserving book metadata',
      () async {
    store.setBookFavorite(alpha, true);
    store.dispose();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    db.execute('DROP TABLE library_fulltext_jobs');
    db.execute('DROP TABLE library_fulltext_settings');
    db.execute('PRAGMA user_version = 25');
    db.dispose();

    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    expect(store.isFullTextIndexEnabled, isFalse);
    expect(store.getBook(alpha)!.isFavorite, isTrue);
    expect(store.books, hasLength(2));
    final check = sqlite3.open(p.join(root.path, 'library.sqlite'));
    expect(check.select('PRAGMA user_version').single['user_version'], 26);
    expect(check.select("SELECT name FROM sqlite_master WHERE name = "
        "'library_fulltext_fts'"), isEmpty);
    check.dispose();
  });

  test('limits and disabled indexing reject changes without altering books',
      () async {
    await expectLater(store.indexNextFullTextBatch(), throwsStateError);
    store.setFullTextIndexEnabled(true);
    await expectLater(store.indexNextFullTextBatch(maxBooks: 21),
        throwsRangeError);
    expect(store.fullTextIndexedBooks, 0);
    expect(store.books, hasLength(2));
  });
}
