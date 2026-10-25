import 'dart:async';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// All data sent into the native isolate is immutable and isolate-sendable.
class VitsWaveRequest {
  const VitsWaveRequest({
    required this.text,
    required this.modelPath,
    required this.tokensPath,
    required this.dataDir,
    required this.wavPath,
    required this.speed,
  });

  final String text;
  final String modelPath;
  final String tokensPath;
  final String dataDir;
  final String wavPath;
  final double speed;
}

class VitsWaveCancelled implements Exception {
  const VitsWaveCancelled();
}

/// A cancellable one-utterance native job. Killing the isolate terminates
/// the FFI worker rather than merely discarding a late Future result.
/// Native cleanup on forced termination is platform-specific: every next
/// request starts a fresh isolate and a fresh Sherpa model instance.
class VitsWaveJob {
  VitsWaveJob(VitsWaveRequest request)
      : this.withEntrypoint(request, vitsWaveWorkerMain);

  /// Allows tests to spawn a synthetic worker with no ONNX library.
  VitsWaveJob.withEntrypoint(
    VitsWaveRequest request,
    void Function((SendPort, VitsWaveRequest)) entrypoint,
  ) {
    _port = ReceivePort();
    _subscription = _port.listen(_handleMessage);
    unawaited(_spawn(entrypoint, request));
  }

  late final ReceivePort _port;
  late final StreamSubscription<dynamic> _subscription;
  final Completer<void> _completion = Completer<void>();
  Isolate? _worker;
  Timer? _exitGrace;
  bool _ended = false;

  Future<void> get result => _completion.future;

  Future<void> _spawn(
    void Function((SendPort, VitsWaveRequest)) entrypoint,
    VitsWaveRequest request,
  ) async {
    try {
      final isolate = await Isolate.spawn<(SendPort, VitsWaveRequest)>(
        entrypoint,
        (_port.sendPort, request),
        onExit: _port.sendPort,
        onError: _port.sendPort,
        debugName: 'EReader local neural synthesis',
      );
      if (_ended) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _worker = isolate;
      }
    } catch (_) {
      _fail(StateError('Unable to start offline neural synthesis'));
    }
  }

  void _handleMessage(dynamic message) {
    if (_ended) return;
    if (message == null) {
      // Isolate.exit() result and onExit signals can arrive in either order.
      // A short bounded grace avoids reporting false failures under load.
      _exitGrace ??= Timer(const Duration(seconds: 3), () {
        _fail(StateError('Offline synthesis exited without a result'));
      });
      return;
    }
    if (message is List && message.length == 1 && message[0] == 0) {
      _ended = true;
      _close();
      _completion.complete();
    } else {
      // Native error messages and stacks are deliberately not exposed.
      _fail(StateError('Offline neural synthesis failed'));
    }
  }

  void _fail(Object error) {
    if (_ended) return;
    _ended = true;
    _worker?.kill(priority: Isolate.immediate);
    _close();
    _completion.completeError(error);
  }

  void _close() {
    _exitGrace?.cancel();
    _exitGrace = null;
    unawaited(_subscription.cancel());
    _port.close();
    _worker = null;
  }

  void cancel() => _fail(const VitsWaveCancelled());
}

/// Called INSIDE the spawned worker isolate, never on Flutter's UI isolate.
void vitsWaveWorkerMain((SendPort, VitsWaveRequest) message) {
  final reply = message.$1;
  final request = message.$2;
  try {
    sherpa.initBindings();
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: request.modelPath,
          tokens: request.tokensPath,
          dataDir: request.dataDir,
        ),
        numThreads: 2,
        provider: 'cpu',
      ),
    );
    final tts = sherpa.OfflineTts(config);
    try {
      final audio = tts.generate(
        text: request.text, sid: 0, speed: request.speed,
      );
      if (audio.sampleRate < 8000 || audio.sampleRate > 96000 ||
          audio.samples.isEmpty ||
          audio.samples.length > audio.sampleRate * 90) {
        throw const FormatException('Invalid offline audio');
      }
      if (!sherpa.writeWave(
        filename: request.wavPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      )) {
        throw StateError('Cannot write offline WAV output');
      }
    } finally {
      tts.free();
    }
    Isolate.exit(reply, [0]);
  } catch (_) {
    // Never send book passages, file paths or native stacks to the caller.
    Isolate.exit(reply, [1]);
  }
}
