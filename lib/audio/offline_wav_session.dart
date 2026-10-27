import 'dart:io';

import 'package:path/path.dart' as p;

/// Only WAVs created in new marked, locked sessions can be recovered.
/// Legacy unmarked temporary files are deliberately NOT swept.
class OfflineWavSession {
  OfflineWavSession._(this.directory, this._lease);

  static const sessionPrefix = 'ereader-wav-session-v1-';
  static const markerName = '.ereader-wav-v1';
  static const leaseName = '.ereader-lease';
  static const markerContent = 'EReader private WAV session v1\n';
  static const maxScannedSessions = 16;
  static const maxClipsPerSession = 64;
  static const maxRootEntries = 512;

  // POSIX native locking semantics can permit two handles owned by the
  // SAME process to acquire a record lock. This local registry prevents
  // in-process engine instances from reclaiming each other's live WAVs.
  // The OS lease separately guards against other processes.
  static final Set<String> _liveSessionPaths = <String>{};
  // Two simultaneous recovery scans within one process must never try
  // to acquire or unlink the same OS lease independently.
  static final Set<String> _recoveringPaths = <String>{};
  // A deterministic rotating cursor prevents the same 16 locked/invalid
  // sessions from starving every recoverable candidate after them.
  static int _recoveryCursor = 0;

  final Directory directory;
  final RandomAccessFile _lease;
  Future<void>? _closing;

  static File _marker(Directory directory) =>
      File(p.join(directory.path, markerName));
  static File _leaseFile(Directory directory) =>
      File(p.join(directory.path, leaseName));

  /// A live session keeps an OS-exclusive lock from creation until all
  /// owned audio and native decoder operations have finished.
  static Future<OfflineWavSession> create(Directory tempRoot) async {
    final directory = await tempRoot.createTemp(sessionPrefix);
    RandomAccessFile? handle;
    try {
      handle = await _leaseFile(directory).open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      await _marker(directory).writeAsString(markerContent, flush: true);
      _liveSessionPaths.add(p.normalize(directory.absolute.path));
      return OfflineWavSession._(directory, handle);
    } catch (_) {
      if (handle != null) {
        try { await handle.unlock(); } on FileSystemException {}
        await handle.close();
      }
      // Never recurse into an unknown replacement directory on failure.
      rethrow;
    }
  }

  /// Only closes the lease after every caller has finished with the WAV
  /// folders. If no clips remain, remove the empty session metadata too.
  /// If Windows still owns a WAV, leave the MARKED session for next launch.
  Future<void> close() => _closing ??= _closeOnce();

  Future<void> _closeOnce() async {
    try {
      final contents = await directory.list(followLinks: false).toList();
      final empty = contents.length == 2 &&
          contents.every((e) =>
              p.basename(e.path) == markerName ||
              p.basename(e.path) == leaseName);
      if (empty) {
        // Removing the marker first ensures another scanner never
        // attempts recovery in the tiny unlock -> delete interval.
        await _marker(directory).delete();
      }
    } on FileSystemException {
      // A locked WAV is not safe to remove; marker remains intact.
    } finally {
      try { await _lease.unlock(); } on FileSystemException {}
      await _lease.close();
      _liveSessionPaths.remove(p.normalize(directory.absolute.path));
    }
    try {
      if (await FileSystemEntity.type(_marker(directory).path,
              followLinks: false) == FileSystemEntityType.notFound) {
        await _leaseFile(directory).delete();
        await directory.delete();
      }
    } on FileSystemException {
      // The next launch ignores an unmarked directory; never scan it.
    }
  }

  static bool _clipName(String value) =>
      value.startsWith('ereader-local-tts-') ||
      value.startsWith('ereader-local-lookahead-');

