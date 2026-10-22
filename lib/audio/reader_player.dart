import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/speech_segment.dart';
import '../domain/speech_preferences.dart';
import 'speech_engine.dart';

typedef SegmentStarted = Future<void> Function(SpeechSegment segment);

/// Serialized speech queue with session tokens to invalidate interrupted runs.
/// Pause stops the current native utterance; resume RESTARTS that segment.
/// Word-level timing and background sessions are not claimed in this milestone.
class ReaderPlayer extends ChangeNotifier {
  ReaderPlayer({
    required SpeechEngine engine,
    required List<SpeechSegment> segments,
    required this.onSegmentStarted,
    this.language = 'it-IT',
  }) : _engine = engine, _segments = segments;

  final SpeechEngine _engine;
  final List<SpeechSegment> _segments;
  final SegmentStarted onSegmentStarted;
  String language;
  double rate = 0.5;
  double pitch = 1.0;
  List<SpeechVoice> availableVoices = const [];
  SpeechVoice? selectedVoice;

  /// Called immediately before TTS. Display text and reading offsets remain
  /// untouched even when pronunciation replacements change string length.
  String Function(String)? speechTextTransform;

  Future<void> loadVoices() async {
    try {
      availableVoices = await _engine.listVoices();
    } catch (_) {
      // Missing system TTS engine or unsupported voice enumeration.
      availableVoices = const [];
    }
    _notify();
  }

  Future<void> selectVoice(SpeechVoice voice) async {
    await pause();
    await _engine.chooseVoice(voice);
    selectedVoice = voice;
    language = voice.locale;
    _notify();
  }

  Future<void> applyPreferences(SpeechPreferences preferences) async {
    preferences.validate();
    if (preferences.providerId != 'system') {
      throw UnsupportedError('TTS provider is not installed: '
          + preferences.providerId);
    }
    if (isPlaying) await pause();
    language = preferences.language;
    rate = preferences.rate;
    pitch = preferences.pitch;
    selectedVoice = null;
    if (preferences.voiceName != null && preferences.voiceLocale != null) {
      for (final voice in availableVoices) {
        if (voice.name == preferences.voiceName &&
            voice.locale == preferences.voiceLocale) {
          await _engine.chooseVoice(voice);
          selectedVoice = voice;
          break;
        }
      }
    }
    _notify();
  }

  SpeechPreferences get currentPreferences => SpeechPreferences(
        providerId: 'system',
        language: language,
        rate: rate,
        pitch: pitch,
        voiceName: selectedVoice?.name,
        voiceLocale: selectedVoice?.locale,
      );

  void setPitch(double value) {
    pitch = value;
    _notify();
  }

  int currentIndex = 0;
  bool isPlaying = false;
  int _session = 0;
  bool _disposed = false;
  Future<void> _pendingStop = Future<void>.value();
  Object? lastError;

  List<SpeechSegment> get segments => _segments;
  bool get hasNext => currentIndex + 1 < _segments.length;

  void setRate(double value) {
    rate = value;
    _notify();
  }

  void setLanguage(String value) {
    language = value;
    _notify();
  }

  Future<void> play() async {
    if (isPlaying || _segments.isEmpty) return;
    if (currentIndex >= _segments.length) currentIndex = 0;
    final token = ++_session;
    isPlaying = true;
    lastError = null;
    _notify();
    try {
      // A rapid pause/play must not synthesize before the old native
      // utterance has fully stopped, otherwise voices overlap.
      await _pendingStop;
      while (token == _session && currentIndex < _segments.length) {
        final segment = _segments[currentIndex];
        await onSegmentStarted(segment);
        if (token != _session) return;
        final spokenText =
            speechTextTransform?.call(segment.text) ?? segment.text;
        await _engine.speak(spokenText,
            language: language, rate: rate, pitch: pitch);
        if (token != _session) return;
        currentIndex++;
        _notify();
      }
    } catch (error) {
      if (token == _session) {
        lastError = error;
        _notify();
      }
      rethrow;
    } finally {
      if (token == _session) {
        isPlaying = false;
        _notify();
      }
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _session++;
    isPlaying = false;
    _notify();
    // Serialize stop commands; the next play waits for their completion.
    final priorStop = _pendingStop;
    final stopping = () async {
      try {
        await priorStop;
      } catch (_) {
        // A previous stop failure must not prevent a new stop attempt.
      }
      await _engine.stop();
    }();
    _pendingStop = stopping;
    await stopping;
  }

  Future<void> seekTo(int index) async {
    final restart = isPlaying;
    await pause();
    if (_disposed || _segments.isEmpty) return;
    currentIndex = index.clamp(0, _segments.length - 1).toInt();
    _notify();
    if (restart) {
      // Seeking must return as soon as playback is restarted, not only when
      // the rest of the book finishes. Surface asynchronous errors to the UI.
      unawaited(play().catchError((Object error, StackTrace stack) {
        lastError = error;
        _notify();
      }));
    }
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _session++;
    _disposed = true;
    unawaited(_engine.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
