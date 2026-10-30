import 'dart:io';

import 'package:path/path.dart' as p;

/// An independently leased work directory for a user-approved VITS/Piper
/// import. Only [payload] is promoted to the final installed voice ID:
/// recovery marker and lock NEVER enter a verified model package.
///
/// Old unmarked .install-* folders deliberately remain untouched.
/// Bounded, read-only recovery diagnostic. Eligible is not a promise:
/// another process can take a lock or change files after this snapshot.
class ManualVoiceStagingHealth {
  const ManualVoiceStagingHealth({
    required this.candidates,
    required this.examined,
    required this.eligible,
    required this.recent,
    required this.busy,
    required this.unrecognized,
    required this.rootLimitReached,
  });

  final int candidates;
  final int examined;
  final int eligible;
  final int recent;
  final int busy;
  final int unrecognized;
  final bool rootLimitReached;

  int get notExamined => candidates - examined;
  bool get limited => rootLimitReached || notExamined > 0;
}

class ManualVoiceInstallStaging {
  ManualVoiceInstallStaging._(this.directory, this._lease);

  static const prefix = '.install-';
  static const markerName = '.ereader-manual-install-v1';
  static const leaseName = '.ereader-manual-install-lease-v1';
  static const payloadName = 'payload';
  static const markerContent = 'EReader private manual voice import v1\n';
  static const minRecoveryAge = Duration(hours: 24);
  static const maxRootEntries = 512;
  static const maxCandidatesPerSweep = 16;
  static const maxTreeEntries = 4096;

  static final Set<String> _live = <String>{};
  static final Set<String> _recovering = <String>{};
  static int _cursor = 0;
  static int _diagnosticCursor = 0;

  final Directory directory;
  final RandomAccessFile _lease;
  Future<void>? _closing;
  Directory get payload => Directory(p.join(directory.path, payloadName));

  static String _key(Directory dir) => p.normalize(dir.absolute.path);
  static File _marker(Directory dir) =>
      File(p.join(dir.path, markerName));
  static File _leaseFile(Directory dir) =>
      File(p.join(dir.path, leaseName));

  static Future<ManualVoiceInstallStaging> create(
      Directory modelsDirectory) async {
    await modelsDirectory.create(recursive: true);
    final dir = await modelsDirectory.createTemp(prefix);
    RandomAccessFile? lease;
    try {
      lease = await _leaseFile(dir).open(mode: FileMode.append);
      await lease.lock(FileLock.exclusive);
      _live.add(_key(dir));
      await _marker(dir).writeAsString(markerContent, flush: true);
      await Directory(p.join(dir.path, payloadName)).create();
      return ManualVoiceInstallStaging._(dir, lease);
    } catch (_) {
      _live.remove(_key(dir));
      if (lease != null) {
        try { await lease.unlock(); } on FileSystemException {}
        await lease.close();
      }
      // This exact newly created directory is owned by this operation.
      try { await dir.delete(recursive: true); } on FileSystemException {}
      rethrow;
    }
  }

  /// Finish while still holding our exclusive lease. If a Windows native
  /// handle blocks deletion, preserve the exact marker for a later cleanup.
  Future<void> finish() => _closing ??= _finishOnce();

  Future<void> _finishOnce() async {
    var removed = false;
    try {
      if (await _safeContents(directory)) {
        await _removePayload(directory);
        await _marker(directory).delete();
        removed = true;
      }
    } on FileSystemException {
      // Keep a marked stage if a temporary asset is locked.
    } finally {
      try { await _lease.unlock(); } on FileSystemException {}
      await _lease.close();
      _live.remove(_key(directory));
    }
    if (!removed) return;
    try {
      await _leaseFile(directory).delete();
      await directory.delete();
    } on FileSystemException {
      // A Windows lease-only empty folder may remain; no model files do.
    }
  }

