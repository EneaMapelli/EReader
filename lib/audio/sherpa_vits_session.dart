import 'dart:async';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'sherpa_vits_worker.dart';

/// Fixed, already-verified local voice configuration, sent once to the
/// worker. The model is never loaded on Flutter's UI isolate.
class VitsSessionModel {
  const VitsSessionModel({
    required this.modelPath,
    required this.tokensPath,
    required this.dataDir,
  });
  final String modelPath;
  final String tokensPath;
  final String dataDir;
}

/// A single reusable local VITS worker. At most ONE outstanding synthesis
/// may use its native OfflineTts object. Stop kills the entire isolate.
class VitsPersistentSession {
  VitsPersistentSession(VitsSessionModel model)
      : this.withEntrypoint(model, vitsPersistentWorkerMain);

  /// Tests inject a pure-Dart worker; no native model or files are required.
  VitsPersistentSession.withEntrypoint(
    VitsSessionModel model,
    void Function((SendPort, VitsSessionModel)) entrypoint,
  ) {
    _events = ReceivePort();
    _subscription = _events.listen(_onMessage);
    unawaited(_spawn(entrypoint, model));
  }

  late final ReceivePort _events;
  late final StreamSubscription<dynamic> _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  List<Object>? _queued;
  Completer<void>? _active;
  int _activeId = 0;
  int _nextId = 0;
  bool _closed = false;

  Future<void> _spawn(
    void Function((SendPort, VitsSessionModel)) worker,
    VitsSessionModel model,
  ) async {
    try {
      final child = await Isolate.spawn<(SendPort, VitsSessionModel)>(
        worker, (_events.sendPort, model),
        onExit: _events.sendPort, onError: _events.sendPort,
        debugName: 'EReader reusable local VITS',
      );
      if (_closed) {
        child.kill(priority: Isolate.immediate);
      } else {
        _isolate = child;
      }
    } catch (_) {
      _closeWith(StateError('Unable to start local voice worker'));
    }
  }

  void _onMessage(dynamic message) {
    if (_closed) return;
    if (message is SendPort) {
      if (_commands != null) {
        _closeWith(StateError('Unexpected second VITS initialization'));
        return;
      }
      _commands = message;
      final queued = _queued;
      _queued = null;
      if (queued != null) message.send(queued);
      return;
    }
    if (message is List && message.length == 2 &&
        message[0] is int && message[1] is int) {
      if (message[0] == 0 && message[1] == _activeId &&
          _active != null) {
        final active = _active!;
        _active = null;
        active.complete();
        return;
      }
      _closeWith(StateError('Local VITS synthesis failed'));
      return;
    }
    // Includes onExit/onError; never return native stack traces or text.
    _closeWith(StateError('Local VITS worker terminated'));
  }

  Future<void> synthesize({
    required String text,
    required String wavPath,
    required double speed,
  }) {
    if (_closed) return Future<void>.error(const VitsWaveCancelled());
    if (_active != null) {
      return Future<void>.error(StateError('Local VITS worker busy'));
    }
    if (text.isEmpty || text.length > 2048 || wavPath.isEmpty ||
        !speed.isFinite || speed <= 0) {
      return Future<void>.error(
          const FormatException('Invalid local VITS request'));
    }
    final active = Completer<void>();
    _active = active;
    _activeId = ++_nextId;
    final payload = <Object>[_activeId, text, wavPath, speed];
    if (_commands == null) {
      _queued = payload;
    } else {
      _commands!.send(payload);
    }
    return active.future;
  }

  void _closeWith(Object reason) {
    if (_closed) return;
    _closed = true;
    final active = _active;
    _active = null;
    _queued = null;
    _commands = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    unawaited(_subscription.cancel());
    _events.close();
    if (active != null && !active.isCompleted) active.completeError(reason);
  }

  /// Invalidate queued/in-flight work even if native FFI does not preempt
  /// instantly. A future explicit Play creates a new model instance.
  void cancel() => _closeWith(const VitsWaveCancelled());
}

/// Executed INSIDE the child isolate. One native model serves every
/// sequential request until cancellation or a sanitized failure.
void vitsPersistentWorkerMain((SendPort, VitsSessionModel) init) async {
  final reply = init.$1;
  final port = ReceivePort();
  sherpa.OfflineTts? tts;
  try {
    sherpa.initBindings();
    final model = init.$2;
    tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: model.modelPath,
          tokens: model.tokensPath,
          dataDir: model.dataDir,
        ),
        numThreads: 2,
        provider: 'cpu',
      ),
    ));
    reply.send(port.sendPort);
    await for (final input in port) {
      if (input is! List || input.length != 4 ||
          input[0] is! int || input[1] is! String ||
          input[2] is! String || input[3] is! double) {
        reply.send([1, -1]);
        break;
      }
      final id = input[0] as int;
      try {
        final audio = tts.generate(
          text: input[1] as String, sid: 0, speed: input[3] as double,
        );
        if (audio.sampleRate < 8000 || audio.sampleRate > 96000 ||
            audio.samples.isEmpty ||
            audio.samples.length > audio.sampleRate * 90) {
          throw const FormatException('Invalid local wave samples');
        }
        if (!sherpa.writeWave(
          filename: input[2] as String,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        )) {
          throw StateError('Unable to write local voice WAV');
        }
        reply.send([0, id]);
      } catch (_) {
        reply.send([1, id]);
        break;
      }
    }
  } catch (_) {
    reply.send([1, -1]);
  } finally {
    port.close();
    tts?.free();
  }
}
