import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Injectable output contract: mock tests avoid native audio plugins.
abstract interface class SynthesizedAudioOutput {
  Future<void> play(Uint8List mp3Data, {required double speed});
  Future<void> stop();
  Future<void> dispose();
}

/// Optional warm MP3 player capability; NO HTTP/TTS request is made here.
/// The bytes must already have been synthesized with separate user consent.
abstract interface class PreloadableSynthesizedAudioOutput
    implements SynthesizedAudioOutput {
  /// Prepare exactly one subsequent clip on an idle decoder.
  /// A matching play() uses the already loaded source. Returns after load.
  Future<void> prepareNext(Uint8List mp3Data, {required double speed});
}

/// Small adapter makes native decoder readiness and cancellation testable.
abstract interface class Mp3Decoder {
  Future<void> load(String filePath, {required double speed});
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioMp3Decoder implements Mp3Decoder {
  JustAudioMp3Decoder() : _player = AudioPlayer();
  final AudioPlayer _player;
  @override
  Future<void> load(String filePath, {required double speed}) async {
    await _player.setFilePath(filePath);
    await _player.setSpeed(speed);
  }
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

class _Mp3Slot {
  _Mp3Slot(this.decoder);
  final Mp3Decoder decoder;
  File? file;
}

/// Two reusable, strictly serial players: one playing and one loading.
/// Unlike a playlist, each clip still completes separately so ReaderPlayer
/// can preserve per-segment progress, read-along and voice attribution.
///
/// A warmed decoder can reduce the file-open/MP3-decode gap but is NOT proof
/// of gapless playback or continuous acoustics on Windows/Android.
/// Both files are temporary, private and deleted on completion/cancellation.
class JustAudioMp3Output implements PreloadableSynthesizedAudioOutput {
  JustAudioMp3Output({
    Mp3Decoder Function()? decoderFactory,
    Future<Directory> Function()? temporaryDirectory,
  })  : _createDecoder = decoderFactory ?? JustAudioMp3Decoder.new,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Mp3Decoder Function() _createDecoder;
  final Future<Directory> Function() _temporaryDirectory;
  _Mp3Slot? _active;
  _Mp3Slot? _standby;
  Future<void>? _preparing;
  Uint8List? _pendingBytes;
  double? _pendingSpeed;
  _Mp3Slot? _pendingSlot;
  int _generation = 0;
  int _fileSerial = 0;
  bool _disposed = false;

  void _check(Uint8List bytes, double speed) {
    if (_disposed) throw StateError('Audio output disposed');
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024 ||
        !speed.isFinite || speed < 0.5 || speed > 2.0) {
      throw const FormatException('Invalid MP3 audio or playback speed');
    }
  }

  _Mp3Slot _idleSlot() {
    if (_active == null) return _active = _Mp3Slot(_createDecoder());
    return _standby ??= _Mp3Slot(_createDecoder());
  }

  Future<void> _clearFile(_Mp3Slot slot) async {
    final file = slot.file;
    slot.file = null;
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Retain failed cleanup path for another try after stop/dispose:
      // Windows can briefly keep MP3 files open after playback completion.
      slot.file = file;
    }
  }

  Future<void> _load(_Mp3Slot slot, Uint8List bytes,
      double speed, int generation) async {
    await slot.decoder.stop();
    await _clearFile(slot);
    if (_disposed || generation != _generation) return;
    final dir = await _temporaryDirectory();
    if (_disposed || generation != _generation) return;
    final filename = 'ereader-tts-' +
        DateTime.now().microsecondsSinceEpoch.toString() + '-' +
        (_fileSerial++).toString() + '.mp3';
    final file = File(p.join(dir.path, filename));
    slot.file = file;
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (_disposed || generation != _generation) return;
      await slot.decoder.load(file.path, speed: speed);
    } catch (_) {
      await _clearFile(slot);
      rethrow;
    } finally {
      if (_disposed || generation != _generation) {
        await _clearFile(slot);
      }
    }
  }

  @override
  Future<void> prepareNext(Uint8List bytes, {required double speed}) async {
    _check(bytes, speed);
    // The caller may only prepare while another clip is playing. Never
    // start a speculative native decoder merely by opening the book.
    if (_active == null) return;
    if (_pendingBytes != null) {
      if (identical(_pendingBytes, bytes) && _pendingSpeed == speed) {
        await _preparing;
      }
      return; // exactly one ahead; no queue expansion
    }
    final token = _generation;
    final slot = _idleSlot();
    _pendingBytes = bytes;
    _pendingSpeed = speed;
    _pendingSlot = slot;
    final task = _load(slot, bytes, speed, token);
    _preparing = task;
    try {
      await task;
    } catch (_) {
      if (token == _generation && identical(_pendingSlot, slot)) {
        _pendingBytes = null;
        _pendingSpeed = null;
        _pendingSlot = null;
        _preparing = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> play(Uint8List bytes, {required double speed}) async {
    _check(bytes, speed);
    final token = _generation;
    _Mp3Slot slot;
    if (_active == null) {
      slot = _idleSlot();
      await _load(slot, bytes, speed, token);
    } else if (identical(_pendingBytes, bytes) &&
        _pendingSpeed == speed && _pendingSlot != null) {
      slot = _pendingSlot!;
      final task = _preparing;
      // The warm load can still be in flight when the previous MP3 ends.
      if (task != null) await task;
      if (_disposed || token != _generation) return;
      final old = _active;
      _active = slot;
      _standby = old;
      _pendingBytes = null;
      _pendingSpeed = null;
      _pendingSlot = null;
      _preparing = null;
    } else {
      // No usable standby; reuse the current decoder for a cold load.
      // The pending standby remains reserved until it is explicitly stopped.
      slot = _active!;
      await _load(slot, bytes, speed, token);
    }
    if (_disposed || token != _generation) return;
    try {
      await slot.decoder.play();
    } finally {
      // Release the native file handle before erasing private temporary
      // audio, particularly for the Windows Media Player implementation.
      await slot.decoder.stop();
      await _clearFile(slot);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _pendingBytes = null;
    _pendingSpeed = null;
    _pendingSlot = null;
    _preparing = null;
    final slots = <_Mp3Slot>{if (_active != null) _active!,
        if (_standby != null) _standby!};
    await Future.wait([
      for (final slot in slots) slot.decoder.stop(),
    ]);
    await Future.wait([
      for (final slot in slots) _clearFile(slot),
    ]);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    final slots = <_Mp3Slot>{if (_active != null) _active!,
        if (_standby != null) _standby!};
    await Future.wait([
      for (final slot in slots) slot.decoder.dispose(),
    ]);
    _active = null;
    _standby = null;
  }
}
