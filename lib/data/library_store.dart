import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/book.dart';

/// Files are copied to app storage rather than retaining temporary picker URIs.
/// Prototype JSON index will migrate to SQLite for robust concurrent updates.
class LibraryStore {
  Directory? _home;
  final Map<String, BookRecord> _records = {};

  Future<void> initialize() async {
    final base = await getApplicationSupportDirectory();
    _home = Directory(p.join(base.path, 'ereader'));
    await _home!.create(recursive: true);
    await Directory(p.join(_home!.path, 'books')).create(recursive: true);
    final index = File(p.join(_home!.path, 'library.json'));
    if (!await index.exists()) return;
    final decoded = jsonDecode(await index.readAsString()) as List<dynamic>;
    for (final item in decoded) {
      final book = BookRecord.fromJson(item as Map<String, dynamic>);
      _records[book.id] = book;
    }
  }

  List<BookRecord> get books {
    final result = _records.values.toList();
    result.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return result;
  }

  Future<BookRecord> importFile(String sourcePath, {String? originalName}) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw const FormatException('Source not found');
    final displayName = originalName ?? p.basename(sourcePath);
    final format = BookFormatPath.parse(displayName);
    if (format == null) throw const FormatException('Unsupported file type');
    final length = await source.length();
    if (length > 100 * 1024 * 1024) {
      throw const FormatException('Prototype import limit: 100 MB');
    }
    if (length == 0) throw const FormatException('Empty file');

    final bytes = await source.readAsBytes();
    if (format == BookFormat.pdf &&
        !(bytes.length >= 5 &&
          bytes[0] == 0x25 && bytes[1] == 0x50 &&
          bytes[2] == 0x44 && bytes[3] == 0x46 && bytes[4] == 0x2D)) {
      throw const FormatException('Invalid PDF signature');
    }
    if (format == BookFormat.epub &&
        !(bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B &&
          bytes[2] == 0x03 && bytes[3] == 0x04)) {
      throw const FormatException('Invalid EPUB ZIP signature');
    }
    final id = sha256.convert(bytes).toString();
    if (_records.containsKey(id)) return _records[id]!;
    final safePath = p.join(_home!.path, 'books', '$id.${format.extension}');
    await File(safePath).writeAsBytes(bytes, flush: true);
    final title = p.basenameWithoutExtension(displayName);
    final record = BookRecord(
      id: id,
      title: title,
      localPath: safePath,
      format: format,
      importedAt: DateTime.now().toUtc(),
    );
    _records[id] = record;
    await _save();
    return record;
  }

  Future<void> savePosition(String bookId, int offset) async {
    final book = _records[bookId];
    if (book == null) return;
    _records[bookId] = book.atOffset(offset);
    await _save();
  }

  Future<void> removeBook(String bookId) async {
    final book = _records.remove(bookId);
    if (book == null) return;
    await _save();
    final file = File(book.localPath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _save() async {
    final file = File(p.join(_home!.path, 'library.json'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(_records.values.map((e) => e.toJson()).toList()),
      flush: true,
    );
    // Temporary compromise for Windows where rename-to-existing can fail.
    // SQLite transactional persistence is part of M1.
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
