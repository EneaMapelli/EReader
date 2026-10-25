import 'dart:io';
import 'dart:typed_data';

import 'epub_text_extractor.dart';

/// Read EPUB bytes from a worker isolate only, with a filesystem-size
/// preflight check. This prevents an oversized ZIP from first being copied
/// into memory merely to discover that its header violates import quotas.
/// Check the actual bytes again in case the file changed between stat/read.
Uint8List readBoundedEpubFile(String localPath) {
  final file = File(localPath);
  if (file.lengthSync() > EpubTextExtractor.maxCompressedLength) {
    throw const FormatException('EPUB ZIP file exceeds 100 MB');
  }
  final bytes = file.readAsBytesSync();
  if (bytes.length > EpubTextExtractor.maxCompressedLength) {
    throw const FormatException('EPUB ZIP file exceeds 100 MB');
  }
  return bytes;
}
