import 'dart:async';
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

Future<void> _deletePrivateMp3File(File file) async {
  if (await file.exists()) await file.delete();
}

class _Mp3Slot {
  _Mp3Slot(this.decoder);
  final Mp3Decoder decoder;
  File? file;
  // Native setFilePath/stop must not race on the SAME physical decoder
  // when a new session starts before an older load has completed.
  Future<void> loading = Future<void>.value();
  // Covers native load as well as the temporary-file write. Stop must
  // not race setFilePath and must not wait for a hung *idle* decoder.
  bool loadingInFlight = false;
  // Only a confirmed native Stop releases this obligation. A completed
  // decoder.play Future is NOT proof that its file handle is closed.
  // New decoders are already stopped, so their first load skips Stop.
  bool needsNativeStop = false;
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
    Future<void> Function(File file)? deleteTemporaryFile,
  })  : _createDecoder = decoderFactory ?? JustAudioMp3Decoder.new,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _deleteTemporaryFile =
            deleteTemporaryFile ?? _deletePrivateMp3File;

  final Mp3Decoder Function() _createDecoder;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(File file) _deleteTemporaryFile;
  // Deletion may fail transiently while Windows holds a native file handle.
  // Keep the path even if the decoder slot is reused; retry on disposal.
  final Set<File> _deferredDeletions = <File>{};
  static const int _maxDeferredDeletions = 64;
  Future<void>? _disposeFuture;
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

  Future<void> _tryDelete(File file) async {
    try {
      await _deleteTemporaryFile(file);
      _deferredDeletions.remove(file);
    } on FileSystemException {
      // Do not discard the path when a Windows decoder still holds it.
      // An unrelated new clip can replace slot.file in the meantime.
      _deferredDeletions.add(file);
    }
  }

  Future<void> _clearFile(_Mp3Slot slot, {File? expected}) async {
    final file = slot.file;
    if (file == null ||
        (expected != null && !identical(file, expected))) return;
    slot.file = null;
    await _tryDelete(file);
  }

  Future<void> _retryDeferredDeletions() async {
    for (final file in _deferredDeletions.toList()) {
      await _tryDelete(file);
    }
  }

  Future<void> _load(_Mp3Slot slot, Uint8List bytes,
      double speed, int generation) {
    final previous = slot.loading;
    final task = () async {
      try {
        await previous;
      } catch (_) {
        // A failed former load should not poison later sessions.
      }
      if (_disposed || generation != _generation) return;
      // Persistent filesystem failures must not create an unbounded
      // collection of undeletable temporary MP3 files.
      if (_deferredDeletions.length >= _maxDeferredDeletions) {
        throw StateError('Too many MP3 files awaiting cleanup');
      }
      slot.loadingInFlight = true;
      try {
        // This decoder's previous load/finalizer is serialized above.
        // A redundant second native Stop increases cold-handoff latency.
        // Never elide Stop after a failed/unfinished native load or play.
        if (slot.needsNativeStop) {
          await slot.decoder.stop();
          slot.needsNativeStop = false;
        }
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
          // Set BEFORE awaiting the native call, so a failed or interrupted
          // setFilePath still requires an explicit Stop before file reuse.
          slot.needsNativeStop = true;
          await slot.decoder.load(file.path, speed: speed);
        } catch (_) {
          // setFilePath may have opened a native handle before failing.
          // Settle Stop BEFORE deleting the working MP3; if native Stop
          // itself fails, retain the obligation for the next retry.
          try {
            await slot.decoder.stop();
            slot.needsNativeStop = false;
          } catch (_) {
            // The next Stop/load must try again; Windows may still hold
            // this file open, and deletion will be deferred safely.
          }
          await _clearFile(slot, expected: file);
          rethrow;
        } finally {
          // A generation cancelled while native setFilePath is still in
          // flight owns this file until that operation has actually ended.
          if (_disposed || generation != _generation) {
            await _clearFile(slot, expected: file);
          }
        }
      } finally {
        slot.loadingInFlight = false;
      }
    }();
    slot.loading = task;
    return task;
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

  void _discardPrepared() {
    final slot = _pendingSlot;
    // A mismatched new clip plays on the active decoder and must not be
    // blocked by an obsolete warm load stalled on the *other* decoder.
    // Drop the pending identity synchronously so it cannot be played.
    _pendingBytes = null;
    _pendingSpeed = null;
    _pendingSlot = null;
    _preparing = null;
    if (slot == null) return;
    // _stopSlot appends cleanup to slot.loading immediately. Later warm
    // requests on this physical decoder therefore queue AFTER the stale
    // decoder load and its Stop, rather than racing either operation.
    unawaited(_stopSlot(slot).catchError((Object _) {
      // Any native cleanup error is isolated from the new audible clip;
      // dispose() still waits for and cleans the old physical slot.
    }));
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
      // A seek, voice/speed change or different cached clip must invalidate
      // the stale warm slot. Otherwise it would block all future preloads.
      if (_pendingBytes != null) _discardPrepared();
      if (_disposed || token != _generation) return;
      slot = _active!;
      await _load(slot, bytes, speed, token);
    }
    if (_disposed || token != _generation) return;
    final playedFile = slot.file;
    try {
      await slot.decoder.play();
    } finally {
      // Serialize the native end-of-clip stop against the NEXT load on this
      // same decoder. A delayed old generation cannot stop or delete a
      // restarted segment's private MP3.
      final prior = slot.loading;
      final finishing = () async {
        try { await prior; } catch (_) {
          // Failed prior load does not prevent stop/cleanup.
        }
        if (_disposed || token != _generation) return;
        // Do not release this slot until the same decoder has confirmed
        // Stop; other slots may warm concurrently, never play concurrently.
        await slot.decoder.stop();
        slot.needsNativeStop = false;
        if (_disposed || token != _generation) return;
        await _clearFile(slot, expected: playedFile);
      }();
      slot.loading = finishing;
      await finishing;
    }
  }

  /// Serialize Stop and file deletion with every earlier native load and
  /// previous clip finalizer on this exact physical decoder. A later play()
  /// chains after this barrier, even if it starts immediately after Stop.
  Future<void> _stopSlot(_Mp3Slot slot) {
    final previous = slot.loading;
    final stopping = () async {
      try {
        await previous;
      } catch (_) {
        // A failed load must still be followed by native Stop and cleanup.
      }
      if (slot.needsNativeStop) {
        await slot.decoder.stop();
        slot.needsNativeStop = false;
      }
      await _clearFile(slot);
    }();
    slot.loading = stopping;
    return stopping;
  }

  @override
  Future<void> stop() async {
    // Invalidate pending playback synchronously, before any native await.
    _generation++;
    _pendingBytes = null;
    _pendingSpeed = null;
    _pendingSlot = null;
    _preparing = null;

    final active = _active;
    final standby = _standby;
    // Warming must never delay Stop of the audible clip: the old standby
    // load may be blocked inside platform setFilePath. Queue its cleanup
    // after that load, but don't wait for the idle decoder in this case.
    final standbyLoading = standby?.loadingInFlight ?? false;
    final activeStop = active == null ? null : _stopSlot(active);
    final standbyStop = standby == null ? null : _stopSlot(standby);
    if (standbyLoading && standbyStop != null) {
      unawaited(standbyStop.catchError((Object _) {
        // Disposing the decoder will retry cleanup after native load ends.
      }));
    }
    if (activeStop != null) await activeStop;
    if (!standbyLoading && standbyStop != null) await standbyStop;
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _disposeAll();

  Future<void> _disposeAll() async {
    _disposed = true;
    final slots = <_Mp3Slot>{
      if (_active != null) _active!,
      if (_standby != null) _standby!,
    };
    try {
      await stop();
    } finally {
      // Unlike Stop, disposal must not free a decoder still inside a
      // native load. Wait for deferred cleanup, then release handles.
      for (final slot in slots) {
        try {
          await slot.loading;
        } catch (_) {
          // A failed native load still needs decoder disposal.
        }
      }
      try {
        await Future.wait([
          for (final slot in slots) slot.decoder.dispose(),
        ]);
      } finally {
        await Future.wait([
          for (final slot in slots) _clearFile(slot),
        ]);
        // Retry orphaned files only after BOTH decoders have been released.
        await _retryDeferredDeletions();
        _active = null;
        _standby = null;
      }
    }
  }
}
