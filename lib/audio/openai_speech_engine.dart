import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

import '../domain/cloud_speech_consent.dart';
import 'mp3_playback.dart';
import 'speech_audio_cache.dart';
import 'secret_vault.dart';
import 'speech_engine.dart';

/// HTTP is injected to unit-test payload, failure codes and key redaction
/// without sending any text to a live server.
abstract interface class SpeechHttpTransport {
  Future<SpeechHttpResponse> requestSpeech({
    required String apiKey,
    required String model,
    required String voice,
    required String input,
  });
  void dispose();
}

class SpeechHttpResponse {
  const SpeechHttpResponse({required this.statusCode, required this.bytes});
  final int statusCode;
  final Uint8List bytes;
}

/// The URL is fixed by design. Allowing user-defined insecure endpoints
/// would risk sending API keys or copyrighted text to unintended hosts.
/// Additional providers receive separate audited adapters.
class OpenAiSpeechHttpTransport implements SpeechHttpTransport {
  OpenAiSpeechHttpTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static final Uri endpoint =
      Uri.parse('https://api.openai.com/v1/audio/speech');

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<SpeechHttpResponse> requestSpeech({
    required String apiKey,
    required String model,
    required String voice,
    required String input,
  }) async {
    final request = http.Request('POST', endpoint);
    request.followRedirects = false; // Never forward secrets to another host.
    request.headers.addAll({
      'Authorization': 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'model': model,
      'voice': voice,
      'input': input,
      'response_format': 'mp3',
    });

    final response = await _client.send(request)
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      // Do not read or expose error bodies; they might echo book contents,
      // credentials or request information.
      return SpeechHttpResponse(
        statusCode: response.statusCode,
        bytes: Uint8List(0),
      );
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 90))) {
      if (result.length + chunk.length > 20 * 1024 * 1024) {
        throw const CloudSpeechException('Audio stream exceeds 20 MiB');
      }
      result.add(chunk);
    }
    return SpeechHttpResponse(
      statusCode: response.statusCode,
      bytes: result.takeBytes(),
    );
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class CloudSpeechException implements Exception {
  const CloudSpeechException(this.message);
  final String message;
  @override
  String toString() => 'Cloud TTS: ' + message;
}

/// An actual, optional cloud TTS engine. No calls are made at construction,
/// enumeration or voice selection time. Each speak() independently checks
/// consent, credentials and atomically reserves quota BEFORE the HTTPS call.
///
/// This speech API returns audio, not word timestamps. Model fidelity to
/// exact book text, audio duration, pitch, and character voices all require
/// separate testing. Pitch is currently NOT supported by this provider.
class _PreparedCloudClip {
  const _PreparedCloudClip({
    required this.key,
    required this.generation,
    required this.audio,
  });
  final String key;
  final int generation;
  final Future<Uint8List?> audio;
}

/// Paid audio may be prepared ONE chunk ahead, but only after a separate
/// session toggle is enabled and playback has already started. Every remote
/// render rechecks per-book permission, key and quota. No background chapters.
class OpenAiSpeechEngine implements SpeechEngine, AheadOfTimeSpeechEngine {
  OpenAiSpeechEngine({
    required this.bookId,
    required this.modelId,
    required this.access,
    required this.vault,
    SpeechHttpTransport? transport,
    SynthesizedAudioOutput? output,
    SpeechAudioCache? cache,
  })  : _transport = transport ?? OpenAiSpeechHttpTransport(),
        _output = output ?? JustAudioMp3Output(),
        _cache = cache ?? const NoSpeechAudioCache() {
    if (!supportedModels.contains(modelId)) {
      throw UnsupportedError('Unsupported OpenAI speech model: ' + modelId);
    }
  }

  static const providerId = 'openai-speech';
  static const supportedModels = {
    'gpt-4o-mini-tts',
    'gpt-4o-mini-tts-2025-12-15',
  };
  static const supportedVoices = [
    'alloy', 'ash', 'ballad', 'coral', 'echo', 'fable',
    'onyx', 'nova', 'sage', 'shimmer', 'verse', 'marin', 'cedar',
  ];

  final String bookId;
  final String modelId;
  final CloudSpeechAccess access;
  final SpeechSecretVault vault;
  final SpeechHttpTransport _transport;
  final SynthesizedAudioOutput _output;
  final SpeechAudioCache _cache;

  String _voice = 'marin';
  int _generation = 0;
  bool _disposed = false;
  _PreparedCloudClip? _prepared;

