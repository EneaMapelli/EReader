import 'dart:async';

import '../data/library_store.dart';
import '../domain/reading_activity.dart';

/// Reader-owned local activity sampler. No book text, cloud requests,
/// global services, background wakeups or app-wide motion tracking.
/// Caller updates the desired mode on visibility/player/input transitions.
class ReaderActivityTracker {
  ReaderActivityTracker({
    required this.store,
    required this.bookId,
    required ReadingActivityMode? Function() mode,
    Duration interval = const Duration(seconds: 15),
  }) : _mode = mode {
    _stopwatch.start();
    _active = _mode();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  final LibraryStore store;
  final String bookId;
  final ReadingActivityMode? Function() _mode;
  final ReadingActivityAccumulator _accumulator = ReadingActivityAccumulator();
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  ReadingActivityMode? _active;
  bool _closed = false;

  /// Flush OLD mode first, so a new Play/Pause never relabels the prior
  /// interval. Stopwatch (monotonic) is independent of system clock changes.
  void refresh() {
    if (_closed) return;
    _flush();
    _active = _mode();
  }

  void _flush() {
    final elapsed = _stopwatch.elapsed;
    _stopwatch
      ..reset()
      ..start();
    final active = _active;
    final seconds = _accumulator.record(elapsed, active);
    if (seconds == 0 || active == null) return;
    try {
      store.recordReadingActivity(bookId, active, seconds);
    } catch (_) {
      // Local storage may fail during shutdown or if the disk fills.
      // Optional statistics must never disrupt the reader or native TTS.
    }
  }

  void dispose() {
    if (_closed) return;
    _flush();
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    _accumulator.dispose();
  }
}
