import 'dart:io';
import 'dart:typed_data';

import 'package:ereader/audio/offline_wave_metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

List<int> pcmWav({
  int sampleRate = 16000,
  int channels = 1,
  int frames = 16000,
  int bitsPerSample = 16,
  int encoding = 1,
  bool metadata = false,
}) {
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final dataBytes = frames * blockAlign;
  final fmtBytes = 24;
  final junkBytes = metadata ? 12 : 0;
  final total = 12 + fmtBytes + junkBytes + 8 + dataBytes;
  final bytes = Uint8List(total);
  final b = ByteData.sublistView(bytes);
  void ascii(int start, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[start + i] = text.codeUnitAt(i);
    }
  }
  ascii(0, 'RIFF');
  b.setUint32(4, total - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, encoding, Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * blockAlign, Endian.little);
  b.setUint16(32, blockAlign, Endian.little);
  b.setUint16(34, bitsPerSample, Endian.little);
  final dataOffset = 36 + junkBytes;
  if (metadata) {
    ascii(36, 'JUNK');
    b.setUint32(40, 4, Endian.little);
  }
  ascii(dataOffset, 'data');
  b.setUint32(dataOffset + 4, dataBytes, Endian.little);
  return bytes;
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ereader-wav-metrics-');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> source(List<int> bytes) async {
    final file = File(p.join(dir.path, 'sample.wav'));
    await file.writeAsBytes(bytes);
    return file;
  }

  test('valid one-second PCM16 mono is measured without copying audio',
      () async {
    final metrics = await inspectOfflinePcmWave(await source(pcmWav()));
    expect(metrics.sampleRate, 16000);
    expect(metrics.durationMs, 1000);
    expect(metrics.frames, 16000);
    expect(metrics.channels, 1);
    expect(metrics.bitsPerSample, 16);
    expect(metrics.toJson().keys, containsAll(['durationMs', 'sampleRate']));
    expect(metrics.toJson().keys, isNot(contains('filePath')));
  });

  test('additional metadata chunk does not shift data alignment',
      () async {
    final metrics = await inspectOfflinePcmWave(await source(pcmWav(
      sampleRate: 24000, channels: 2, frames: 24000, metadata: true,
    )));
    expect(metrics.durationMs, 1000);
    expect(metrics.channels, 2);
    expect(metrics.sampleRate, 24000);
  });

  test('non-PCM format or inconsistent data rates are rejected',
      () async {
    await expectLater(inspectOfflinePcmWave(
      await source(pcmWav(encoding: 3)),
    ), throwsFormatException);
    await expectLater(inspectOfflinePcmWave(
      await source(pcmWav(bitsPerSample: 8)),
    ), throwsFormatException);
    final damaged = Uint8List.fromList(pcmWav());
    ByteData.sublistView(damaged).setUint32(28, 123, Endian.little);
    await expectLater(inspectOfflinePcmWave(
      await source(damaged),
    ), throwsFormatException);
  });

  test('truncated RIFF and fake magic are rejected', () async {
    final damaged = Uint8List.fromList(pcmWav());
    await expectLater(inspectOfflinePcmWave(
      await source(damaged.sublist(0, 160)),
    ), throwsFormatException);
    damaged[0] = 0;
    await expectLater(inspectOfflinePcmWave(
      await source(damaged),
    ), throwsFormatException);
  });

  test('very short, very long, and overly large WAV are bounded', () async {
    await expectLater(inspectOfflinePcmWave(
      await source(pcmWav(frames: 100)),
    ), throwsFormatException);
    await expectLater(inspectOfflinePcmWave(
      await source(pcmWav(frames: 16000)),
      maxFileBytes: 200,
    ), throwsFormatException);
    await expectLater(inspectOfflinePcmWave(
      await source(pcmWav()),
      maxFileBytes: 10,
    ), throwsArgumentError);
  });

  test('missing WAV file fails closed before native audio playback',
      () async {
    await expectLater(inspectOfflinePcmWave(
      File(p.join(dir.path, 'missing.wav')),
    ), throwsFormatException);
  });
}
