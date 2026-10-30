import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/speech_segment.dart';
import '../domain/speech_preferences.dart';
import 'speech_engine.dart';
import 'offline_voice_diagnostics.dart';

typedef SegmentStarted = Future<void> Function(SpeechSegment segment);

/// Only called once the complete native utterance has finished normally.
/// A cancelled or interrupted segment is never reported as finished.
typedef SegmentCompleted = Future<void> Function(
    SpeechSegment segment, SpeechSegment? nextAudible);

/// Injectable so the wall-clock sleep deadline can be regression-tested
/// without waiting for real minutes.
typedef SleepTimerScheduler = Timer Function(
    Duration duration, void Function() onElapsed);

/// A deadline bounds how long UI and media controls wait for native Stop,
/// NOT how long it is safe to assume the previous utterance has stopped.
class SpeechStopTimeout implements Exception {
  const SpeechStopTimeout(this.deadline);
  final Duration deadline;

  @override
  String toString() =>
      'Speech engine Stop did not confirm within '
      '${deadline.inMilliseconds} ms; narration remains locked until '
      'the native Stop completes successfully';
}

/// Serialized speech queue with session tokens to invalidate interrupted runs.
/// Pause stops the current native utterance; resume RESTARTS that segment.
/// Word-level timing and background sessions are not claimed in this milestone.
class ReaderPlayer extends ChangeNotifier {
  ReaderPlayer({
    required SpeechEngine engine,
    required List<SpeechSegment> segments,
    required this.onSegmentStarted,
    this.onSegmentCompleted,
    this.language = 'it-IT',
    this.engineProviderId = 'system',
    SleepTimerScheduler? timerScheduler,
    this.nativeStopTimeout = const Duration(seconds: 8),
    Duration dialogueTurnPause = Duration.zero,
  }) : assert(nativeStopTimeout > Duration.zero),
       assert(dialogueTurnPause >= Duration.zero),
       _dialogueTurnPause = dialogueTurnPause,
       _engine = engine,
       _segments = segments,
       _timerScheduler = timerScheduler ?? Timer.new;

  final SpeechEngine _engine;
  final List<SpeechSegment> _segments;
  final SegmentStarted onSegmentStarted;
  final SegmentCompleted? onSegmentCompleted;
  final String engineProviderId;
  final SleepTimerScheduler _timerScheduler;
  final Duration nativeStopTimeout;

  /// Optional short breath ONLY between actually audible, DIFFERENT cast
  /// voices on a system TTS engine. Zero preserves the original timing for
  /// existing callers. The UI explicitly opts in on Windows/Android system
  /// voices, not cloud or neural engines. Never change source checkpoints.
  Duration _dialogueTurnPause;
  Duration get dialogueTurnPause => _dialogueTurnPause;

  /// Reconfigure future dialogue transitions without interrupting the
  /// current spoken sentence. This updates only the local OS speech policy.
  void setDialogueTurnPause(Duration duration) {
    if (_disposed) return;
    if (duration < Duration.zero ||
        duration > const Duration(milliseconds: 2000) ||
        duration.inMicroseconds % 1000 != 0) {
      throw ArgumentError.value(duration, 'duration',
          'Dialogue turn pause must be 0–2000 whole milliseconds');
    }
    if (_dialogueTurnPause == duration) return;
    _dialogueTurnPause = duration;
    _notify();
  }

  Timer? _turnPauseTimer;
  Completer<void>? _turnPauseDone;

