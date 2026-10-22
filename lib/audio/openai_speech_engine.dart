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
class OpenAiSpeechEngine implements SpeechEngine {
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

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    if (_disposed) throw StateError('Cloud speech provider is disposed');
    if (text.isEmpty) return;
    if (text.length > 4096) {
      throw const FormatException('Speech chunk exceeds 4096 characters');
    }
    final token = _generation;
    final consent = access.getConsent(bookId, providerId);
    if (!consent.allowed) {
      throw const CloudSpeechBlocked(
        'Enable cloud narration explicitly for this book first',
      );
    }
    final cacheKey = sha256.convert(
      utf8.encode(modelId + '\u0000' + _voice + '\u0000' + text),
    ).toString();
    final cached = await _cache.read(bookId, cacheKey);
    if (token != _generation || _disposed) return;
    if (cached != null) {
      // No API request, quota consumption or key is needed on a cache hit.
      await _output.play(cached,
        speed: (rate / 0.5).clamp(0.5, 2.0).toDouble());
      return;
    }
    if (consent.remainingCharacters < text.length) {
      throw const CloudSpeechBlocked(
        'Character budget exhausted for this book and provider',
      );
    }
    final key = await vault.readKey(providerId);
    if (token != _generation || _disposed) return;
    if (key == null || key.trim().isEmpty) {
      throw const CloudSpeechBlocked('OpenAI API key is not configured');
    }

    // Reserve attempted bytes even if an HTTP error occurs. This conservative
    // local limit does NOT assert or estimate exact provider billing.
    await access.reserveCharacters(bookId, providerId, text.length);
    if (token != _generation || _disposed) return;

    final result = await _transport.requestSpeech(
      apiKey: key,
      model: modelId,
      voice: _voice,
      input: text,
    );
    if (token != _generation || _disposed) return;
    if (result.statusCode != 200) {
      // Never include response body or secrets in exceptions/logs.
      throw CloudSpeechException(
        'HTTP ' + result.statusCode.toString()
            + '. Review credentials, model and account limits.',
      );
    }
    if (result.bytes.isEmpty || result.bytes.length > 20 * 1024 * 1024) {
      throw const CloudSpeechException('Empty or oversized audio response');
    }
    // Cache errors must not throw away paid synthesis, but cache misses
    // always consume quota. Only successful HTTP audio is cached.
    try {
      await _cache.write(bookId, cacheKey, result.bytes);
    } catch (_) {
      // Can still play when storage is full or external cleanup races us.
    }
    if (token != _generation || _disposed) return;
    // rate=0.5 is nominal 1x in the system TTS reader. Cloud speed uses a
    // local playback rate when the platform backend supports it. Cloud pitch
    // is NOT claimed to work and is omitted from the API request.
    final speed = (rate / 0.5).clamp(0.5, 2.0).toDouble();
    await _output.play(result.bytes, speed: speed);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _output.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _output.dispose();
    _transport.dispose();
  }
}
