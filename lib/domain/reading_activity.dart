/// Local aggregate modes. TTS is measured as player-requested activity,
/// not acoustic verification or a count of provider-billed audio seconds.
enum ReadingActivityMode { visual, tts }

/// A summarized local calendar day (not a list of user actions).
class ReadingActivityDay {
  const ReadingActivityDay({
    required this.date,
    this.visualSeconds = 0,
    this.ttsSeconds = 0,
  });

  /// Local date YYYY-MM-DD; no time, content or device identity is stored.
  final String date;
  final int visualSeconds;
  final int ttsSeconds;
  int get totalSeconds => visualSeconds + ttsSeconds;
}

class WeeklyReadingActivity {
  const WeeklyReadingActivity({
    required this.days,
    required this.goalMinutes,
  });

  /// Ordered six previous local dates followed by today.
  final List<ReadingActivityDay> days;
  final int goalMinutes;

  int get visualSeconds =>
      days.fold(0, (sum, day) => sum + day.visualSeconds);
  int get ttsSeconds =>
      days.fold(0, (sum, day) => sum + day.ttsSeconds);
  int get totalSeconds => visualSeconds + ttsSeconds;
  int get daysMeetingGoal => goalMinutes == 0 ? 0 :
      days.where((day) => day.totalSeconds >= goalMinutes * 60).length;

  ReadingActivityDay get today => days.last;
}

String readingLocalDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Converts monotonic elapsed time into bounded whole-second increments.
/// Unobserved/suspended gaps are clipped; this is deliberately conservative.
/// A remainder is retained separately for each mode across short transitions.
class ReadingActivityAccumulator {
  ReadingActivityAccumulator({
    this.maxPulse = const Duration(seconds: 30),
  });

  final Duration maxPulse;
  final Map<ReadingActivityMode, int> _remainders = {};
  bool _disposed = false;

  int record(Duration elapsed, ReadingActivityMode? mode) {
    if (_disposed || mode == null || elapsed.isNegative ||
        elapsed == Duration.zero) return 0;
    final clipped = elapsed > maxPulse ? maxPulse : elapsed;
    final total = (_remainders[mode] ?? 0) + clipped.inMicroseconds;
    final seconds = total ~/ Duration.microsecondsPerSecond;
    _remainders[mode] = total % Duration.microsecondsPerSecond;
    return seconds;
  }

  void dispose() {
    _disposed = true;
    _remainders.clear();
  }
}

class BookReadingActivityTotals {
  const BookReadingActivityTotals({
    required this.bookId,
    required this.title,
    required this.visualSeconds,
    required this.ttsSeconds,
  });

  final String bookId;
  final String title;
  final int visualSeconds;
  final int ttsSeconds;
  int get totalSeconds => visualSeconds + ttsSeconds;
}

/// Human-readable, non-rounded duration; sub-minute activity remains visible.
String formatReadingActivityDuration(int seconds) {
  if (seconds < 0) throw RangeError.range(seconds, 0, null, 'seconds');
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}