  Future<void> _waitForTurnBreath() {
    if (_dialogueTurnPause == Duration.zero) return Future<void>.value();
    final done = Completer<void>();
    _turnPauseDone = done;
    _turnPauseTimer = Timer(_dialogueTurnPause, () {
      if (identical(_turnPauseDone, done)) {
        _turnPauseTimer = null;
        _turnPauseDone = null;
      }
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  void _cancelTurnBreath() {
    _turnPauseTimer?.cancel();
    _turnPauseTimer = null;
    final done = _turnPauseDone;
    _turnPauseDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Timer? _sleepTimer;

  /// This is a session-only wall-clock deadline. Pausing does not extend it.
  /// It is cancelled when narration finishes or the reader is disposed.
  DateTime? sleepTimerEndsAt;

  void setSleepTimer(Duration? duration) {
    if (_disposed) return;
    if (duration != null && duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive');
    }
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerEndsAt = null;
    if (duration != null) {
      sleepTimerEndsAt = DateTime.now().add(duration);
      _sleepTimer = _timerScheduler(duration, () {
        _sleepTimer = null;
        sleepTimerEndsAt = null;
        if (_disposed) return;
        // pause() immediately invalidates the playback session before
        // awaiting native stop, so an in-flight clip cannot advance.
        unawaited(pause().catchError((Object error, StackTrace stack) {
          if (_disposed) return;
          lastError = error;
          _notify();
        }));
      });
    }
    _notify();
  }

  void cancelSleepTimer() => setSleepTimer(null);

  String language;
  double rate = 0.5;
  double pitch = 1.0;
  double volume = 1.0;

  /// Only engines explicitly implementing native loudness advertise a
  /// volume control; paid/experimental engines cannot silently ignore it.
  bool get supportsVolume => _engine is SpeechVolumeEngine;
  List<SpeechVoice> availableVoices = const [];
  SpeechVoice? selectedVoice;
  String _providerId = 'system';
  String _modelId = 'gpt-4o-mini-tts';

  /// Called immediately before TTS. Display text and reading offsets remain
  /// untouched even when pronunciation replacements change string length.
  String Function(String)? speechTextTransform;

  /// Optional, local-only, per-session source skip. The predicate is checked
  /// BEFORE the segment checkpoint, cloud prefetch and synthesis. It must
  /// never rewrite positions, text or the speaker's attributed source.
  bool Function(SpeechSegment)? shouldSkipSegment;

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

  /// This is local cache IO/decoder work only, never paid synthesis.
  /// The separate speculative HTTP toggle remains OFF by default.
  bool warmCachedCloudChunk = true;

  /// Opted-in VITS only; locally prepares one future WAV.
  bool warmNextOfflineChunk = true;

  void setOfflineWarmup(bool enabled) {
    if (engineProviderId != 'sherpa-vits') return;
    warmNextOfflineChunk = enabled;
    _notify();
  }

  void setCachedCloudWarmup(bool enabled) {
    if (engineProviderId != 'openai-speech') return;
    warmCachedCloudChunk = enabled;
    _notify();
  }

  void setCloudPrefetch(bool enabled) {
    if (engineProviderId != 'openai-speech') return;
    prefetchNextCloudChunk = enabled;
    // Disabling stops future scheduling. A previously paid lookahead may
    // still finish and be reused for the next passage, avoiding a retry.
    _notify();
  }

  /// Resolve one immutable voice/language pair per source chunk. An
  /// attribution callback may access mutable editor state, so evaluating it
  /// a second time for the language or lookahead can contradict the
  /// actually chosen installed voice. An unavailable cast voice must not
  /// silently switch the narrator's configured book language.
  ({SpeechVoice? voice, String spokenLanguage}) _resolveVoiceAndLanguage(
    SpeechSegment segment, {
    bool forPlayback = false,
  }) {
    final resolver = castVoiceForSegment;
    // Preserve the historical native selection when no cast resolver is
    // installed. Preview/lookahead still uses the available first/marin
    // fallback, exactly as earlier _voiceFor did.
    if (forPlayback && resolver == null && selectedVoice != null) {
      return (voice: selectedVoice, spokenLanguage: language);
    }
    final requestedCast = resolver?.call(segment);
    SpeechVoice? fallback = selectedVoice;
    if (fallback == null && availableVoices.isNotEmpty) {
      // An unsaved system narrator must use the book language when a
      // compatible native voice is available. Selecting alphabetically
      // could silently pronounce an English book with another locale.
      // First prefer an exact match, then the same primary language.
      if (engineProviderId == 'system' ||
          engineProviderId == 'system-native') {
        final desired = language.toLowerCase().replaceAll('_', '-');
        for (final voice in availableVoices) {
          if (voice.locale.toLowerCase().replaceAll('_', '-') == desired) {
            fallback = voice;
            break;
          }
        }
        if (fallback == null) {
          final primary = desired.split('-').first;
          for (final voice in availableVoices) {
            if (voice.locale.toLowerCase().replaceAll('_', '-')
                .split('-').first == primary) {
              fallback = voice;
              break;
            }
          }
        }
      }
      // Preserve the historical default if no matching native voice
      // exists. Cloud's marin preference is unchanged.
      fallback ??= availableVoices.first;
      if (engineProviderId == 'openai-speech') {
        for (final voice in availableVoices) {
          if (voice.name == 'marin') {
            fallback = voice;
            break;
          }
        }
      }
    }

    SpeechVoice? installedVoice(SpeechVoice? requested) {
      if (requested == null) return null;
      for (final voice in availableVoices) {
        if (voice.key == requested.key) return voice;
      }
      return null;
    }

    final cast = installedVoice(requestedCast);
    final resolved = cast ?? installedVoice(fallback);
    return (
      voice: resolved,
      spokenLanguage: cast != null && cast.locale != 'multi'
          ? cast.locale : language,
    );
  }

  /// Serialize automatically applied character/narrator voices with the
  /// user's explicit voice changes. A stale native chooseVoice() may finish
  /// after Pause/Seek, but must NEVER be mistaken for the next session's
  /// confirmed narrator choice or overlap a newer voice selection.
  Future<void> _choosePlaybackVoice(SpeechVoice voice, int token) {
    final preceding = _pendingVoiceChange;
    final changing = () async {
      try {
        await preceding;
      } catch (_) {
        // A prior failed/stale selection cannot suppress a new one.
      }
      if (_disposed || token != _session) return;
      try {
        await _engine.chooseVoice(voice);
      } catch (_) {
        _engineVoiceKey = null;
        rethrow;
      }
      if (_disposed || token != _session) {
        _engineVoiceKey = null;
        return;
      }
      _engineVoiceKey = voice.key;
    }();
    _pendingVoiceChange = changing;
    // A native voice-selection failure belongs to THIS utterance only.
    // Keep the original failed Future for the in-flight Play caller, but
    // clear the barrier for a later explicit retry. That retry reasserts
    // the narrator because the engine voice key was invalidated above.
    unawaited(changing.then<void>((_) {}, onError: (
        Object error, StackTrace stack) {
      if (identical(_pendingVoiceChange, changing)) {
        _pendingVoiceChange = Future<void>.value();
      }
    }));
    return changing;
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
      try {
        await _engine.chooseVoice(voice);
      } catch (_) {
        // The native backend may have switched voices before reporting a
        // failure. Never trust the previous cached voice identity.
        _engineVoiceKey = null;
        rethrow;
      }
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
    try {
      await changing;
    } catch (error) {
      _engineVoiceKey = null;
      if (identical(_pendingVoiceChange, changing)) {
        _pendingVoiceChange = Future<void>.value();
      }
      if (!_disposed && epoch == _navigationEpoch) {
        _resumeAfterNavigation = false;
        lastError = error;
        _notify();
      }
      rethrow;
    }
    if (_disposed || epoch != _navigationEpoch) return;
    if (shouldResume) {
      _resumeUnawaited();
    } else {
      _resumeAfterNavigation = false;
      _notify();
    }
  }

  Future<void> applyPreferences(SpeechPreferences preferences) async {
    if (_disposed) return;
    preferences.validate();
    if (preferences.providerId != engineProviderId) {
      throw UnsupportedError(
        'Speech provider does not match the active engine: '
            + preferences.providerId,
      );
    }

    // Applying a persisted book/global profile is an explicit user
    // configuration, never a request to resume playback. Supersede older
    // auto-resuming Seek and native voice changes before their awaits.
    final epoch = ++_navigationEpoch;
    _resumeAfterNavigation = false;
    if (isPlaying) await _stopCurrent();
    if (_disposed || epoch != _navigationEpoch) return;
    await _pendingStop;
    if (_disposed || epoch != _navigationEpoch) return;
    if (nativeStopUnconfirmed) {
      throw StateError('Cannot change voice before native Stop is confirmed');
    }

    SpeechVoice? restoredVoice;
    if (preferences.voiceName != null && preferences.voiceLocale != null) {
      for (final voice in availableVoices) {
        if (voice.name == preferences.voiceName &&
            voice.locale == preferences.voiceLocale) {
          restoredVoice = voice;
          break;
        }
      }
    }

    // Serialize with _choosePlaybackVoice and selectVoice. Neither the
    // previous nor a superseded book profile may apply native voice state
    // after the last selection. Commit the preferences only when the
    // winning platform choice has completed successfully.
    final previous = _pendingVoiceChange;
    final changing = () async {
      try {
        await previous;
      } catch (_) {
        // A rejected or abandoned earlier native choice cannot override
        // the latest saved preference.
      }
      if (_disposed || epoch != _navigationEpoch) return;
      if (restoredVoice != null) {
        try {
          await _engine.chooseVoice(restoredVoice);
        } catch (_) {
          _engineVoiceKey = null;
          rethrow;
        }
      }
      if (_disposed || epoch != _navigationEpoch) {
        // The old native callback may already have mutated the device.
        // Ensure the next session reasserts the winning installed voice.
        _engineVoiceKey = null;
        return;
      }
      _providerId = preferences.providerId;
      _modelId = preferences.modelId;
      language = preferences.language;
      rate = preferences.rate;
      pitch = preferences.pitch;
      if (_engine is SpeechVolumeEngine) {
        (_engine as SpeechVolumeEngine).configureVolume(preferences.volume);
      }
      volume = preferences.volume;
      selectedVoice = restoredVoice;
      _engineVoiceKey = restoredVoice?.key;
      _notify();
    }();
    _pendingVoiceChange = changing;
    try {
      await changing;
    } catch (error) {
      // Keep the last committed profile and allow a subsequent explicit
      // Play to reassert its narrator, even if native selection mutated
      // the voice before failing.
      _engineVoiceKey = null;
      if (identical(_pendingVoiceChange, changing)) {
        _pendingVoiceChange = Future<void>.value();
      }
      if (!_disposed && epoch == _navigationEpoch) {
        lastError = error;
        _notify();
      }
      rethrow;
    }
  }

  SpeechPreferences get currentPreferences => SpeechPreferences(
        providerId: _providerId,
        modelId: _modelId,
        language: language,
        rate: rate,
        pitch: pitch,
        volume: volume,
        dialogueTurnPauseMs: _dialogueTurnPause.inMilliseconds,
        voiceName: selectedVoice?.name,
        voiceLocale: selectedVoice?.locale,
      );

  void setPitch(double value) {
    pitch = value;
    _notify();
  }

  /// Changes the next native utterance; UI commits call
  /// restartAfterSettingsChange to apply it to an active segment.
  void setVolume(double value) {
    if (_disposed) return;
    if (!supportsVolume) {
      throw UnsupportedError('Active speech engine has no volume control');
    }
    if (!value.isFinite || value < 0 || value > 1) {
      throw RangeError.range(value, 0, 1, 'volume');
    }
    (_engine as SpeechVolumeEngine).configureVolume(value);
    volume = value;
    _notify();
  }

  int currentIndex = 0;
  bool isPlaying = false;
  int _session = 0;
  int _navigationEpoch = 0;

  /// Increases whenever a new direct Play, Pause, Seek, voice/profile
  /// change or source-end navigation supersedes previous control intent.
  /// The Android media handler uses this to distinguish duplicate phone
  /// events from a *new* user operation during an unfinished interruption.
  /// It exposes no content, credentials or wall-clock timing.
  int get narrationControlRevision => _navigationEpoch;
  bool _resumeAfterNavigation = false;
  int _pendingNativeStops = 0;
  int _pendingSegmentCompletions = 0;
  /// True only while the player is committing an utterance that the engine
  /// already confirmed as fully audible. A concurrent Pause may change
  /// isPlaying before that acknowledgment finishes.
  bool get isCommittingSpeechSegment => _pendingSegmentCompletions > 0;
  bool _stopUnconfirmed = false;
  bool _stopFailed = false;
  bool _disposed = false;

  /// A timeout only ends the caller's wait, not the native stop itself.
  /// Never start a second utterance while the first engine could still
  /// be speaking; any failed stop requires a new player/engine instance.
  bool get nativeStopUnconfirmed =>
      _stopUnconfirmed || _stopFailed;

  /// Unlike !isPlaying, this is true only once native stop has settled
  /// and no seek/voice switch intends to resume the current book. Audio
  /// focus and crash checkpoints must use this rather than a transient
  /// state notification emitted during a serialized seek.
  bool get isSettledIdle =>
      !_disposed && !isPlaying &&
      !_resumeAfterNavigation && _pendingNativeStops == 0 &&
      _pendingSegmentCompletions == 0 && !nativeStopUnconfirmed;
  // Keep the physical native Stop queue independent from checkpoint/durable
  // position writes: those may take longer without proving audio is unsafe.
  Future<void> _pendingNativeStop = Future<void>.value();
  Future<void> _pendingStop = Future<void>.value();
  Future<void> _pendingCompletion = Future<void>.value();
  Future<void> _pendingVoiceChange = Future<void>.value();
  Object? lastError;

  List<SpeechSegment> get segments => _segments;

  /// Local-only, read-only counters for the experimental neural engine.
  /// Every other speech engine returns null.
  OfflineVoiceStatistics? get offlineVoiceStatistics {
    final engine = _engine;
    return engine is OfflineVoiceDiagnosticsProvider
        ? (engine as OfflineVoiceDiagnosticsProvider).offlineVoiceStatistics
        : null;
  }

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
    if (nativeStopUnconfirmed) {
      throw StateError(
        'Cannot resume narration before the previous native Stop is '
        'confirmed. Close and reopen the reader if the engine failed.');
    }
    // A direct Play invalidates outstanding seeks after their awaited stop.
    _navigationEpoch++;
    _resumeAfterNavigation = false;
    if (currentIndex >= _segments.length) {
      // A natural EOF does not call native Stop. Clear only session-local
      // punctuation carry before an explicit replay; ordinary Pause/Seek
      // already cancel it through the engine's existing stop path.
      if (_engine is SpeechSessionRestartAware) {
        (_engine as SpeechSessionRestartAware).onNarrationRestart();
      }
      currentIndex = 0;
    }
    final token = ++_session;
    isPlaying = true;
    lastError = null;
    _notify();
    String? previousAudibleSpeaker;
    String? previousAudibleVoiceKey;
    var hadAudibleSegment = false;
    try {
      // A rapid pause/play must not synthesize before the old native
      // utterance has fully stopped, otherwise voices overlap.
      await _pendingStop;
      if (nativeStopUnconfirmed) {
        throw StateError('Native speech Stop could not be confirmed');
      }
      if (token != _session) return;
      // Wait out voice selection in flight before starting a new clip.
      try { await _pendingVoiceChange; } catch (_) {
        if (token == _session) rethrow;
      }
      while (token == _session && currentIndex < _segments.length) {
        final segment = _segments[currentIndex];
        if (shouldSkipSegment?.call(segment) ?? false) {
          // No TTS request, voice switch, cloud reservation or checkpoint
          // for a skipped body. Ordinary source positions remain intact.
          activeSpeakerId = null;
          currentIndex++;
          _notify();
          continue;
        }
        // Preview the resolved voice BEFORE checkpointing the new segment:
        // when Stop/Seek arrives during this small breath, the next
        // unheard segment must not be persisted as already started.
        final resolved = _resolveVoiceAndLanguage(
            segment, forPlayback: true);
        final installed = resolved.voice;
        final speaker = castSpeakerForSegment?.call(segment);
        final isNewAudibleVoiceTurn = hadAudibleSegment &&
            (speaker != previousAudibleSpeaker) &&
            (speaker != null || previousAudibleSpeaker != null) &&
            (installed?.key != previousAudibleVoiceKey) &&
            (engineProviderId == 'system' ||
                engineProviderId == 'system-native');
        final requestedBreath = isNewAudibleVoiceTurn
            ? _dialogueTurnPause : Duration.zero;
        final freeSystemVoice = engineProviderId == 'system' ||
            engineProviderId == 'system-native';
        // The last utterance is finished, so selecting the next native
        // voice may safely overlap the *silent* punctuation/cast breath.
        // Await BOTH before reporting the next source checkpoint: their
        // durations must not stack just because the platform voice switch
        // is slow. Future.wait uses eagerError=false (default), ensuring
        // neither in-flight native operation is left unobserved if one
        // fails. Pause/Seek/Dispose invalidate token and cancel the breath.
        final preparation = <Future<void>>[];
        if (freeSystemVoice && _engine is PreSegmentSpeechPause) {
          preparation.add((_engine as PreSegmentSpeechPause)
              .waitBeforeSegment(voiceTurnPause: requestedBreath));
        } else if (requestedBreath > Duration.zero) {
          // Compatibility with external/mock system engines which have
          // no punctuation-tail coordination hook.
          preparation.add(_waitForTurnBreath());
        }
        if (installed != null && installed.key != _engineVoiceKey) {
          preparation.add(_choosePlaybackVoice(installed, token));
        }
        if (preparation.isNotEmpty) {
          await Future.wait(preparation);
        }
        if (token != _session) return;
        await onSegmentStarted(segment);
        if (token != _session) return;
        final spokenLanguage = resolved.spokenLanguage;
        activeSpeakerId = speaker;
        _notify();
        final spokenText =
            speechTextTransform?.call(segment.text) ?? segment.text;
        final playing = _engine.speak(spokenText,
            language: spokenLanguage, rate: rate, pitch: pitch);
        // Only the NEXT actually audible chunk is eligible. Skippable
        // EPUB footnotes may contain several silent segments in a row;
        // neither private cache warming nor paid prefetch should preload
        // those silent chunks or interrupt the eventual narrator/actor.
        final canCloudWarm =
            engineProviderId == 'openai-speech' &&
            (prefetchNextCloudChunk || warmCachedCloudChunk);
        final canOfflineWarm =
            engineProviderId == 'sherpa-vits' && warmNextOfflineChunk &&
            _engine is OfflineAheadSpeechEngine;
        if (canCloudWarm || canOfflineWarm) {
          // The current utterance is ALREADY live. Any synchronous error
          // while inspecting optional lookahead (a pronunciation transform,
          // speaker resolver or note-skip predicate) must not abort its
          // completion Future and leave native audio running after Play
          // reports an error. A failed preview is retried as normal speech
          // only when its actual turn arrives.
          try {
            // Only the next actually audible passage may be prepared.
            var nextIndex = currentIndex + 1;
            while (nextIndex < _segments.length &&
                (shouldSkipSegment?.call(_segments[nextIndex]) ?? false)) {
              nextIndex++;
            }
            if (nextIndex < _segments.length) {
              final next = _segments[nextIndex];
              final nextText =
                  speechTextTransform?.call(next.text) ?? next.text;
              final nextResolved = _resolveVoiceAndLanguage(next);
              final nextVoice = nextResolved.voice;
              final nextLanguage = nextResolved.spokenLanguage;
              if (canOfflineWarm) {
                final offline = _engine as OfflineAheadSpeechEngine;
                unawaited(offline.prepareOfflineSpeech(
                  nextText, voice: nextVoice,
                  language: nextLanguage, rate: rate, pitch: pitch,
                ).catchError((Object _) {
                  // Local warming is optional, and cannot mask playback errors.
                }));
              } else if (prefetchNextCloudChunk &&
                  _engine is AheadOfTimeSpeechEngine) {
                final cloud = _engine as AheadOfTimeSpeechEngine;
                unawaited(cloud.prepareSpeech(
                  nextText, voice: nextVoice,
                  language: nextLanguage, rate: rate, pitch: pitch,
                ).catchError((Object _) {
                  // Paid prefetch errors surface when that clip is played.
                }));
              } else if (warmCachedCloudChunk &&
                  _engine is CachedAheadSpeechEngine) {
                final cloud = _engine as CachedAheadSpeechEngine;
                unawaited(cloud.prepareCachedSpeech(
                  nextText, voice: nextVoice,
                  language: nextLanguage, rate: rate, pitch: pitch,
                ).catchError((Object _) {
                  // Cache warming never synthesizes on a miss.
                }));
              }
            }
          } catch (_) {
            // Optional lookahead cannot change the audible source cursor,
            // crash checkpoint, current speaker or already-started clip.
            // In particular, never trigger a paid cloud retry here.
          }
        }
        await playing;
        if (token != _session) return;
        // Commit the next AUDIBLE source anchor only after native playback
        // really finishes. On interruption/cancellation, retaining this
        // segment's starting anchor is safer than skipping unheard audio.
        // The skipped-note predicate is source-only and never reorders text.
        if (onSegmentCompleted != null) {
          var nextIndex = currentIndex + 1;
          while (nextIndex < _segments.length &&
              (shouldSkipSegment?.call(_segments[nextIndex]) ?? false)) {
            nextIndex++;
          }
          final completedIndex = currentIndex;
          // Audio has FINISHED: this acknowledgment is not cancellable by
          // Pause. A paused player must resume at the next segment rather
          // than replaying speech already heard in full. Seek/voice changes
          // wait for this barrier before changing the cursor or resuming.
          _pendingSegmentCompletions++;
          final completion = () async {
            await onSegmentCompleted!(
              segment,
              nextIndex < _segments.length ? _segments[nextIndex] : null,
            );
            if (!_disposed && currentIndex == completedIndex) {
              currentIndex = completedIndex + 1;
              _notify();
            }
          }();
          _pendingCompletion = completion;
          try {
            await completion;
          } finally {
            _pendingSegmentCompletions--;
            _notify();
          }
          if (token != _session) return;
        } else {
          currentIndex++;
        }
        previousAudibleSpeaker = speaker;
        previousAudibleVoiceKey = installed?.key;
        hadAudibleSegment = true;
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
        // Avoid an obsolete deadline stopping a later manual replay.
        if (currentIndex >= _segments.length || lastError != null) {
          _sleepTimer?.cancel();
          _sleepTimer = null;
          sleepTimerEndsAt = null;
        }
        _notify();
      }
    }
  }

  // All pause/seek/reconfiguration routes use one serialized native stop,
  // but each public navigation operation has a distinct supersession epoch.
  Future<void> _stopCurrent() async {
    _session++;
    // Unblock a pending narrator/character breath synchronously so Stop
    // cannot leave an older Play task waiting to start stale audio.
    _cancelTurnBreath();
    isPlaying = false;
    activeSpeakerId = null;

    // An existing unconfirmed stop cannot safely be overwritten or
    // bypassed. The platform might still be outputting the old utterance.
    if (nativeStopUnconfirmed) {
      _notify();
      throw StateError('Native speech Stop is still unconfirmed');
    }

    // Mark the stop as pending BEFORE notifying media focus and checkpoint
    // listeners. Otherwise they observe a transient isSettledIdle=true
    // and release focus/erase recovery while native speech still plays.
    _pendingNativeStops++;
    _notify();
    final priorNativeStop = _pendingNativeStop;
    final priorSettled = _pendingStop;
    final stopping = () async {
      try {
        await priorNativeStop;
      } catch (_) {
        // A failed native Stop is tracked separately by _stopFailed.
      }
      if (_stopFailed) {
        throw StateError('An earlier native speech Stop failed');
      }
      await _engine.stop();
    }();
    _pendingNativeStop = stopping;
    // A second Pause/Seek may arrive while the first completed segment
    // waits for its SQLite checkpoint. Native Stops must queue behind only
    // other native Stops, not behind a slow database acknowledgement.
    // The full settled chain still fences every older acknowledgement
    // before a new Play/Seek is allowed to advance source position.
    final settled = () async {
      try {
        await priorSettled;
      } catch (_) {
        // The previous command reports its own native Stop failure.
      }
      try {
        await stopping;
      } catch (_) {
        // The original Stop Future and timeout below report the failure.
      }
      try {
        await _pendingCompletion;
      } catch (_) {
        // A rejected checkpoint leaves the cursor at its previous
        // safe replay position; it must not poison future native Stops.
      }
    }();
    _pendingStop = settled;

    // Observe the ORIGINAL future, not only Future.timeout: the real
    // platform callback may complete after the caller has timed out.
    // Keep the unsafe flag until that late completion is confirmed.
    unawaited(stopping.then((_) {
      _pendingNativeStops--;
      if (_pendingNativeStops == 0) _stopUnconfirmed = false;
      _notify();
    }, onError: (Object error, StackTrace stack) {
      _pendingNativeStops--;
      _stopFailed = true;
      _stopUnconfirmed = true;
      if (!_disposed) lastError = error;
      _notify();
    }));

    try {
      await stopping.timeout(nativeStopTimeout);
    } on TimeoutException {
      _stopUnconfirmed = true;
      // A queued Play/Seek/voice change must never restart merely because
      // the native callback eventually arrives after a timed-out Stop.
      _session++;
      _navigationEpoch++;
      _resumeAfterNavigation = false;
      isPlaying = false;
      activeSpeakerId = null;
      final failure = SpeechStopTimeout(nativeStopTimeout);
      lastError = failure;
      _notify();
      throw failure;
    } catch (error) {
      _stopFailed = true;
      _stopUnconfirmed = true;
      _navigationEpoch++;
      _resumeAfterNavigation = false;
      lastError = error;
      _notify();
      rethrow;
    }
    // Checkpoint callbacks may themselves throw TimeoutException. They
    // are not evidence of an unsafe native Stop and must never put the
    // TTS engine in the permanent native-stop recovery lock.
    await settled;
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
    currentIndex = index.clamp(0, _segments.length - 1).toInt();
    if (resume) {
      // play() synchronously transitions to playing before its first await.
      // Do not publish an artificial idle interval that would release focus
      // or erase crash recovery while navigation is resuming.
      _resumeUnawaited();
    } else {
      _resumeAfterNavigation = false;
      _notify();
    }
  }

  /// Explicitly navigate to a silent trailing source section or speech EOF.
  /// This is NOT Play: it never starts a new utterance and cannot resume a
  /// previous auto-seek after the native Stop. The visual reader separately
  /// persists the exact text/source location in its original document.
  Future<void> seekToSourceEnd() async {
    if (_disposed) return;
    final epoch = ++_navigationEpoch;
    _resumeAfterNavigation = false;
    await _stopCurrent();
    if (_disposed || epoch != _navigationEpoch) return;
    currentIndex = _segments.length;
    _notify();
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
    if (_disposed) return;
    _session++;
    _navigationEpoch++;
    _resumeAfterNavigation = false;
    _cancelTurnBreath();
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerEndsAt = null;
    _disposed = true;
    unawaited(_engine.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
