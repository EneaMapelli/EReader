import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// Deletes ONLY per-utterance directories explicitly created by the current
/// speech-engine instance. Never sweeps the system temp root or arbitrary
/// book/user folders. No WAV contents or paths are logged or uploaded.
typedef OfflineWaveDirectoryDelete = Future<void> Function(Directory folder);

Future<void> _deleteOwnedWaveDirectory(Directory folder) async {
  final kind = await FileSystemEntity.type(folder.path, followLinks: false);
  if (kind == FileSystemEntityType.notFound) return;
  if (kind != FileSystemEntityType.directory) {
    // Refuse to traverse replaced symlinks, files or unexpected path types.
    throw FileSystemException('Unsafe offline WAV temporary directory');
  }
  await folder.delete(recursive: true);
}

/// Bounded retry queue for Windows WAVs still held by a native decoder.
///
/// An entry becomes eligible ONLY after the decoder's Play/Stop/Dispose
/// contract has settled and the engine explicitly releases that directory.
/// Each retry pass visits at most [retryBatchSize] entries and rotates
/// failed ones to avoid starving later, newly unlocked directories.
/// Admission fails closed before generating unbounded orphaned WAVs.
class OfflineWavCleanup {
  OfflineWavCleanup({
    this.maxPending = 32,
    this.retryBatchSize = 4,
    OfflineWaveDirectoryDelete? deleteDirectory,
  })  : assert(maxPending > 0),
        assert(retryBatchSize > 0),
        _deleteDirectory = deleteDirectory ?? _deleteOwnedWaveDirectory;

  final int maxPending;
  final int retryBatchSize;
  final OfflineWaveDirectoryDelete _deleteDirectory;
  final LinkedHashMap<String, Directory> _pending =
      LinkedHashMap<String, Directory>();
  Future<void>? _retrying;

  int get pendingCount => _pending.length;

  Future<void> release(Directory? folder) async {
    if (folder == null) return;
    final path = folder.path;
    try {
      await _deleteDirectory(folder);
      _pending.remove(path);
    } on FileSystemException {
      // Retain the exact owned folder, never a generic path to rescan.
      _pending.remove(path);
      _pending[path] = folder;
    }
  }

  Future<void> _retrySome(int count) async {
    final paths = _pending.keys.take(count).toList(growable: false);
    for (final path in paths) {
      final folder = _pending[path];
      if (folder == null) continue;
      try {
        await _deleteDirectory(folder);
        _pending.remove(path);
      } on FileSystemException {
        // Rotate failed entries to the tail. Otherwise one permanently
        // locked WAV could starve every subsequent unlocked directory.
        _pending.remove(path);
        _pending[path] = folder;
      }
    }
  }

  Future<void> retryPending({int? maxAttempts}) {
    final ongoing = _retrying;
    if (ongoing != null) return ongoing;
    final count = maxAttempts ?? retryBatchSize;
    if (count < 0) throw ArgumentError.value(count, 'maxAttempts');
    if (count == 0 || _pending.isEmpty) return Future<void>.value();
    final current = _retrySome(count);
    _retrying = current;
    return current.whenComplete(() {
      if (identical(_retrying, current)) _retrying = null;
    });
  }

  Future<void> ensureCapacity() async {
    await retryPending();
    if (_pending.length >= maxPending) {
      throw StateError(
        'Too many private offline WAV folders awaiting native cleanup');
    }
  }
}
