import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Metadata from a bounded WAV/PCM header inspection. No audio samples,
/// passage text or local file paths are exposed by this type.
class OfflineWaveMetrics {
  const OfflineWaveMetrics({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.frames,
    required this.fileBytes,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int frames;
  final int fileBytes;

  int get durationMs => frames * 1000 ~/ sampleRate;

  Map<String, int> toJson() => {
        'sampleRate': sampleRate,
        'channels': channels,
        'bitsPerSample': bitsPerSample,
        'frames': frames,
        'durationMs': durationMs,
        'fileBytes': fileBytes,
      };
}

/// Inspect a PCM WAV without decoding or retaining its contents in memory.
/// RIFF chunks may have padding and may appear in different orders, so avoid
/// treating every WAV as a fixed 44-byte header.
///
/// This validates *container structure*, not audio intelligibility or model
/// provenance. Maximum file size keeps diagnostics bounded even when FFI
/// misbehaves or the requested output is corrupted.
Future<OfflineWaveMetrics> inspectOfflinePcmWave(
  File file, {
  int maxFileBytes = 24 * 1024 * 1024,
}) async {
  if (maxFileBytes < 44 || maxFileBytes > 128 * 1024 * 1024) {
    throw ArgumentError.value(maxFileBytes, 'maxFileBytes');
  }
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('WAV output must be a regular file');
  }
  final length = await file.length();
  if (length < 44 || length > maxFileBytes) {
    throw const FormatException('WAV output exceeds size limits');
  }
  final handle = await file.open();
  try {
    Future<Uint8List> bytes(int offset, int count) async {
      await handle.setPosition(offset);
      final read = await handle.read(count);
      if (read.length != count) {
        throw const FormatException('Truncated WAV output');
      }
      return Uint8List.fromList(read);
    }

    final header = await bytes(0, 12);
    String tag(Uint8List data, int offset) => String.fromCharCodes(
          data.sublist(offset, offset + 4),
        );
    if (tag(header, 0) != 'RIFF' || tag(header, 8) != 'WAVE') {
      throw const FormatException('Expected RIFF/WAVE');
    }
    final root = ByteData.sublistView(header);
    final riffBytes = root.getUint32(4, Endian.little) + 8;
    if (riffBytes > length || riffBytes < 44) {
      throw const FormatException('Invalid WAV RIFF bounds');
    }

    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? blockAlign;
    int? dataBytes;

    var offset = 12;
    var chunkCount = 0;
    while (offset + 8 <= riffBytes) {
      if (++chunkCount > 64) {
        throw const FormatException('Too many WAV chunks');
      }
      final chunkHeader = await bytes(offset, 8);
      final chunk = ByteData.sublistView(chunkHeader);
      final id = tag(chunkHeader, 0);
      final size = chunk.getUint32(4, Endian.little);
      final chunkStart = offset + 8;
      final next = chunkStart + size + (size.isOdd ? 1 : 0);
      if (next > riffBytes || next > length) {
        throw const FormatException('WAV chunk outside RIFF');
      }
      if (id == 'fmt ') {
        if (sampleRate != null || size < 16 || size > 128) {
          throw const FormatException('Invalid WAV format header');
        }
        final fmt = ByteData.sublistView(await bytes(chunkStart, 16));
        final encoding = fmt.getUint16(0, Endian.little);
        channels = fmt.getUint16(2, Endian.little);
        sampleRate = fmt.getUint32(4, Endian.little);
        final byteRate = fmt.getUint32(8, Endian.little);
        blockAlign = fmt.getUint16(12, Endian.little);
        bitsPerSample = fmt.getUint16(14, Endian.little);
        if (encoding != 1 ||
            channels < 1 || channels > 2 ||
            sampleRate < 8000 || sampleRate > 96000 ||
            bitsPerSample != 16 ||
            blockAlign != channels * (bitsPerSample ~/ 8) ||
            byteRate != sampleRate * blockAlign) {
          throw const FormatException('Unsupported or invalid PCM format');
        }
      } else if (id == 'data') {
        if (dataBytes != null || size == 0) {
          throw const FormatException('Invalid WAV audio chunk');
        }
        dataBytes = size;
      }
      offset = next;
    }
    if (sampleRate == null || channels == null ||
        bitsPerSample == null || blockAlign == null ||
        dataBytes == null || dataBytes % blockAlign != 0) {
      throw const FormatException('Incomplete PCM WAV');
    }
    final frames = dataBytes ~/ blockAlign;
    final durationMs = frames * 1000 ~/ sampleRate;
    if (durationMs < 100 || durationMs > 90000 ||
        frames > math.max(1, sampleRate * 90)) {
      throw const FormatException('WAV audio outside duration budget');
    }
    return OfflineWaveMetrics(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      frames: frames,
      fileBytes: length,
    );
  } finally {
    await handle.close();
  }
}
