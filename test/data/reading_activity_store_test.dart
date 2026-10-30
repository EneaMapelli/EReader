import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/reading_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('local date key stays stable across calendar boundaries', () {
    expect(readingLocalDate(DateTime(2026, 10, 30, 23, 59)),
        '2026-10-30');
    expect(readingLocalDate(DateTime(2026, 11, 1, 0, 0)),
        '2026-11-01');
  });

  test('bounded monotonic pulses, separate carry and ignored idle', () {
    final acc = ReadingActivityAccumulator();
    expect(acc.record(const Duration(milliseconds: 400),
        ReadingActivityMode.visual), 0);
    expect(acc.record(const Duration(milliseconds: 700),
        ReadingActivityMode.visual), 1);
    expect(acc.record(const Duration(hours: 2),
        ReadingActivityMode.visual), 30);
    expect(acc.record(const Duration(milliseconds: 900),
        ReadingActivityMode.tts), 0);
    expect(acc.record(const Duration(seconds: 12), null), 0);
    expect(acc.record(const Duration(milliseconds: 200),
        ReadingActivityMode.tts), 1);
    expect(acc.record(const Duration(seconds: -1),
        ReadingActivityMode.visual), 0);
    acc.dispose();
    expect(acc.record(const Duration(seconds: 10),
        ReadingActivityMode.visual), 0);
  });

  group('SQLite aggregate and goal', () {
    late Directory home;
    late LibraryStore store;
    late String bookId;
    setUp(() async {
      home = await Directory.systemTemp.createTemp('ereader-activity-');
      store = LibraryStore(homeDirectory: home);
      await store.initialize();
      final sample = File(p.join(home.path, 'one.txt'));
      await sample.writeAsString('An original local text book.');
      bookId = (await store.importFile(sample.path)).id;
    });
    tearDown(() async {
      store.dispose();
      if (await home.exists()) await home.delete(recursive: true);
    });

    test('fresh schema v23 has default 20 minute goal, empty days', () {
      final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
      expect(db.select('PRAGMA user_version').single['user_version'], 23);
      db.dispose();
      final stats = store.weeklyReadingActivity(now: DateTime(2026, 10, 30));
      expect(stats.goalMinutes, 20);
      expect(stats.days, hasLength(7));
      expect(stats.totalSeconds, 0);
    });

    test('visual and TTS seconds persist per day and are never doubled', () async {
      final at = DateTime(2026, 10, 30, 12);
      store.recordReadingActivity(bookId, ReadingActivityMode.visual, 15,
          at: at);
      store.recordReadingActivity(bookId, ReadingActivityMode.visual, 25,
          at: at);
      store.recordReadingActivity(bookId, ReadingActivityMode.tts, 20,
          at: at);
      var activity = store.weeklyReadingActivity(now: at);
      expect(activity.today.visualSeconds, 40);
      expect(activity.today.ttsSeconds, 20);
      expect(activity.daysMeetingGoal, 0);
      store.saveDailyReadingGoalMinutes(1);
      expect(store.weeklyReadingActivity(now: at).daysMeetingGoal, 1);

      store.dispose();
      store = LibraryStore(homeDirectory: home);
      await store.initialize();
      activity = store.weeklyReadingActivity(now: at);
      expect(activity.goalMinutes, 1);
      expect(activity.today.totalSeconds, 60);
    });

    test('reject unknown book, zero/large increments and invalid goal', () {
      expect(() => store.recordReadingActivity('missing',
          ReadingActivityMode.visual, 15), throwsStateError);
      expect(() => store.recordReadingActivity(bookId,
          ReadingActivityMode.visual, 0), throwsRangeError);
      expect(() => store.recordReadingActivity(bookId,
          ReadingActivityMode.visual, 31), throwsRangeError);
      expect(() => store.saveDailyReadingGoalMinutes(-1), throwsRangeError);
      expect(() => store.saveDailyReadingGoalMinutes(241), throwsRangeError);
      expect(store.weeklyReadingActivity().totalSeconds, 0);
    });

    test('removing a book cascades its activity, not other books', () async {
      final two = File(p.join(home.path, 'two.txt'));
      await two.writeAsString('Other content.');
      final other = (await store.importFile(two.path)).id;
      final now = DateTime(2026, 10, 30, 12);
      store.recordReadingActivity(bookId, ReadingActivityMode.visual, 10,
          at: now);
      store.recordReadingActivity(other, ReadingActivityMode.tts, 8,
          at: now);
      await store.removeBook(bookId);
      final result = store.weeklyReadingActivity(now: now);
      expect(result.visualSeconds, 0);
      expect(result.ttsSeconds, 8);
    });

    test('idempotent v22 migration preserves manual shelf and progress',
        () async {
      await store.savePosition(bookId, 8);
      store.dispose();
      final db = sqlite3.open(p.join(home.path, 'library.sqlite'));
      db.execute('DROP TABLE reading_activity_daily');
      db.execute('DROP TABLE reading_activity_settings');
      db.execute('PRAGMA user_version = 22');
      db.dispose();
      store = LibraryStore(homeDirectory: home);
      await store.initialize();
      expect(store.getBook(bookId)!.progressOffset, 8);
      expect(store.weeklyReadingActivity().goalMinutes, 20);
      store.recordReadingActivity(bookId, ReadingActivityMode.tts, 10);
      expect(store.weeklyReadingActivity().ttsSeconds, 10);
    });
    test('weekly scope isolates each book from other books and validates IDs',
        () async {
      final otherFile = File(p.join(home.path, 'another.txt'));
      await otherFile.writeAsString('Distinct sample for another book.');
      final otherId = (await store.importFile(otherFile.path)).id;
      final today = DateTime(2026, 10, 30, 12);
      store.recordReadingActivity(bookId, ReadingActivityMode.visual, 12,
          at: today);
      store.recordReadingActivity(bookId, ReadingActivityMode.tts, 9,
          at: today);
      store.recordReadingActivity(otherId, ReadingActivityMode.tts, 27,
          at: today);
      expect(store.weeklyReadingActivity(now: today).totalSeconds, 48);
      final one = store.weeklyReadingActivity(now: today, bookId: bookId);
      expect(one.visualSeconds, 12);
      expect(one.ttsSeconds, 9);
      final other = store.weeklyReadingActivity(now: today, bookId: otherId);
      expect(other.visualSeconds, 0);
      expect(other.ttsSeconds, 27);
      expect(() => store.weeklyReadingActivity(bookId: 'invalid'),
          throwsStateError);
    });

    test('weekly ranking excludes inactive books and ties sort by title',
        () async {
      final now = DateTime(2026, 10, 30, 12);
      final fileA = File(p.join(home.path, 'a.txt'));
      final fileB = File(p.join(home.path, 'b.txt'));
      await fileA.writeAsString('Unique alpha contents.');
      await fileB.writeAsString('Unique beta contents.');
      final alpha = (await store.importFile(fileA.path)).id;
      final beta = (await store.importFile(fileB.path)).id;
      store.updateBookMetadata(alpha, title: 'Alpha');
      store.updateBookMetadata(beta, title: 'Beta');
      store.recordReadingActivity(alpha, ReadingActivityMode.tts, 21,
          at: now);
      store.recordReadingActivity(beta, ReadingActivityMode.visual, 21,
          at: now);
      store.recordReadingActivity(bookId, ReadingActivityMode.tts, 29,
          at: DateTime(2026, 10, 20));

      final results = store.mostActiveReadingBooks(now: now);
      expect(results.map((e) => e.title), ['Alpha', 'Beta']);
      expect(results.map((e) => e.totalSeconds), [21, 21]);
      expect(store.mostActiveReadingBooks(now: now, limit: 1),
          hasLength(1));
      expect(() => results.clear(), throwsUnsupportedError);
      expect(() => store.mostActiveReadingBooks(limit: 0),
          throwsRangeError);
      expect(() => store.mostActiveReadingBooks(limit: 51),
          throwsRangeError);
    });

    test('per-book all-time sums survive restart/rename; delete cascades',
        () async {
      final old = DateTime(2026, 9, 5, 14);
      final now = DateTime(2026, 10, 30, 12);
      store.recordReadingActivity(bookId, ReadingActivityMode.visual, 23,
          at: old);
      store.recordReadingActivity(bookId, ReadingActivityMode.tts, 15,
          at: now);
      store.updateBookMetadata(bookId, title: 'Updated title');
      var total = store.bookReadingLifetimeTotals(bookId);
      expect(total.title, 'Updated title');
      expect(total.visualSeconds, 23);
      expect(total.ttsSeconds, 15);
      expect(total.totalSeconds, 38);
      expect(store.weeklyReadingActivity(now: now, bookId: bookId)
          .totalSeconds, 15);
      store.dispose();
      store = LibraryStore(homeDirectory: home);
      await store.initialize();
      total = store.bookReadingLifetimeTotals(bookId);
      expect(total.totalSeconds, 38);
      await store.removeBook(bookId);
      expect(() => store.bookReadingLifetimeTotals(bookId),
          throwsStateError);
    });

  });
}
