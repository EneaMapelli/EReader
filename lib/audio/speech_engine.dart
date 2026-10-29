import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import 'windows_speech_punctuation.dart';
import 'offline_voice_diagnostics.dart';

class SpeechVoice {
  const SpeechVoice({required this.name, required this.locale});
  final String name;
  final String locale;
  String get key => '$name@@$locale';
  @override
  String toString() => '$name ($locale)';
}

/// Minimal speech abstraction; cloud providers in M3 expose dynamic capabilities.
abstract interface class SpeechEngine {
  Future<List<SpeechVoice>> listVoices();
  Future<void> chooseVoice(SpeechVoice voice);
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  });
  Future<void> stop();
  Future<void> dispose();
}

/// Optional native loudness capability. configureVolume only updates
/// local configuration; the engine must apply it before starting the next
/// utterance, inside its usual serialized/cancellable speech path. This
/// prevents asynchronous volume calls racing Stop or native voice changes.
/// Unsupported engines (cloud / offline VITS) intentionally do not expose
/// the interface, rather than showing a misleading working volume slider.
abstract interface class SpeechVolumeEngine {
  void configureVolume(double volume);
}

/// Optional system-only, cancellation-aware gap before the next speech
/// segment starts. Called BEFORE ReaderPlayer creates a recovery checkpoint
/// or highlights the next segment. Merge voice changes with trailing
/// punctuation instead of adding two separate pauses.
abstract interface class PreSegmentSpeechPause {
  Future<void> waitBeforeSegment({required Duration voiceTurnPause});
}

/// Reset temporary prosody only when the book restarts after *natural EOF*.
/// Ordinary Pause/Seek already call Stop and must not need this hook.
/// The engine must not initiate synthesis, native Stop, or network access.
abstract interface class SpeechSessionRestartAware {
  void onNarrationRestart();
}

/// Optional ability to synthesize ONE future cloud chunk without playing it.
/// This is never called for a native OS voice. Preparing a cache miss may
/// transmit book text and debit the user's existing cloud-character budget.
/// The caller must obtain a separate, explicit session opt-in first.
abstract interface class AheadOfTimeSpeechEngine {
  Future<void> prepareSpeech(
    String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  });
}

/// Optional local-only lookahead for ALREADY cached cloud audio.
/// This method must never authenticate, transmit text, reserve quota or
/// synthesize an uncached clip. It merely warms a private native decoder
/// if the exact voice/model/text MP3 has previously been generated.
abstract interface class CachedAheadSpeechEngine {
  Future<void> prepareCachedSpeech(
    String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  });
}

/// Optional one-chunk, local neural lookahead: no text leaves the device.
/// All work and any private WAV must be invalidated by Stop/Seek/Dispose.
abstract interface class OfflineAheadSpeechEngine {
  Future<void> prepareOfflineSpeech(
    String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  });
}

/// Read-only, local per-engine performance information. The caller never
/// gets access to private TTS source chunks or WAV file names.
abstract interface class OfflineVoiceDiagnosticsProvider {
  OfflineVoiceStatistics get offlineVoiceStatistics;
}