  static bool _allowedPart(String part) {
    final reserved = RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
        caseSensitive: false);
    return part.isNotEmpty && part != '.' && part != '..' &&
        !part.endsWith('.') && !reserved.hasMatch(part) &&
        (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part) || part == '!v');
  }

  /// Check the exact allowlist before touching ANY file. Incomplete imports
  /// are allowed, but symlinks, unexpected trees and excessive entries are
  /// never recursively removed. The recovery path only removes individual
  /// checked files and then their emptied directories.
  static Future<bool> _safeContents(Directory stage) async {
    if (await FileSystemEntity.type(stage.path, followLinks: false) !=
        FileSystemEntityType.directory) return false;
    var count = 0;
    await for (final entry in stage.list(
        recursive: true, followLinks: false)) {
      if (++count > maxTreeEntries) return false;
      final kind = await FileSystemEntity.type(
          entry.path, followLinks: false);
      if (kind != FileSystemEntityType.file &&
          kind != FileSystemEntityType.directory) return false;
      final relative = p.relative(entry.path, from: stage.path)
          .replaceAll('\\', '/');
      final parts = relative.split('/');
      if (parts.length == 1) {
        if (relative == markerName || relative == leaseName) {
          if (kind != FileSystemEntityType.file) return false;
        } else if (relative == payloadName) {
          if (kind != FileSystemEntityType.directory) return false;
        } else {
          return false;
        }
        continue;
      }
      if (parts.first != payloadName || parts.length > 18) return false;
      if (parts.length == 2) {
        if (parts[1] == 'espeak-ng-data') {
          if (kind != FileSystemEntityType.directory) return false;
        } else if (parts[1] == 'model.onnx' ||
            parts[1] == 'tokens.txt' ||
            parts[1] == 'voice-pack.json') {
          if (kind != FileSystemEntityType.file) return false;
        } else {
          return false;
        }
      } else if (parts[1] != 'espeak-ng-data' ||
          !parts.skip(2).every(_allowedPart)) {
        return false;
      }
    }
    return true;
  }

  static Future<bool> _validMarker(Directory stage, DateTime cutoff) async {
    final marker = _marker(stage);
    final lease = _leaseFile(stage);
    if (await FileSystemEntity.type(stage.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.type(lease.path, followLinks: false) !=
            FileSystemEntityType.file) return false;
    if (await marker.length() != markerContent.length ||
        await lease.length() != 0 ||
        (await marker.lastModified()).isAfter(cutoff)) return false;
    return await marker.readAsString() == markerContent;
  }

  static Future<void> _removePayload(Directory stage) async {
    final payload = Directory(p.join(stage.path, payloadName));
    final type = await FileSystemEntity.type(
        payload.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('Unsafe voice import payload');
    }
    final files = <FileSystemEntity>[];
    final dirs = <Directory>[];
    await for (final entity in payload.list(
        recursive: true, followLinks: false)) {
      final kind = await FileSystemEntity.type(
          entity.path, followLinks: false);
      if (kind == FileSystemEntityType.file) {
        files.add(entity);
      } else if (kind == FileSystemEntityType.directory) {
        dirs.add(Directory(entity.path));
      } else {
        throw const FileSystemException('Unsafe voice import asset');
      }
      if (files.length + dirs.length > maxTreeEntries) {
        throw const FileSystemException('Excessive voice import assets');
      }
    }
    // Recheck type at deletion time; never follow a replacement symlink.
    for (final file in files) {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException('Voice import file changed');
      }
      await File(file.path).delete();
    }
    dirs.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final dir in dirs) {
      if (await FileSystemEntity.type(dir.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FileSystemException('Voice import directory changed');
      }
      await dir.delete(); // nonrecursive, must already be empty
    }
    await payload.delete();
  }

  /// Explicit read-only preflight: never cleans or starts an ONNX model.
  /// Fixed scan budgets and a rotating candidate cursor avoid starvation.
  static Future<ManualVoiceStagingHealth> inspectAbandoned(
    Directory modelsDirectory, {
    Duration minimumAge = minRecoveryAge,
  }) async {
    if (minimumAge.isNegative) {
      throw ArgumentError.value(minimumAge, 'minimumAge');
    }
    if (await FileSystemEntity.type(modelsDirectory.path,
            followLinks: false) != FileSystemEntityType.directory) {
      return const ManualVoiceStagingHealth(
        candidates: 0, examined: 0, eligible: 0, recent: 0,
        busy: 0, unrecognized: 0, rootLimitReached: false,
      );
    }
    final discovered = <Directory>[];
    var scanned = 0;
    var rootLimitReached = false;
    try {
      await for (final entry in modelsDirectory.list(followLinks: false)) {
        if (++scanned > maxRootEntries) {
          rootLimitReached = true;
          break;
        }
        if (entry is Directory &&
            RegExp(r'^\.install-[A-Za-z0-9_-]+$')
                .hasMatch(p.basename(entry.path))) {
          discovered.add(Directory(entry.path));
        }
      }
    } on FileSystemException {
      return const ManualVoiceStagingHealth(
        candidates: 0, examined: 0, eligible: 0, recent: 0,
        busy: 0, unrecognized: 0, rootLimitReached: true,
      );
    }
    discovered.sort((a, b) => a.path.compareTo(b.path));
    if (discovered.isEmpty) {
      return ManualVoiceStagingHealth(
        candidates: 0, examined: 0, eligible: 0, recent: 0,
        busy: 0, unrecognized: 0, rootLimitReached: rootLimitReached,
      );
    }
    final count = discovered.length < maxCandidatesPerSweep
        ? discovered.length : maxCandidatesPerSweep;
    final start = _diagnosticCursor % discovered.length;
    _diagnosticCursor = (start + count) % discovered.length;
    final now = DateTime.now();
    final cutoff = now.subtract(minimumAge);
    var eligible = 0;
    var recent = 0;
    var busy = 0;
    var unrecognized = 0;

    for (var i = 0; i < count; i++) {
      final stage = discovered[(start + i) % discovered.length];
      final key = _key(stage);
      if (_live.contains(key) || !_recovering.add(key)) {
        busy++;
        continue;
      }
      RandomAccessFile? lease;
      var locked = false;
      try {
        if (!await _validMarker(stage, now)) {
          unrecognized++;
          continue;
        }
        if (!await _validMarker(stage, cutoff)) {
          recent++;
          continue;
        }
        lease = await _leaseFile(stage).open(mode: FileMode.append);
        try {
          await lease.lock(FileLock.exclusive);
          locked = true;
        } on FileSystemException {
          busy++;
          continue;
        }
        if (_live.contains(key)) {
          busy++;
        } else if (await _validMarker(stage, cutoff) &&
            await _safeContents(stage)) {
          eligible++;
        } else {
          unrecognized++;
        }
      } on FileSystemException {
        unrecognized++;
      } on FormatException {
        unrecognized++;
      } finally {
        if (lease != null) {
          if (locked) {
            try { await lease.unlock(); } on FileSystemException {}
          }
          await lease.close();
        }
        _recovering.remove(key);
      }
    }
    return ManualVoiceStagingHealth(
      candidates: discovered.length, examined: count,
      eligible: eligible, recent: recent, busy: busy,
      unrecognized: unrecognized, rootLimitReached: rootLimitReached,
    );
  }

  /// Called ONLY from an explicit user cleanup command, never on startup.
  /// Scans at most 512 direct names and attempts at most 16 marked stages.
  /// Returns a count, never source paths or model contents.
  static Future<int> recoverAbandoned(
    Directory modelsDirectory, {
    Duration minimumAge = minRecoveryAge,
  }) async {
    if (minimumAge.isNegative) {
      throw ArgumentError.value(minimumAge, 'minimumAge');
    }
    if (await FileSystemEntity.type(modelsDirectory.path,
            followLinks: false) != FileSystemEntityType.directory) return 0;
    final discovered = <Directory>[];
    var inspected = 0;
    try {
      await for (final entry in modelsDirectory.list(followLinks: false)) {
        if (++inspected > maxRootEntries) break;
        if (entry is Directory &&
            RegExp(r'^\.install-[A-Za-z0-9_-]+$')
                .hasMatch(p.basename(entry.path))) {
          discovered.add(Directory(entry.path));
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
    var cleaned = 0;

    for (var i = 0; i < count; i++) {
      final stage = discovered[(start + i) % discovered.length];
      final key = _key(stage);
      if (_live.contains(key) || !_recovering.add(key)) continue;
      RandomAccessFile? lease;
      var locked = false;
      var empty = false;
      try {
        if (!await _validMarker(stage, cutoff)) continue;
        lease = await _leaseFile(stage).open(mode: FileMode.append);
        try {
          await lease.lock(FileLock.exclusive);
          locked = true;
        } on FileSystemException {
          continue; // active installer in another process
        }
        if (_live.contains(key) ||
            !await _validMarker(stage, cutoff) ||
            !await _safeContents(stage)) continue;
        await _removePayload(stage);
        await _marker(stage).delete();
        empty = true;
      } on FileSystemException {
        // A lock or file change leaves this stage for a later pass.
      } finally {
        if (lease != null) {
          if (locked) {
            try { await lease.unlock(); } on FileSystemException {}
          }
          await lease.close();
        }
        _recovering.remove(key);
      }
      if (!empty) continue;
      try {
        await _leaseFile(stage).delete();
        await stage.delete();
        cleaned++;
      } on FileSystemException {
        // Only empty lease metadata may remain on Windows.
      }
    }
    return cleaned;
  }
}
