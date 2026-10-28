import 'dart:io';

import '../domain/book.dart';

/// The library owns the canonical copy and validation of each imported book.
/// Picker providers on Android can expose a readable SAF stream but no usable
/// on-disk path. This adapter only stages such a stream temporarily; it never
/// persists provider URIs or assumes an external bookmark remains accessible.
typedef PickedBookImporter<T> = Future<T> Function(
    String sourcePath, {String? originalName});

/// Import a supported local picker selection or safely stage a stream-only
/// selection. All temporary source bytes are removed even if the stream,
/// format verification, SQLite import or user navigation fails.
/// A streamed selection cannot bypass the library's 100 MB import limit.
Future<T> importPickedBook<T>({
  required String originalName,
  required String? pickedPath,
  required Stream<List<int>> Function() readAsByteStream,
  required PickedBookImporter<T> importFile,
  Directory? stagingParent,
  int maxBytes = 100 * 1024 * 1024,
}) async {
  if (maxBytes < 1 || maxBytes > 100 * 1024 * 1024) {
    throw ArgumentError.value(maxBytes, 'maxBytes');
  }
  final format = BookFormatPath.parse(originalName);
  if (format == null) {
    throw const FormatException('Unsupported book extension');
  }

  // The normal desktop and cached mobile paths use the existing validated
  // library import without an additional byte copy.
  // Android SAF can expose a content:// URI instead of an OS file.
  // Never pass provider URIs to dart:io; use the bounded stream path.
  // A missing/inaccessible *cached* path is also retried as a stream.
  if (pickedPath != null && !pickedPath.startsWith('content://')) {
    var isFile = false;
    try {
      isFile = await File(pickedPath).exists();
    } on FileSystemException {
      // Windows/Android may reject a virtual path; fall back to the
      // provider's official stream rather than skipping a real book.
    }
    if (isFile) {
      return importFile(pickedPath, originalName: originalName);
    }
  }

  // SAF/cloud document providers may return no real path. Stage only a
  // bounded stream, using a random private directory rather than the
  // provider's potentially unsafe/display-only filename.
  final parent = stagingParent ?? Directory.systemTemp;
  final staging = await parent.createTemp('ereader-picker-');
  final stagedFile = File(
      '${staging.path}${Platform.pathSeparator}source.${format.extension}');
  RandomAccessFile? writer;
  try {
    writer = await stagedFile.open(mode: FileMode.write);
    var length = 0;
    await for (final bytes in readAsByteStream()) {
      if (bytes.length > maxBytes - length) {
        throw const FormatException('Book must be 1 byte to 100 MB');
      }
      if (bytes.isEmpty) continue;
      await writer.writeFrom(bytes);
      length += bytes.length;
    }
    await writer.flush();
    await writer.close();
    writer = null;
    if (length == 0) {
      throw const FormatException('Book must be 1 byte to 100 MB');
    }
    return await importFile(stagedFile.path, originalName: originalName);
  } finally {
    if (writer != null) await writer.close();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
