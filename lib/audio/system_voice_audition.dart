import 'dart:async';

import 'speech_engine.dart';

/// Local fixed samples for user-initiated comparisons of installed OS
/// voices. The caller never supplies EPUB/PDF text, secrets or API keys.
/// Unsupported languages are NOT guessed with a different locale.
String? systemVoiceSampleText(String locale) {
  switch (locale.toLowerCase().replaceAll('_', '-').split('-').first) {
    case 'it':
      return 'Buongiorno! Questa è una prova della voce italiana. '
          'Come suonano le pause, i dialoghi e le domande?';
    case 'en':
      return 'Hello! This is a sample of the English voice. '
          'How natural do the pauses and questions sound?';
    case 'fr':
      return 'Bonjour ! Voici un exemple de voix française. '
          'Les pauses et les questions sont-elles naturelles ?';
    case 'es':
      return '¡Hola! Esta es una prueba de la voz española. '
          '¿Cómo suenan las pausas y las preguntas?';
    case 'de':
      return 'Guten Tag! Dies ist eine Probe der deutschen Stimme. '
          'Wie natürlich klingen Pausen und Fragen?';
    case 'pt':
      return 'Olá! Esta é uma amostra da voz portuguesa. '
          'Como soam as pausas e as perguntas?';
    default:
      return null;
  }
}

typedef SystemVoiceAuditionEngineFactory = SpeechEngine Function(
    bool interpretWindowsPunctuation);

/// An isolated, cancellable audition of ONE installed Windows/Android voice.
/// It never touches ReaderPlayer, cloud consent, the book checkpoint or cast.
///
/// Catalog presence is rechecked on Play. Stop invalidates even a pending
/// catalog or voice change, and owns native disposal after taking _active.
/// A new audition waits for the prior native Stop/Dispose barrier.
class SystemVoiceAudition {
  SystemVoiceAudition({SystemVoiceAuditionEngineFactory? createEngine})
      : _createEngine = createEngine ??
            ((interpret) => SystemSpeechEngine(
                interpretWindowsPunctuation: interpret));

  final SystemVoiceAuditionEngineFactory _createEngine;
  SpeechEngine? _active;
  Future<void> _stopping = Future<void>.value();
  int _epoch = 0;
  bool _running = false;
  bool _listing = false;
  bool _disposed = false;
  Completer<void>? _activeSettled;

  bool get isPlaying => _running;

  Future<List<SpeechVoice>> listVoices() async {
    if (_disposed) throw StateError('Voice audition is closed');
    if (_running || _listing) {
      throw StateError('Finish the current voice operation first');
    }
    _listing = true;
    SpeechEngine? engine;
    try {
      await _stopping;
      if (_disposed) throw StateError('Voice audition is closed');
      engine = _createEngine(false);
      final raw = await engine.listVoices();
      final unique = <String, SpeechVoice>{};
      for (final voice in raw) {
        if (voice.name.trim().isEmpty || voice.locale.trim().isEmpty) {
          continue;
        }
        unique.putIfAbsent(voice.key, () => voice);
      }
      final voices = unique.values.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      return List<SpeechVoice>.unmodifiable(voices);
    } finally {
      try {
        await engine?.dispose();
      } finally {
        _listing = false;
      }
    }
  }

  Future<void> play(SpeechVoice voice, {
    bool interpretWindowsPunctuation = false,
    double rate = 0.5,
    double pitch = 1.0,
  }) async {
    if (_disposed) throw StateError('Voice audition is closed');
    if (_running || _listing) {
      throw StateError('A system voice operation is already running');
    }
    final sample = systemVoiceSampleText(voice.locale);
    if (sample == null) {
      throw const FormatException(
          'No fixed local voice sample for the selected language');
    }
    if (!rate.isFinite || rate < 0.2 || rate > 1.0 ||
        !pitch.isFinite || pitch < 0.5 || pitch > 1.5) {
      throw const FormatException('Invalid voice sample speed or pitch');
    }
    _running = true;
    final token = ++_epoch;
    final settled = Completer<void>();
    _activeSettled = settled;
    SpeechEngine? owned;
    try {
      await _stopping;
      if (_disposed || token != _epoch) return;
      owned = _createEngine(interpretWindowsPunctuation);
      _active = owned;
      final available = await owned.listVoices();
      if (_disposed || token != _epoch) return;
      if (!available.any((entry) => entry.key == voice.key)) {
        throw const FormatException(
            'Selected voice is no longer installed on this device');
      }
      await owned.chooseVoice(voice);
      if (_disposed || token != _epoch) return;
      await owned.speak(sample,
          language: voice.locale, rate: rate, pitch: pitch);
    } finally {
      try {
        // Stop takes exclusive responsibility for the old native engine.
        if (owned != null && identical(_active, owned)) {
          _active = null;
          await owned.dispose();
        }
      } finally {
        _running = false;
        if (identical(_activeSettled, settled)) _activeSettled = null;
        if (!settled.isCompleted) settled.complete();
      }
    }
  }

  Future<void> stop() {
    ++_epoch;
    final engine = _active;
    final settled = _activeSettled?.future;
    _active = null;
    if (engine == null) return _stopping;
    final prior = _stopping;
    return _stopping = () async {
      await prior;
      try {
        await engine.stop();
      } finally {
        // A native listVoices/chooseVoice call can finish AFTER Stop.
        // Wait until the cancelled Play has unwound before disposing
        // its engine or permitting a different voice to start.
        if (settled != null) await settled;
        await engine.dispose();
      }
    }();
  }

  Future<void> dispose() {
    _disposed = true;
    return stop();
  }
}
