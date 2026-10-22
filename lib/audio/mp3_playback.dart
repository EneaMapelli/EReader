import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Separate output contract so HTTP/auth/quotas can be unit-tested without
/// loading audio plugins, drivers, speakers or an Android emulator.
abstract interface class SynthesizedAudioOutput {
  Future<void> play(Uint8List mp3Data, {required double speed});
  Future<void> stop();
  Future<void> dispose();
}

/// Platform-agnostic MP3 player; Windows implementation comes from
/// just_audio_windows. Audio files go in private temporary app storage,
/// never into public music directories, and are erased after playback.
class JustAudioMp3Output implements SynthesizedAudioOutput {
  JustAudioMp3Output();
  final AudioPlayer _player = AudioPlayer();
  File? _activeFile;
  bool _disposed = false;

  @override
  Future<void> play(Uint8List mp3Data, {required double speed}) async {
    if (_disposed) throw StateError('Audio output disposed');
    if (mp3Data.isEmpty || mp3Data.length > 20 * 1024 * 1024) {
      throw const FormatException('Unsupported generated audio size');
    }
    final cache = await getTemporaryDirectory();
    final file = File(p.join(
      cache.path, 'ereader-tts-' +
          DateTime.now().microsecondsSinceEpoch.toString() + '.mp3',
    ));
    await file.writeAsBytes(mp3Data, flush: true);
    _activeFile = file;
    try {
      await _player.setFilePath(file.path);
      await _player.setSpeed(speed.clamp(0.5, 2.0).toDouble());
      await _player.play();
    } finally {
      await _player.stop();
      if (await file.exists()) await file.delete();
      if (identical(_activeFile, file)) _activeFile = null;
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.stop();
    await _player.dispose();
    final file = _activeFile;
    if (file != null && await file.exists()) await file.delete();
    _activeFile = null;
  }
}