  @override
  Future<List<SpeechVoice>> listVoices() async => [
    for (final name in supportedVoices)
      SpeechVoice(name: name, locale: 'multi'),
  ];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    if (!supportedVoices.contains(voice.name)) {
      throw ArgumentError.value(voice.name, 'voice', 'Unknown OpenAI voice');
    }
    _voice = voice.name;
  }

  String _cacheKey(String voice, String text) => sha256.convert(
        utf8.encode(modelId + '\u0000' + voice + '\u0000' + text),
      ).toString();

  bool _live(int token) => !_disposed && token == _generation;

  Future<Uint8List?> _synthesize(
      String text, String voice, int token) async {
    final consent = access.getConsent(bookId, providerId);
    if (!consent.allowed) {
      throw const CloudSpeechBlocked(
        'Enable cloud narration explicitly for this book first',
      );
    }
    final key = _cacheKey(voice, text);
    final cached = await _cache.read(bookId, key);
    if (!_live(token)) return null;
    if (cached != null) return cached;
    if (consent.remainingCharacters < text.length) {
      throw const CloudSpeechBlocked(
        'Character budget exhausted for this book and provider',
      );
    }
    final apiKey = await vault.readKey(providerId);
    if (!_live(token)) return null;
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const CloudSpeechBlocked('OpenAI API key is not configured');
    }

    // This reservation happens before transmission, including prefetch.
    // An interrupted request may still be billed and is not silently retried.
    await access.reserveCharacters(bookId, providerId, text.length);
    if (!_live(token)) return null;
    final response = await _transport.requestSpeech(
      apiKey: apiKey, model: modelId, voice: voice, input: text,
    );
    if (!_live(token)) return null;
    if (response.statusCode != 200) {
      throw CloudSpeechException(
        'HTTP ' + response.statusCode.toString()
            + '. Review credentials, model and account limits.',
      );
    }
    if (response.bytes.isEmpty ||
        response.bytes.length > 20 * 1024 * 1024) {
      throw const CloudSpeechException('Empty or oversized audio response');
    }
    try {
      await _cache.write(bookId, key, response.bytes);
    } catch (_) {
      // Missing storage should not discard a paid synthesis response.
    }
    if (!_live(token)) return null;
    return response.bytes;
  }

  void _validateText(String text) {
    if (_disposed) throw StateError('Cloud speech provider is disposed');
    if (text.length > 4096) {
      throw const FormatException('Speech chunk exceeds 4096 characters');
    }
  }

  /// The next immutable voice is passed explicitly. Never change _voice
  /// during the current spoken clip just to render the next one.
  /// Errors are later surfaced by speak for the same prepared clip, rather
  /// than causing an automatic paid retry on failure.
  @override
  Future<void> prepareSpeech(
    String text, {
    required SpeechVoice? voice,
    required String language,
    required double rate,
    required double pitch,
  }) async {
    _validateText(text);
    if (text.isEmpty) return;
    final intended = voice?.name ?? _voice;
    if (!supportedVoices.contains(intended)) {
      throw const FormatException('Unsupported prefetched voice');
    }
    final token = _generation;
    final key = _cacheKey(intended, text);
    final existing = _prepared;
    if (existing != null && existing.generation == token) {
      // Bounded one ahead. Do not start more paid requests while one is
      // already retained or in flight.
      if (existing.key == key) await existing.audio;
      return;
    }
    final clip = _PreparedCloudClip(
      key: key,
      generation: token,
      audio: _synthesize(text, intended, token),
    );
    _prepared = clip;
    try {
      await clip.audio;
    } catch (_) {
      // Keep the failed clip for speak(), which surfaces the same error
      // exactly once rather than automatically paying for another request.
      rethrow;
    }
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    _validateText(text);
    if (text.isEmpty) return;
    final token = _generation;
    final voice = _voice;
    final key = _cacheKey(voice, text);
    final prepared = _prepared;
    Uint8List? audio;
    if (prepared != null &&
        prepared.key == key && prepared.generation == token) {
      try {
        audio = await prepared.audio;
      } finally {
        if (identical(_prepared, prepared)) _prepared = null;
      }
    } else {
      // Any other prepared clip remains bounded at one until consumed or
      // stopped. Normal playback does not wait for an unrelated lookahead.
      audio = await _synthesize(text, voice, token);
    }
    if (!_live(token) || audio == null) return;
    final speed = (rate / 0.5).clamp(0.5, 2.0).toDouble();
    await _output.play(audio, speed: speed);
  }

  @override
  Future<void> stop() async {
    _generation++;
    _prepared = null;
    await _output.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _prepared = null;
    await _output.dispose();
    _transport.dispose();
  }
}