class SystemSpeechEngine
    implements SpeechEngine, SpeechSessionRestartAware,
        PreSegmentSpeechPause, SpeechVolumeEngine {
  SystemSpeechEngine({bool? interpretWindowsPunctuation})
      : _interpretWindowsPunctuation =
            interpretWindowsPunctuation ?? Platform.isWindows;

  final FlutterTts _tts = FlutterTts();
  final bool _interpretWindowsPunctuation;
  static const WindowsSpeechPunctuation _punctuation =
      WindowsSpeechPunctuation();
  final WindowsSpeechPauseCarry _punctuationTail =
      WindowsSpeechPauseCarry();
  SpeechVoice? _selectedVoice;
  double _volume = 1.0;
  bool _completionConfigured = false;
  int _speechEpoch = 0;
  bool _pausePreparedForNextSpeak = false;
  Timer? _pendingPauseTimer;
  Completer<void>? _pendingPause;

  Future<void> _waitForPause(Duration duration) {
    if (duration <= Duration.zero) return Future<void>.value();
    final done = Completer<void>();
    _pendingPause = done;
    _pendingPauseTimer = Timer(duration, () {
      if (identical(_pendingPause, done)) {
        _pendingPause = null;
        _pendingPauseTimer = null;
      }
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  void _cancelPendingPause() {
    _pendingPauseTimer?.cancel();
    _pendingPauseTimer = null;
    final waiting = _pendingPause;
    _pendingPause = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  @override
  Future<void> waitBeforeSegment({required Duration voiceTurnPause}) async {
    // Only the Windows interpreted-punctuation adapter has a carried
    // terminal punctuation breath. Native punctuation/Android only need
    // the user-configured speaker-change breath.
    final duration = _interpretWindowsPunctuation
        ? _punctuationTail.takeForTurn(voiceTurnPause)
        : voiceTurnPause;
    final epoch = _speechEpoch;
    await _waitForPause(duration);
    if (epoch == _speechEpoch) {
      _pausePreparedForNextSpeak = true;
    }
  }

  @override
  void onNarrationRestart() {
    // An explicitly repeated book must not inherit the last punctuation
    // breath from its *previous* complete narration session.
    _punctuationTail.clear();
    _pausePreparedForNextSpeak = false;
  }

  @override
  void configureVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw RangeError.range(volume, 0, 1, 'volume');
    }
    _volume = volume;
  }

  Future<void> _prepare() async {
    if (!_completionConfigured) {
      await _tts.awaitSpeakCompletion(true);
      _completionConfigured = true;
    }
  }

  @override
  Future<List<SpeechVoice>> listVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    final result = <SpeechVoice>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString();
      final locale = item['locale']?.toString();
      if (name == null || name.isEmpty || locale == null || locale.isEmpty) {
        continue;
      }
      result.add(SpeechVoice(name: name, locale: locale));
    }
    result.sort((a, b) => a.toString().compareTo(b.toString()));
    return result;
  }

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    _selectedVoice = voice;
    await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    // ReaderPlayer has already waited for the merged punctuation/speaker
    // breath BEFORE announcing a source checkpoint. Direct engine callers
    // still receive the legacy inter-segment punctuation wait below.
    final pausePrepared = _pausePreparedForNextSpeak;
    _pausePreparedForNextSpeak = false;
    final epoch = ++_speechEpoch;
    _cancelPendingPause();
    await _prepare();
    if (epoch != _speechEpoch) return;
    await _tts.setLanguage(language);
    if (epoch != _speechEpoch) return;
    if (_selectedVoice != null) {
      await _tts.setVoice({
        'name': _selectedVoice!.name,
        'locale': _selectedVoice!.locale,
      });
      if (epoch != _speechEpoch) return;
    }
    await _tts.setSpeechRate(rate);
    if (epoch != _speechEpoch) return;
    await _tts.setPitch(pitch);
    if (epoch != _speechEpoch) return;
    // Apply once per utterance, after native voice/pitch selection and
    // before any text is spoken. A Stop during the platform call cancels
    // this epoch, preventing late audio from being started.
    await _tts.setVolume(_volume);
    if (epoch != _speechEpoch) return;

    if (!_interpretWindowsPunctuation) {
      // Android's TTS adapter already handles natural prosody, and cloud
      // / VITS providers have separate speech input implementations.
      await _tts.speak(text);
      return;
    }

    // On Windows, don't pass standalone quote/punctuation glyphs to
    // voices which speak their NAMES literally. Speak actual text spans
    // and model punctuation by short, cancellable pauses instead.
    // This remains ONE ReaderPlayer segment and ONE recovery checkpoint.
    final phrases = _punctuation.plan(text);
    // The final punctuation pause of a previous segment was not applied
    // inside that previous speak() call: carry it to the next ACTUAL clip.
    // This also preserves dialogue-tag phrasing when the quote and its
    // narrator incise were split into separate source-accurate chunks.
    final priorPause = pausePrepared
        ? Duration.zero : _punctuationTail.take();
    if (phrases.isNotEmpty && priorPause > Duration.zero) {
      await _waitForPause(priorPause);
      if (epoch != _speechEpoch) return;
    }
    for (var i = 0; i < phrases.length && epoch == _speechEpoch; i++) {
      await _tts.speak(phrases[i].text);
      if (epoch != _speechEpoch) return;
      if (i + 1 < phrases.length) {
        await _waitForPause(phrases[i].pauseAfter);
      }
    }
    if (epoch == _speechEpoch) {
      _punctuationTail.recordCompleted(phrases);
    }
  }

  @override
  Future<void> stop() async {
    // Cancel a pause IMMEDIATELY so no late clause can begin speaking
    // after Stop, voice change, document seek or application shutdown.
    _speechEpoch++;
    _punctuationTail.clear();
    _pausePreparedForNextSpeak = false;
    _cancelPendingPause();
    await _tts.stop();
  }

  @override
  Future<void> dispose() => stop();
}
