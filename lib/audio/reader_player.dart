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
    this.engineProviderId = 'system',
  }) : _engine = engine, _segments = segments;

  final SpeechEngine _engine;
  final List<SpeechSegment> _segments;
  final SegmentStarted onSegmentStarted;
  final String engineProviderId;
  String language;
  double rate = 0.5;
  double pitch = 1.0;
  List<SpeechVoice> availableVoices = const [];
  SpeechVoice? selectedVoice;
  String _providerId = 'system';
  String _modelId = 'gpt-4o-mini-tts';

  /// Called immediately before TTS. Display text and reading offsets remain
  /// untouched even when pronunciation replacements change string length.
  String Function(String)? speechTextTransform;

  /// The narrator voice remains selectedVoice. For a manually attributed
  /// segment, the resolver may choose a provider-specific installed voice.
  /// Missing/unknown voices always fall back to narrator.
  SpeechVoice? Function(SpeechSegment)? castVoiceForSegment;
  String? Function(SpeechSegment)? castSpeakerForSegment;
  String? activeSpeakerId;
  String? _engineVoiceKey;

  /// Deliberately session-only and OFF by default: an uncached cloud
  /// lookahead can spend quota before the reader reaches that passage.
  bool prefetchNextCloudChunk = false;

  void setCloudPrefetch(bool enabled) {
    if (engineProviderId != 'openai-speech') return;
    prefetchNextCloudChunk = enabled;
    // Disabling stops future scheduling. A previously paid lookahead may
    // still finish and be reused for the next passage, avoiding a retry.
    _notify();
  }

  SpeechVoice? _voiceFor(SpeechSegment segment) {
    final chosen = castVoiceForSegment?.call(segment);
    SpeechVoice? fallback = selectedVoice;
    if (fallback == null && availableVoices.isNotEmpty) {
      fallback = availableVoices.first;
      if (engineProviderId == 'openai-speech') {
        for (final voice in availableVoices) {
          if (voice.name == 'marin') { fallback = voice; break; }
        }
      }
    }
    final requested = chosen ?? fallback;
    if (requested == null) return null;
    for (final voice in availableVoices) {
      if (voice.key == requested.key) return voice;
    }
    return null;
  }


  Future<void> loadVoices() async {
    try {
      availableVoices = await _engine.listVoices();
      _engineVoiceKey = null;
    } catch (_) {
      // Missing system TTS engine or unsupported voice enumeration.
      availableVoices = const [];
    }
    _notify();
  }

  Future<void> selectVoice(SpeechVoice voice) async {
    if (_disposed) return;
    final shouldResume = isPlaying || _resumeAfterNavigation;
    final epoch = ++_navigationEpoch;
    _resumeAfterNavigation = shouldResume;
    await _stopCurrent();
    if (_disposed || epoch != _navigationEpoch) return;
    // Native voice switches are serialized: an old platform method call
    // cannot finish AFTER a newer choice and overwrite the wanted timbre.
    final previous = _pendingVoiceChange;
    final changing = () async {
      try { await previous; } catch (_) {
        // A failed prior choice cannot block the user's new selection.
      }
      if (_disposed || epoch != _navigationEpoch) return;
      await _engine.chooseVoice(voice);
      if (_disposed || epoch != _navigationEpoch) {
        // The native voice may have changed despite cancellation. Force
        // the next live utterance to reapply its intended narrator/cast.
        _engineVoiceKey = null;
        return;
      }
      _engineVoiceKey = voice.key;
      selectedVoice = voice;
      if (voice.locale != 'multi') language = voice.locale;
      _notify();
    }();
    _pendingVoiceChange = changing;
    await changing;
    if (_disposed || epoch != _navigationEpoch) return;
    _resumeAfterNavigation = false;
    if (shouldResume) _resumeUnawaited();
  }

  Future<void> applyPreferences(SpeechPreferences preferences) async {
    preferences.validate();
    if (preferences.providerId != engineProviderId) {
      throw UnsupportedError(
        'Speech provider does not match the active engine: '
            + preferences.providerId,
      );
    }
    if (isPlaying) await pause();
    _providerId = preferences.providerId;
    _modelId = preferences.modelId;
    language = preferences.language;
    rate = preferences.rate;
    pitch = preferences.pitch;
    selectedVoice = null;
    _engineVoiceKey = null;
    if (preferences.voiceName != null && preferences.voiceLocale != null) {
      for (final voice in availableVoices) {
        if (voice.name == preferences.voiceName &&
            voice.locale == preferences.voiceLocale) {
          await _engine.chooseVoice(voice);
          _engineVoiceKey = voice.key;
          selectedVoice = voice;
          break;
        }
      }
    }
    _notify();
  }

  SpeechPreferences get currentPreferences => SpeechPreferences(
        providerId: _providerId,
        modelId: _modelId,
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
  int _navigationEpoch = 0;
  bool _resumeAfterNavigation = false;
  bool _disposed = false;
  Future<void> _pendingStop = Future<void>.value();
  Future<void> _pendingVoiceChange = Future<void>.value();
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
    if (_disposed || isPlaying || _segments.isEmpty) return;
    // A direct Play invalidates outstanding seeks after their awaited stop.
    _navigationEpoch++;
    _resumeAfterNavigation = false;
    if (currentIndex >= _segments.length) currentIndex = 0;
    final token = ++_session;
    isPlaying = true;
    lastError = null;
    _notify();
    try {
      // A rapid pause/play must not synthesize before the old native
      // utterance has fully stopped, otherwise voices overlap.
      await _pendingStop;
      // Wait out voice selection in flight before starting a new clip.
      try { await _pendingVoiceChange; } catch (_) {
        if (token == _session) rethrow;
      }
      while (token == _session && currentIndex < _segments.length) {
        final segment = _segments[currentIndex];
        await onSegmentStarted(segment);
        if (token != _session) return;
        // Cast affects only synthesis voice, never text, offsets or order.
        // A narrator voice MUST be restored after a character's turn.
        // A previous asynchronous native voice selection can complete
        // after an interrupted session. Reapply the chosen narrator voice
        // even when no multi-character casting callback is installed.
        final installed = castVoiceForSegment != null
            ? _voiceFor(segment) : selectedVoice;
        if (installed != null && installed.key != _engineVoiceKey) {
          await _engine.chooseVoice(installed);
          _engineVoiceKey = installed.key;
        }
        if (token != _session) return;
        activeSpeakerId = castSpeakerForSegment?.call(segment);
        _notify();
        final spokenText =
            speechTextTransform?.call(segment.text) ?? segment.text;
        final playing = _engine.speak(spokenText,
            language: language, rate: rate, pitch: pitch);
        // The cloud implementation waits until current audio is ready
        // before spending any quota on the next chunk. Only ONE future
        // clip is prepared; actual audio output stays strictly serial.
        if (prefetchNextCloudChunk &&
            engineProviderId == 'openai-speech' &&
            _engine is AheadOfTimeSpeechEngine &&
            currentIndex + 1 < _segments.length) {
          final next = _segments[currentIndex + 1];
          final nextText =
              speechTextTransform?.call(next.text) ?? next.text;
          final cap = _engine as AheadOfTimeSpeechEngine;
          unawaited(cap.prepareSpeech(
            nextText,
            voice: _voiceFor(next),
            language: language, rate: rate, pitch: pitch,
          ).catchError((Object _) {
            // A failed prefetch is retained and surfaced by the next
            // speak() without a second charged API request.
          }));
        }
        await playing;
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
        activeSpeakerId = null;
        _notify();
      }
    }
  }

  // All pause/seek/reconfiguration routes use one serialized native stop,
  // but each public navigation operation has a distinct supersession epoch.
  Future<void> _stopCurrent() async {
    _session++;
    isPlaying = false;
    activeSpeakerId = null;
    _notify();
    final priorStop = _pendingStop;
    final stopping = () async {
      try {
        await priorStop;
      } catch (_) {
        // One failed native stop does not block the next safety stop.
      }
      await _engine.stop();
    }();
    _pendingStop = stopping;
    await stopping;
  }

  Future<void> pause() async {
    if (_disposed) return;
    _navigationEpoch++;
    _resumeAfterNavigation = false;
    await _stopCurrent();
  }

  void _resumeUnawaited() {
    final running = play();
    final token = _session;
    unawaited(running.catchError((Object error, StackTrace stack) {
      if (_disposed || token != _session) return;
      lastError = error;
      _notify();
    }));
  }

  Future<void> seekTo(int index) async {
    if (_disposed) return;
    // A second seek during a pending native stop inherits the user's desire
    // to continue playing; only the MOST RECENT seek may set the position.
    final resume = isPlaying || _resumeAfterNavigation;
    final epoch = ++_navigationEpoch;
    _resumeAfterNavigation = resume;
    await _stopCurrent();
    if (_disposed || epoch != _navigationEpoch || _segments.isEmpty) return;
    _resumeAfterNavigation = false;
    currentIndex = index.clamp(0, _segments.length - 1).toInt();
    _notify();
    if (resume) _resumeUnawaited();
  }

  /// Called only when the user COMMITS a rate/pitch/language adjustment.
  /// Cancels stale prefetched audio and restarts the current source segment
  /// with updated settings; no new read position or speaker is inferred.
  Future<void> restartAfterSettingsChange() async {
    if (_disposed || !isPlaying) return;
    await seekTo(currentIndex);
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _session++;
    _navigationEpoch++;
    _resumeAfterNavigation = false;
    _disposed = true;
    unawaited(_engine.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
