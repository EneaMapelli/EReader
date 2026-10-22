import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ereader/audio/mp3_playback.dart';
import 'package:ereader/audio/openai_speech_engine.dart';
import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/domain/cloud_speech_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeVault implements SpeechSecretVault {
  String? key;
  @override
  Future<String?> readKey(String providerId) async => key;
  @override
  Future<void> saveKey(String providerId, String value) async { key = value; }
  @override
  Future<void> deleteKey(String providerId) async { key = null; }
}

class FakeAccess implements CloudSpeechAccess {
  bool allowed = false;
  int budget = 1000;
  int used = 0;
  @override
  CloudSpeechConsent getConsent(String bookId, String providerId) =>
      CloudSpeechConsent(
        bookId: bookId,
        providerId: providerId,
        allowed: allowed,
        maxCharacters: budget,
        usedCharacters: used,
      );

  @override
  Future<void> reserveCharacters(
      String bookId, String providerId, int characters) async {
    if (!allowed || used + characters > budget) {
      throw const CloudSpeechBlocked('Quota exhausted');
    }
    used += characters;
  }
}

class FakeTransport implements SpeechHttpTransport {
  int requests = 0;
  String? receivedInput;
  String? receivedModel;
  String? receivedVoice;
  int status = 200;
  Completer<SpeechHttpResponse>? delayed;

  @override
  Future<SpeechHttpResponse> requestSpeech({
    required String apiKey,
    required String model,
    required String voice,
    required String input,
  }) async {
    requests++;
    receivedInput = input;
    receivedModel = model;
    receivedVoice = voice;
    if (delayed != null) return delayed!.future;
    return SpeechHttpResponse(
      statusCode: status,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
  }

  @override
  void dispose() {}
}

class FakeAudioOutput implements SynthesizedAudioOutput {
  int plays = 0;
  int stops = 0;
  double? lastSpeed;
  @override
  Future<void> play(Uint8List audio, {required double speed}) async {
    plays++;
    lastSpeed = speed;
  }
  @override
  Future<void> stop() async { stops++; }
  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeAccess access;
  late FakeVault vault;
  late FakeTransport transport;
  late FakeAudioOutput output;
  late OpenAiSpeechEngine engine;

  setUp(() {
    access = FakeAccess();
    vault = FakeVault()..key = 'example-test-key';
    transport = FakeTransport();
    output = FakeAudioOutput();
    engine = OpenAiSpeechEngine(
      bookId: 'book-123',
      modelId: 'gpt-4o-mini-tts',
      access: access,
      vault: vault,
      transport: transport,
      output: output,
    );
  });

  tearDown(() async { await engine.dispose(); });

  test('does not contact cloud during voice discovery or selection', () async {
    final voices = await engine.listVoices();
    expect(voices.any((voice) => voice.name == 'marin'), isTrue);
    await engine.chooseVoice(voices.first);
    expect(transport.requests, 0);
    expect(access.used, 0);
  });

  test('denies all cloud requests without per-book consent', () async {
    await expectLater(
      engine.speak('A chapter fragment', language: 'it-IT',
          rate: 0.5, pitch: 1.0),
      throwsA(isA<CloudSpeechBlocked>()),
    );
    expect(transport.requests, 0);
    expect(access.used, 0);
  });

  test('denies cloud requests if API key was removed', () async {
    access.allowed = true;
    vault.key = null;
    await expectLater(
      engine.speak('Hello', language: 'en-US', rate: 0.5, pitch: 1.0),
      throwsA(isA<CloudSpeechBlocked>()),
    );
    expect(transport.requests, 0);
    expect(access.used, 0);
  });

  test('sends a single guarded request and debits exact characters', () async {
    access.allowed = true;
    await engine.chooseVoice(
        const SpeechVoice(name: 'cedar', locale: 'multi'));
    await engine.speak('Hello', language: 'it-IT', rate: 0.75, pitch: 1.0);
    expect(transport.requests, 1);
    expect(transport.receivedInput, 'Hello');
    expect(transport.receivedVoice, 'cedar');
    expect(transport.receivedModel, 'gpt-4o-mini-tts');
    expect(access.used, 5);
    expect(output.plays, 1);
    expect(output.lastSpeed, 1.5);
  });

  test('hard budget blocks second request before API call', () async {
    access.allowed = true;
    access.budget = 5;
    await engine.speak('Hello', language: 'en-US', rate: 0.5, pitch: 1.0);
    await expectLater(
      engine.speak('Again', language: 'en-US', rate: 0.5, pitch: 1.0),
      throwsA(isA<CloudSpeechBlocked>()),
    );
    expect(transport.requests, 1);
    expect(access.used, 5);
  });

  test('HTTP failures consume conservative budget without audio playback',
      () async {
    access.allowed = true;
    transport.status = 429;
    await expectLater(
      engine.speak('Book text', language: 'en-US',
          rate: 0.5, pitch: 1.0),
      throwsA(isA<CloudSpeechException>()),
    );
    expect(access.used, 9);
    expect(transport.requests, 1);
    expect(output.plays, 0);
  });

  test('stop during pending HTTP prevents stale audio playback', () async {
    access.allowed = true;
    transport.delayed = Completer<SpeechHttpResponse>();
    final active = engine.speak('Paragraph', language: 'en-US',
        rate: 0.5, pitch: 1.0);
    // Pump microtasks while the fake vault/guard complete.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await engine.stop();
    transport.delayed!.complete(SpeechHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList([1, 2, 3]),
    ));
    await active;
    expect(output.plays, 0);
  });

  test('HTTP adapter uses fixed HTTPS host and never leaks key in JSON', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(),
          'https://api.openai.com/v1/audio/speech');
      expect(request.headers['authorization'], 'Bearer sample-key');
      expect(request.body.contains('sample-key'), isFalse);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini-tts');
      expect(body['input'], 'Book text');
      expect(body['voice'], 'marin');
      expect(body['response_format'], 'mp3');
      return http.Response.bytes([7, 8, 9], 200);
    });
    final api = OpenAiSpeechHttpTransport(client: client);
    final result = await api.requestSpeech(
      apiKey: 'sample-key',
      model: 'gpt-4o-mini-tts',
      voice: 'marin',
      input: 'Book text',
    );
    expect(result.bytes, [7, 8, 9]);
    api.dispose();
    client.close();
  });
}
