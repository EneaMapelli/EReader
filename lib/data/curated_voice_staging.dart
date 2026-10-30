import 'dart:io';

import 'package:path/path.dart' as p;

/// Crash-recoverable, private scratch space for the explicitly approved
/// curated Paola download. A marker AND an exclusive OS lease are required
/// for recovery: merely matching a folder name is NEVER sufficient.
///
/// Sessions are independent of installed models and of the offline WAV
/// recovery mechanism. Recovery is opt-in, bounded and ignores unmarked
/// legacy folders, unexpected symlinks and recently created sessions.
class CuratedVoiceStaging {
  CuratedVoiceStaging._(this.directory, this._lease);

  static const prefix = '.paola-install-';
  static const markerName = '.ereader-paola-stage-v1';
  static const leaseName = '.ereader-paola-lease-v1';
  static const markerContent = 'EReader Paola private download v1\n';
  static const maxRootEntries = 256;
  static const maxCandidatesPerSweep = 16;
  static const maxOwnedEntries = 4096;
  static const minRecoveryAge = Duration(hours: 24);

  static final Set<String> _live = {};
  static final Set<String> _recovering = {};
  static int _cursor = 0;

  final Directory directory;
  final RandomAccessFile _lease;
  Future<void>? _closing;

  static String _absolute(Directory dir) => p.normalize(dir.absolute.path);
  static File _marker(Directory dir) =>
      File(p.join(dir.path, markerName));
  static File _leaseFile(Directory dir) =>
      File(p.join(dir.path, leaseName));

  /// The lock stays owned for the WHOLE download/extraction/import session.
  /// If the process crashes, the OS releases it and the exact marker remains.
  static Future<CuratedVoiceStaging> create(Directory parent) async {
    await parent.create(recursive: true);
    final dir = await parent.createTemp(prefix);
    RandomAccessFile? handle;
    try {
      handle = await _leaseFile(dir).open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      _live.add(_absolute(dir));
      await _marker(dir).writeAsString(markerContent, flush: true);
      return CuratedVoiceStaging._(dir, handle);
    } catch (_) {
      _live.remove(_absolute(dir));
      if (handle != null) {
        try { await handle.unlock(); } on FileSystemException {}
        await handle.close();
      }
      try { await dir.delete(recursive: true); } on FileSystemException {}
      rethrow;
    }
  }

  /// Remove the marker while still owning the lease, so a concurrent
  /// recoverer cannot mistake normal cleanup for an abandoned download.
  Future<void> finish() => _closing ??= _finishOnce();

  Future<void> _finishOnce() async {
    try {
      if (await FileSystemEntity.type(_marker(directory).path,
              followLinks: false) == FileSystemEntityType.file) {
        await _marker(directory).delete();
      }
    } on FileSystemException {
      // Keep a marked, OS-unlocked directory for a later safe sweep.
    } finally {
      try { await _lease.unlock(); } on FileSystemException {}
      await _lease.close();
      _live.remove(_absolute(directory));
    }
    try { await directory.delete(recursive: true); } on FileSystemException {
      // Windows may retain an archive handle. Never delete other folders.
    }
  }

