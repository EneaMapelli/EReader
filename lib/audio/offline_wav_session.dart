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

  final Directory directory;
  final RandomAccessFile _lease;
  bool _closed = false;

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
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
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

  /// Bounded recovery on explicit experimental VITS engine initialization.
  ///
  /// Deletion is permitted only after obtaining the non-blocking exclusive
  /// lease of a marked, strictly validated session. Live readers keep their
  /// lock so multiple Windows processes cannot delete each other's WAVs.
  /// No file names, book text, audio or private paths are logged.
  static Future<int> recoverAbandoned(Directory tempRoot) async {
    if (await FileSystemEntity.type(tempRoot.path, followLinks: false) !=
        FileSystemEntityType.directory) return 0;
    var seen = 0;
    var candidates = 0;
    var recovered = 0;
    await for (final entry in tempRoot.list(followLinks: false)) {
      if (++seen > maxRootEntries || candidates >= maxScannedSessions) {
        break;
      }
      if (!p.basename(entry.path).startsWith(sessionPrefix) ||
          entry is! Directory) continue;
      candidates++;
      final candidate = Directory(entry.path);
      try {
        if (!await _isValidSession(candidate)) continue;
        // Validate BEFORE trying to lock; a malformed tree is untouched.
        var clips = await _clips(candidate);
        if (clips == null) continue;
        final lease = await _leaseFile(candidate).open(mode: FileMode.append);
        var locked = false;
        try {
          try {
            await lease.lock(FileLock.exclusive); // Nonblocking attempt.
            locked = true;
          } on FileSystemException {
            continue; // Another live engine owns this session.
          }
          // Verify AGAIN after locking: the directory could have changed.
          if (!await _isValidSession(candidate)) continue;
          clips = await _clips(candidate);
          if (clips == null) continue;
          var succeeded = true;
          for (final folder in clips) {
            try {
              final wav = File(p.join(folder.path, 'speech.wav'));
              if (await FileSystemEntity.type(wav.path,
                      followLinks: false) == FileSystemEntityType.file) {
                await wav.delete();
              }
              await folder.delete(); // Nonrecursive, strict allowlist.
            } on FileSystemException {
              succeeded = false;
              break;
            }
          }
          if (!succeeded) continue;
          await _marker(candidate).delete();
          recovered++;
        } finally {
          if (locked) {
            try { await lease.unlock(); } on FileSystemException {}
          }
          await lease.close();
        }
        // Remove only the now-unmarked metadata directory, no recursion.
        try {
          await _leaseFile(candidate).delete();
          await candidate.delete();
        } on FileSystemException {}
      } on FileSystemException {
        // Locked or inaccessible files remain for a future attempt.
      } on FormatException {
        // Malformed markers are never treated as authoritative.
      }
    }
    return recovered;
  }
}
