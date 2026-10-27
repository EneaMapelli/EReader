import 'dart:io';

/// Best-effort retry only for a fresh TEMP folder created by the current
/// test. Windows may retain handles briefly after FFI/isolate termination.
/// A sustained native lock is still a FAIL, never silently ignored.
Future<void> deleteOwnedTestTemp(Directory directory, {
  Duration deadline = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (watch.elapsed >= deadline) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Poll asynchronous native/OS-file events with real elapsed time, not
/// a fixed number of zero-delay microtask turns. Reaching the deadline
/// is an actionable assertion failure rather than a hanging test.
Future<void> waitForNativeCondition(
  bool Function() condition, {
  Duration deadline = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= deadline) {
      throw StateError('Native/IO test condition did not settle in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
