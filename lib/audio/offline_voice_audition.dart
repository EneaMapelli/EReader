import 'dart:async';

import '../data/offline_voice_pack.dart';
import 'speech_engine.dart';
import 'sherpa_vits_engine.dart';
import 'system_voice_audition.dart';

typedef OfflineVoicePackLoader =
    Future<InstalledOfflineVoicePack> Function(String packId);
typedef OfflineVoiceAuditionEngineFactory =
    SpeechEngine Function(InstalledOfflineVoicePack pack);

/// Use the SAME public, fixed, locale-appropriate phrase as the system
/// voice audition so a listener can compare timbre and punctuation instead
/// of comparing different scripts. No book text or user content enters it.
/// Unknown locales are refused before model load, never translated blindly.
String? offlineVoiceSampleText(String locale) =>
    systemVoiceSampleText(locale);

/// Isolated, opt-in offline audition. No book ID, cloud keys, cached paid
/// speech, preferences or user text can enter this API. A pack is re-verified
/// on every Play before a native model is constructed.
///
/// Stop invalidates an in-flight SHA verification BEFORE any synthesis.
/// Native Stop and Dispose settle before another engine may be started.
class OfflineVoiceAudition {
  OfflineVoiceAudition({
    required OfflineVoicePackLoader loadPack,
    OfflineVoiceAuditionEngineFactory? createEngine,
  }) : _loadPack = loadPack,
       _createEngine = createEngine ?? _nativeEngine;

  final OfflineVoicePackLoader _loadPack;
  final OfflineVoiceAuditionEngineFactory _createEngine;
  static SpeechEngine _nativeEngine(InstalledOfflineVoicePack pack) =>
      SherpaVitsSpeechEngine(
        pack: pack, dataDir: pack.phonemizerDataDir!,
      );

  SpeechEngine? _active;
  Future<void> _stopping = Future<void>.value();
  int _epoch = 0;
  bool _running = false;
  bool _disposed = false;
  // Native chooseVoice and speak can remain in flight after Stop starts.
  // Stop exclusively disposes a detached engine only when Play has
  // unwound from those operations; otherwise native FFI may be torn down
  // while an earlier voice selection still holds its model.
  Completer<void>? _activeSettled;

  bool get isPlaying => _running;

  Future<void> play(String packId) async {
    if (_disposed) throw StateError('Voice preview is closed');
    if (_running) throw StateError('A voice preview is already running');
    _running = true;
    final token = ++_epoch;
    final settled = Completer<void>();
    _activeSettled = settled;
    SpeechEngine? owned;
    try {
      await _stopping;
      if (_disposed || token != _epoch) return;
      final pack = await _loadPack(packId);
      if (_disposed || token != _epoch) return;
      if (pack.manifest.id != packId || pack.phonemizerDataDir == null) {
        throw const FormatException(
          'Voice pack identity or phonemizer data is unavailable',
        );
      }
      final sample = offlineVoiceSampleText(pack.manifest.locale);
      if (sample == null) {
        throw const FormatException(
          'No verified demonstration text for this language',
        );
      }
      owned = _createEngine(pack);
      _active = owned;
      await owned.chooseVoice(SpeechVoice(
          name: pack.manifest.id, locale: pack.manifest.locale));
      if (_disposed || token != _epoch) return;
      await owned.speak(
        sample,
        language: pack.manifest.locale,
        rate: 0.5,
        pitch: 1.0,
      );
    } finally {
      try {
        // When Stop detached this engine, Stop exclusively owns disposal.
        if (owned != null && identical(_active, owned)) {
          _active = null;
          await owned.dispose();
        }
      } finally {
        // Even native cleanup failure must not leave a permanently busy UI.
        // Failure is reported rather than silently retrying model execution.
        _running = false;
        if (identical(_activeSettled, settled)) {
          _activeSettled = null;
        }
        if (!settled.isCompleted) settled.complete();
      }
    }
  }

  Future<void> stop() {
    ++_epoch;
    final engine = _active;
    final settled = _activeSettled?.future;
    _active = null;
    // A cancelled SHA verification has no native model to stop. Do not
    // block the Stop button on disk IO; the epoch prevents model loading.
    if (engine == null) return _stopping;
    final prior = _stopping;
    return _stopping = () async {
      await prior;
      try {
        await engine.stop();
      } finally {
        try {
          // If chooseVoice returns only after Stop, wait for the cancelled
          // Play callback before releasing the engine's native handles.
          if (settled != null) await settled;
        } finally {
          await engine.dispose();
        }
      }
    }();
  }

  Future<void> dispose() {
    _disposed = true;
    return stop();
  }
}
