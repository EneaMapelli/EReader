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
  });
}