  static Future<bool> _isValidSession(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) return false;
    if (await FileSystemEntity.type(_marker(directory).path,
            followLinks: false) != FileSystemEntityType.file) return false;
    if (await FileSystemEntity.type(_leaseFile(directory).path,
            followLinks: false) != FileSystemEntityType.file) return false;
    // A tiny exact marker; never read a potentially large arbitrary file.
    if (await _marker(directory).length() != markerContent.length) {
      return false;
    }
    return await _marker(directory).readAsString() == markerContent;
  }

  /// Strict allowlist. Do not follow symlinks, touch unexpected files,
  /// recursively sweep arbitrary contents, or follow nested directories.
  static Future<List<Directory>?> _clips(Directory session) async {
    final result = <Directory>[];
    var entries = 0;
    var sawMarker = false;
    var sawLease = false;
    await for (final entry in session.list(followLinks: false)) {
      if (++entries > maxClipsPerSession + 2) return null;
      final name = p.basename(entry.path);
      final kind = await FileSystemEntity.type(
          entry.path, followLinks: false);
      if (name == markerName && kind == FileSystemEntityType.file) {
        sawMarker = true;
      } else if (name == leaseName &&
          kind == FileSystemEntityType.file) {
        sawLease = true;
      } else if (_clipName(name) &&
          kind == FileSystemEntityType.directory) {
        var seenWav = false;
        var nested = 0;
        await for (final child in Directory(entry.path)
            .list(followLinks: false)) {
          if (++nested > 1) return null;
          if (p.basename(child.path) != 'speech.wav' ||
              await FileSystemEntity.type(child.path,
                  followLinks: false) != FileSystemEntityType.file ||
              seenWav) return null;
          seenWav = true;
        }
        result.add(Directory(entry.path));
      } else {
        return null;
      }
    }
    return sawMarker && sawLease ? result : null;
  }

  /// Some Windows crashes can interrupt close() after the ownership
  /// marker has been removed but before the lease file/directory are
  /// unlinked. ONLY a strictly empty, lease-only directory can be
  /// recovered without an ownership marker; WAVs remain forbidden.
  static Future<bool> _isLeaseOnlyMetadata(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) return false;
    var count = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (++count > 1 ||
          p.basename(entry.path) != leaseName ||
          await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.file) return false;
      // An exclusive OS record lock does not modify file contents.
      // The private lease file is created empty and never written to.
      if (await File(entry.path).length() != 0) return false;
    }
    return count == 1;
  }

  /// Bounded, fair recovery on explicit experimental VITS initialization.
  ///
  /// Examine at most 512 *direct* system-temp entries in one call, then
  /// visit at most 16 matching session candidates. Sort the discovered
  /// candidates and rotate a cursor so permanently locked or invalid
  /// earlier entries do not starve later crashed sessions.
  static Future<int> recoverAbandoned(Directory tempRoot) async {
    if (await FileSystemEntity.type(tempRoot.path, followLinks: false) !=
        FileSystemEntityType.directory) return 0;

    final discovered = <Directory>[];
    var entries = 0;
    try {
      await for (final item in tempRoot.list(followLinks: false)) {
        if (++entries > maxRootEntries) break;
        if (item is Directory &&
            p.basename(item.path).startsWith(sessionPrefix)) {
          discovered.add(Directory(item.path));
        }
      }
    } on FileSystemException {
      // Best-effort cleanup must not block normal audio initialization.
      return 0;
    }
    if (discovered.isEmpty) return 0;
    discovered.sort((a, b) => a.path.compareTo(b.path));

    final start = _recoveryCursor % discovered.length;
    final visit = discovered.length < maxScannedSessions
        ? discovered.length : maxScannedSessions;
    _recoveryCursor = (start + visit) % discovered.length;
    var recovered = 0;

    for (var index = 0; index < visit; index++) {
      final candidate = discovered[(start + index) % discovered.length];
      final path = p.normalize(candidate.absolute.path);
      if (_liveSessionPaths.contains(path) ||
          !_recoveringPaths.add(path)) continue;
      try {
        final marked = await _isValidSession(candidate);
        if (marked) {
          if (await _clips(candidate) == null) continue;
        } else if (!await _isLeaseOnlyMetadata(candidate)) {
          continue;
        }
        // The regular lease file was checked above. FileLock.exclusive
        // is non-blocking; a live process is skipped without waiting.
        final lease = await _leaseFile(candidate).open(mode: FileMode.append);
        var locked = false;
        var eligible = false;
        try {
          try {
            await lease.lock(FileLock.exclusive);
            locked = true;
          } on FileSystemException {
            continue;
          }
          // Recheck AFTER taking the OS lease, before ANY deletion.
          if (await _isValidSession(candidate)) {
            final clips = await _clips(candidate);
            if (clips == null) continue;
            var allRemoved = true;
            for (final folder in clips) {
              try {
                final wav = File(p.join(folder.path, 'speech.wav'));
                final type = await FileSystemEntity.type(
                    wav.path, followLinks: false);
                if (type == FileSystemEntityType.file) {
                  await wav.delete();
                } else if (type != FileSystemEntityType.notFound) {
                  allRemoved = false;
                  break;
                }
                // No recursive deletion of unknown children.
                await folder.delete();
              } on FileSystemException {
                allRemoved = false;
                break;
              }
            }
            if (!allRemoved) continue;
            await _marker(candidate).delete();
            eligible = true;
          } else if (await _isLeaseOnlyMetadata(candidate)) {
            // Metadata-only special case: no unmarked WAV is removed.
            eligible = true;
          }
        } finally {
          if (locked) {
            try { await lease.unlock(); } on FileSystemException {}
          }
          await lease.close();
        }
        if (!eligible) continue;
        // Deleting the now-empty lease may fail transiently on Windows.
        // Later sweeps can safely retry the metadata-only candidate.
        try {
          if (!await _isLeaseOnlyMetadata(candidate)) continue;
          await _leaseFile(candidate).delete();
          await candidate.delete();
          recovered++;
        } on FileSystemException {
          // Retain only the empty metadata for the next sweep.
        }
      } on FileSystemException {
        // Treat locked or inaccessible candidates as harmless.
      } on FormatException {
        // Never trust malformed metadata.
      } finally {
        _recoveringPaths.remove(path);
      }
    }
    return recovered;
  }
}
