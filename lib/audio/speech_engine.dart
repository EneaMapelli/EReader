import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import 'windows_speech_punctuation.dart';

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

class SystemSpeechEngine implements SpeechEngine {
  SystemSpeechEngine({bool? interpretWindowsPunctuation})
      : _interpretWindowsPunctuation =
            interpretWindowsPunctuation ?? Platform.isWindows;

  final FlutterTts _tts = FlutterTts();
  final bool _interpretWindowsPunctuation;
  static const WindowsSpeechPunctuation _punctuation =
      WindowsSpeechPunctuation();
  SpeechVoice? _selectedVoice;
  bool _completionConfigured = false;
  int _speechEpoch = 0;
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
    for (var i = 0; i < phrases.length && epoch == _speechEpoch; i++) {
      await _tts.speak(phrases[i].text);
      if (epoch != _speechEpoch) return;
      if (i + 1 < phrases.length) {
        await _waitForPause(phrases[i].pauseAfter);
      }
    }
  }

  @override
  Future<void> stop() async {
    // Cancel a pause IMMEDIATELY so no late clause can begin speaking
    // after Stop, voice change, document seek or application shutdown.
    _speechEpoch++;
    _cancelPendingPause();
    await _tts.stop();
  }

  @override
  Future<void> dispose() => stop();
}
