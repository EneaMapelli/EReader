import '../data/offline_voice_pack.dart';
import 'speech_engine.dart';
import 'sherpa_vits_engine.dart';

typedef OfflineVoicePackLoader =
    Future<InstalledOfflineVoicePack> Function(String packId);
typedef OfflineVoiceAuditionEngineFactory =
    SpeechEngine Function(InstalledOfflineVoicePack pack);

/// Short PUBLIC examples only. Never use book text or uploaded data here.
/// Unsupported language tags are explicitly refused, not approximated.
String? offlineVoiceSampleText(String locale) {
  switch (locale.toLowerCase().replaceAll('_', '-').split('-').first) {
    case 'it':
      return 'Buongiorno! Questa voce funziona senza inviare il testo '
          'a servizi online. Come suonano le pause e le domande?';
    case 'en':
      return 'Hello! This voice reads locally without sending book text '
          'to an online service. Can you hear the pauses and questions?';
    default:
      return null;
  }
}

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

  bool get isPlaying => _running;

  Future<void> play(String packId) async {
    if (_disposed) throw StateError('Voice preview is closed');
    if (_running) throw StateError('A voice preview is already running');
    _running = true;
    final token = ++_epoch;
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
      // When Stop detached this engine, Stop exclusively owns disposal.
      if (owned != null && identical(_active, owned)) {
        _active = null;
        await owned.dispose();
      }
      _running = false;
    }
  }

  Future<void> stop() {
    ++_epoch;
    final engine = _active;
    _active = null;
    if (engine == null) return _stopping;
    final prior = _stopping;
    return _stopping = () async {
      await prior;
      try {
        await engine.stop();
      } finally {
        await engine.dispose();
      }
    }();
  }

  Future<void> dispose() {
    _disposed = true;
    return stop();
  }
}
