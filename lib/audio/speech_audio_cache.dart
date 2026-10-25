import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Audio cache contains generated book audio (personal data), not API keys.
/// Cache keys must be opaque SHA-256 hashes of model, voice and exact TTS text;
/// rendered text and credentials are never stored in filenames.
abstract interface class SpeechAudioCache {
  Future<Uint8List?> read(String bookId, String cacheKey);
  Future<void> write(String bookId, String cacheKey, Uint8List mp3);
  Future<void> clearBook(String bookId);
  Future<void> clearAll();
}

class NoSpeechAudioCache implements SpeechAudioCache {
  const NoSpeechAudioCache();
  @override
  Future<Uint8List?> read(String bookId, String key) async => null;
  @override
  Future<void> write(String bookId, String key, Uint8List mp3) async {}
  @override
  Future<void> clearBook(String bookId) async {}
  @override
  Future<void> clearAll() async {}
}

class PrivateMp3SpeechCache implements SpeechAudioCache {
  PrivateMp3SpeechCache({Directory? root}) : _root = root;

  final Directory? _root;
  static const maxBytes = 250 * 1024 * 1024;
  static const maxEntry = 20 * 1024 * 1024;

  Future<Directory> _cacheRoot() async {
    final directory = _root ??
        Directory(p.join(
          (await getApplicationSupportDirectory()).path,
          'ereader', 'speech-cache',
        ));
    await directory.create(recursive: true);
    return directory;
  }

  static void _validateKey(String bookId, String key) {
    final sha256 = RegExp(r'^[0-9a-f]{64}$');
    if (!sha256.hasMatch(bookId) || !sha256.hasMatch(key)) {
      throw const FormatException('Cache identifiers must be SHA-256 hashes');
    }
  }

  Future<File> _file(String bookId, String key) async {
    _validateKey(bookId, key);
    final root = await _cacheRoot();
    final dir = Directory(p.join(root.path, bookId));
    await dir.create(recursive: true);
    return File(p.join(dir.path, key + '.mp3'));
  }

  @override
  Future<Uint8List?> read(String bookId, String cacheKey) async {
    final file = await _file(bookId, cacheKey);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length <= 0 || length > maxEntry) {
      await file.delete();
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      // Update last-used time for least-recently-read retention.
      await file.setLastModified(DateTime.now().toUtc());
      return Uint8List.fromList(bytes);
    } on FileSystemException {
      return null; // Corrupt/evicted entry can be synthesized again.
    }
  }

  @override
  Future<void> write(String bookId, String cacheKey, Uint8List mp3) async {
    if (mp3.isEmpty || mp3.length > maxEntry) {
      throw const FormatException('Invalid audio cache entry size');
    }
    final file = await _file(bookId, cacheKey);
    if (await file.exists()) return;
    final staging = File(
      file.path + '.' + DateTime.now().microsecondsSinceEpoch.toString() + '.part',
    );
    try {
      await staging.writeAsBytes(mp3, flush: true);
      if (!await file.exists()) await staging.rename(file.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    await _enforceLimit();
  }

  Future<void> _enforceLimit() async {
    final root = await _cacheRoot();
    final files = <File>[];
    var total = 0;
    await for (final item in root.list(recursive: true)) {
      if (item is! File || !item.path.endsWith('.mp3')) continue;
      files.add(item);
      total += await item.length();
    }
    if (total <= maxBytes) return;
    final oldToNew = <({File file, DateTime lastUsed})>[];
    for (final file in files) {
      oldToNew.add((
        file: file,
        lastUsed: await file.lastModified(),
      ));
    }
    oldToNew.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    for (final item in oldToNew) {
      if (total <= maxBytes) break;
      try {
        total -= await item.file.length();
        await item.file.delete();
      } on FileSystemException {
        // Playback of another clip may hold this file open on Windows.
      }
    }
  }

  @override
  Future<void> clearBook(String bookId) async {
    _validateKey(bookId, '0' * 64);
    final root = await _cacheRoot();
    final dir = Directory(p.join(root.path, bookId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<void> clearAll() async {
    final root = await _cacheRoot();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