  static Future<bool> _validMarker(Directory dir, DateTime cutoff) async {
    if (await FileSystemEntity.type(dir.path, followLinks: false) !=
        FileSystemEntityType.directory) return false;
    final marker = _marker(dir);
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
        FileSystemEntityType.file ||
        await FileSystemEntity.type(_leaseFile(dir).path,
            followLinks: false) != FileSystemEntityType.file) return false;
    if (await marker.length() != markerContent.length ||
        await _leaseFile(dir).length() != 0 ||
        (await marker.lastModified()).isAfter(cutoff)) return false;
    return await marker.readAsString() == markerContent;
  }

  /// Deny links, unknown top-level content and excessive extraction trees.
  /// No arbitrary folder under the user's Temp or Documents is traversed.
  static Future<bool> _safeContents(Directory dir) async {
    var seen = 0;
    await for (final item in dir.list(recursive: true, followLinks: false)) {
      if (++seen > maxOwnedEntries) return false;
      final kind = await FileSystemEntity.type(item.path, followLinks: false);
      if (kind != FileSystemEntityType.file &&
          kind != FileSystemEntityType.directory) return false;
      final relative = p.relative(item.path, from: dir.path)
          .replaceAll('\\', '/');
      final top = relative.split('/').first;
      if (top != markerName && top != leaseName &&
          top != 'unpacked' && top != 'prepared' &&
          top != 'vits-piper-it_IT-paola-medium.tar.bz2') return false;
      if ((top == markerName || top == leaseName ||
           top.endsWith('.tar.bz2')) && relative != top) return false;
    }
    return true;
  }

  /// Explicit cleanup after interruption. At most 256 direct parent
  /// entries and 16 candidate sessions are examined in one invocation.
  /// Return only the number fully removed; no private paths are exposed.
  static Future<int> recoverAbandoned(
    Directory parent, {
    Duration minimumAge = minRecoveryAge,
  }) async {
    if (minimumAge.isNegative) throw ArgumentError.value(
        minimumAge, 'minimumAge');
    if (await FileSystemEntity.type(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) return 0;
    final discovered = <Directory>[];
    var inspected = 0;
    try {
      await for (final entity in parent.list(followLinks: false)) {
        if (++inspected > maxRootEntries) break;
        final name = p.basename(entity.path);
        if (entity is Directory &&
            RegExp(r'^\\.paola-install-[a-zA-Z0-9_-]+$').hasMatch(name)) {
          discovered.add(Directory(entity.path));
        }
      }
    } on FileSystemException {
      return 0;
    }
    if (discovered.isEmpty) return 0;
    discovered.sort((a, b) => a.path.compareTo(b.path));
    final start = _cursor % discovered.length;
    final count = discovered.length < maxCandidatesPerSweep
        ? discovered.length : maxCandidatesPerSweep;
    _cursor = (start + count) % discovered.length;
    final cutoff = DateTime.now().subtract(minimumAge);
    var removed = 0;

    for (var i = 0; i < count; i++) {
      final dir = discovered[(start + i) % discovered.length];
      final key = _absolute(dir);
      if (_live.contains(key) || !_recovering.add(key)) continue;
      RandomAccessFile? lease;
      var locked = false;
      var emptied = false;
      try {
        if (!await _validMarker(dir, cutoff)) continue;
        lease = await _leaseFile(dir).open(mode: FileMode.append);
        try {
          await lease.lock(FileLock.exclusive);
          locked = true;
        } on FileSystemException {
          // The current downloader owns the OS lock.
          continue;
        }
        if (_live.contains(key) ||
            !await _validMarker(dir, cutoff) ||
            !await _safeContents(dir)) continue;
        // Delete only allowlisted children while holding the lease.
        // Do not recursively delete an unknown path or traverse symlinks.
        await for (final child in dir.list(followLinks: false)) {
          final name = p.basename(child.path);
          if (name == markerName || name == leaseName) continue;
          final type = await FileSystemEntity.type(
              child.path, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            await Directory(child.path).delete(recursive: true);
          } else if (type == FileSystemEntityType.file) {
            await File(child.path).delete();
          } else {
            throw const FileSystemException('Unsafe staging entry');
          }
        }
        await _marker(dir).delete();
        emptied = true;
      } on FileSystemException {
        // The original marked candidate remains for a later retry.
      } finally {
        if (lease != null) {
          if (locked) {
            try { await lease.unlock(); } on FileSystemException {}
          }
          await lease.close();
        }
        _recovering.remove(key);
      }
      if (!emptied) continue;
      try {
        await _leaseFile(dir).delete();
        await dir.delete();
        removed++;
      } on FileSystemException {
        // All model/archive bytes have been removed; only the empty
        // lease-only metadata may remain on a locked Windows volume.
      }
    }
    return removed;
  }
}
