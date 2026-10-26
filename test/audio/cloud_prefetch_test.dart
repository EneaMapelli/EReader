import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:ereader/audio/mp3_playback.dart';
import 'package:ereader/audio/openai_speech_engine.dart';
import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/audio/speech_audio_cache.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/cloud_speech_consent.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class _Meter implements CloudSpeechAccess {
  bool allowed = true;
  int max = 1000;
  int used = 0;
  @override
  CloudSpeechConsent getConsent(String bookId, String providerId) =>
      CloudSpeechConsent(
        bookId: bookId, providerId: providerId,
        allowed: allowed, maxCharacters: max, usedCharacters: used,
      );
  @override
  Future<void> reserveCharacters(
      String bookId, String providerId, int count) async {
    if (!allowed || used + count > max) {
      throw const CloudSpeechBlocked('Not authorized');
    }
    used += count;
  }
}

class _Vault implements SpeechSecretVault {
  @override
  Future<String?> readKey(String providerId) async => 'fake';
  @override
  Future<void> saveKey(String providerId, String key) async {}
  @override
  Future<void> deleteKey(String providerId) async {}
}

class _Http implements SpeechHttpTransport {
  final requests = <({String text, String voice})>[];
  final pending = <Completer<SpeechHttpResponse>>[];
  @override
  Future<SpeechHttpResponse> requestSpeech({
    required String apiKey, required String model,
    required String voice, required String input,
  }) {
    requests.add((text: input, voice: voice));
    final gate = Completer<SpeechHttpResponse>();
    pending.add(gate);
    return gate.future;
  }

  void complete(int index, {int status = 200}) {
    pending[index].complete(SpeechHttpResponse(
      statusCode: status,
      bytes: Uint8List.fromList([index + 1, 10, 20]),
    ));
  }
  @override
  void dispose() {}
}

class _Output implements PreloadableSynthesizedAudioOutput {
  final clips = <Uint8List>[];
  final warmed = <Uint8List>[];
  final warmSpeeds = <double>[];
  final awaiting = <Completer<void>>[];
  @override
  Future<void> prepareNext(Uint8List bytes, {required double speed}) async {
    warmed.add(bytes);
    warmSpeeds.add(speed);
  }
  @override
  Future<void> play(Uint8List bytes, {required double speed}) {
    clips.add(bytes);
    final gate = Completer<void>();
    awaiting.add(gate);
    return gate.future;
  }

  void finish(int index) {
    if (!awaiting[index].isCompleted) awaiting[index].complete();
  }

  @override
  Future<void> stop() async {
    for (final gate in awaiting) {
      if (!gate.isCompleted) gate.complete();
    }
  }
  @override
  Future<void> dispose() => stop();
}

class _Cache implements SpeechAudioCache {
  final items = <String, Uint8List>{};
  final reads = <String>[];
  final readGates = <String, Completer<void>>{};
  @override
  Future<Uint8List?> read(String book, String key) async {
    reads.add(key);
    final gate = readGates[key];
    if (gate != null) await gate.future;
    return items[book + ':' + key];
  }
  @override
  Future<void> write(String book, String key, Uint8List bytes) async {
    items[book + ':' + key] = bytes;
  }
  @override
  Future<void> clearBook(String book) async {
    items.removeWhere((key, _) => key.startsWith(book + ':'));
  }
  @override
  Future<void> clearAll() async => items.clear();
}

String _keyFor(String text, {String voice = 'marin'}) =>
    sha256.convert(
      utf8.encode('gpt-4o-mini-tts\u0000$voice\u0000$text'),
    ).toString();

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 60; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected asynchronous audio event was not reached');
}

void main() {
  late _Meter meter;
  late _Http http;
  late _Output output;
  late _Cache cache;
  late OpenAiSpeechEngine engine;
  late ReaderPlayer player;

  setUp(() async {
    meter = _Meter();
    http = _Http();
    output = _Output();
    cache = _Cache();
    engine = OpenAiSpeechEngine(
      bookId: 'book', modelId: 'gpt-4o-mini-tts',
      access: meter, vault: _Vault(), transport: http,
      output: output, cache: cache,
    );
    player = ReaderPlayer(
      engine: engine, engineProviderId: OpenAiSpeechEngine.providerId,
      segments: const [
        SpeechSegment(0, 5, 'Alpha'),
        SpeechSegment(6, 10, 'Beta'),
        SpeechSegment(11, 16, 'Gamma'),
      ],
      onSegmentStarted: (_) async {},
    );
    await player.loadVoices();
    await player.applyPreferences(const SpeechPreferences(
      providerId: OpenAiSpeechEngine.providerId,
      voiceName: 'marin', voiceLocale: 'multi',
    ));
  });

  tearDown(() async {
    await player.pause();
    player.dispose();
  });

  test('cloud prebuffer defaults OFF, so only active audio is billed', () async {
    expect(player.prefetchNextCloudChunk, isFalse);
    final playback = player.play();
    await _until(() => http.requests.isNotEmpty);
    expect(http.requests.map((r) => r.text), ['Alpha']);
    http.complete(0);
    await _until(() => output.clips.isNotEmpty);
    expect(http.requests, hasLength(1),
        reason: 'No speculative paid request is allowed by default');
    expect(meter.used, 5);
    await player.pause();
    await playback;
  });

  test('cache-only next MP3 warms without any extra HTTPS or quota',
      () async {
    cache.items['book:${_keyFor('Beta')}'] =
        Uint8List.fromList([91, 92, 93]);
    expect(player.prefetchNextCloudChunk, isFalse);
    expect(player.warmCachedCloudChunk, isTrue);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.clips.length == 1);
    await _until(() => output.warmed.length == 1);
    expect(output.warmed.single, [91, 92, 93]);
    expect(output.warmSpeeds, [1.0]);
    expect(http.requests.map((req) => req.text), ['Alpha']);
    expect(meter.used, 5, reason: 'Cached lookahead is entirely local');
    output.finish(0);
    await _until(() => output.clips.length == 2);
    expect(output.clips.last, [91, 92, 93]);
    expect(http.requests, hasLength(1));
    await _until(() => player.currentIndex == 1);
    output.finish(1);
    await _until(() => http.requests.length == 2);
    expect(http.requests.last.text, 'Gamma',
        reason: 'Cache miss is rendered ONLY when its turn arrives');
    http.complete(1);
    await _until(() => output.clips.length == 3);
    output.finish(2);
    await playback;
    expect(http.requests.map((r) => r.text), ['Alpha', 'Gamma']);
    expect(meter.used, 10);
  });

  test('disabled local warming never prepares cached future decoder',
      () async {
    cache.items['book:${_keyFor('Beta')}'] = Uint8List.fromList([61]);
    player.setCachedCloudWarmup(false);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.clips.length == 1);
    await Future<void>.delayed(Duration.zero);
    expect(output.warmed, isEmpty);
    output.finish(0);
    await _until(() => output.clips.length == 2);
    expect(output.clips.last, [61],
        reason: 'Normal speech still reuses the cached MP3');
    expect(http.requests, hasLength(1));
    await player.pause();
    await playback;
  });

  test('cached warming chooses the next character voice without HTTP',
      () async {
    cache.items['book:${_keyFor('Beta', voice: 'cedar')}'] =
        Uint8List.fromList([71, 72]);
    player.castVoiceForSegment = (segment) => segment.start == 6
        ? const SpeechVoice(name: 'cedar', locale: 'multi')
        : const SpeechVoice(name: 'marin', locale: 'multi');
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.warmed.length == 1);
    expect(output.warmed.single, [71, 72]);
    expect(http.requests, hasLength(1));
    expect(http.requests.single.voice, 'marin');
    output.finish(0);
    await _until(() => output.clips.length == 2);
    expect(output.clips.last, [71, 72]);
    await player.pause();
    await playback;
  });

  test('cached warming searches past consecutive skipped note segments',
      () async {
    cache.items['book:${_keyFor('Gamma')}'] =
        Uint8List.fromList([81, 82]);
    player.shouldSkipSegment = (segment) => segment.start == 6;
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.warmed.length == 1);
    expect(output.warmed.single, [81, 82]);
    expect(http.requests.map((req) => req.text), ['Alpha']);
    output.finish(0);
    await _until(() => output.clips.length == 2);
    expect(output.clips.last, [81, 82]);
    output.finish(1);
    await playback;
    expect(player.currentIndex, 3);
    expect(meter.used, 5, reason: 'No Beta synthesis or quota');
    expect(http.requests.map((req) => req.text), ['Alpha']);
  });

  test('paid one-ahead also skips silent notes but charges next audible',
      () async {
    player.shouldSkipSegment = (segment) => segment.start == 6;
    player.setCloudPrefetch(true);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => http.requests.length == 2);
    expect(http.requests.map((req) => req.text), ['Alpha', 'Gamma']);
    expect(meter.used, 10);
    http.complete(1);
    await _until(() => output.warmed.length == 1);
    output.finish(0);
    await _until(() => output.clips.length == 2);
    output.finish(1);
    await playback;
    expect(player.currentIndex, 3);
  });

  test('revoked consent blocks a locally warmed MP3 before playback',
      () async {
    cache.items['book:${_keyFor('Beta')}'] =
        Uint8List.fromList([91, 92]);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.warmed.length == 1);
    meter.allowed = false;
    output.finish(0);
    await expectLater(playback, throwsA(isA<CloudSpeechBlocked>()));
    expect(output.clips.length, 1);
    expect(http.requests.map((req) => req.text), ['Alpha']);
    expect(meter.used, 5);
  });

  test('stopped playback never auto-plays previously cached warmup',
      () async {
    cache.items['book:${_keyFor('Beta')}'] =
        Uint8List.fromList([92]);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.warmed.length == 1);
    await player.pause();
    await playback;
    expect(output.clips.length, 1);
    expect(player.currentIndex, 0);
    expect(http.requests.map((req) => req.text), ['Alpha']);
  });

  test('Stop invalidates cache read before it may warm a decoder',
      () async {
    final key = _keyFor('Beta');
    cache.items['book:$key'] = Uint8List.fromList([12, 34]);
    cache.readGates[key] = Completer<void>();
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => output.clips.length == 1);
    await _until(() => cache.reads.contains(key));
    await player.pause();
    await playback;
    cache.readGates[key]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(output.warmed, isEmpty);
    expect(output.clips.length, 1);
    expect(http.requests.map((r) => r.text), ['Alpha']);
    expect(meter.used, 5);
  });

  test('opted-in prefetch waits until current audio is ready', () async {
    player.setCloudPrefetch(true);
    final playback = player.play();
    await _until(() => http.requests.isNotEmpty);
    expect(http.requests, hasLength(1),
        reason: 'Failed or unrendered active audio cannot trigger lookahead');
    http.complete(0);
    await _until(() => output.clips.isNotEmpty);
    await _until(() => http.requests.length == 2);
    expect(http.requests[1].text, 'Beta');
    expect(meter.used, 9);
    http.complete(1);
    await _until(() => output.warmed.length == 1);
    expect(output.warmSpeeds, [1.0]);
    expect(output.warmed.single, [2, 10, 20]);
    expect(output.clips, hasLength(1),
        reason: 'Prebuffer must not play audio ahead of the active segment');
    output.finish(0);
    await _until(() => output.clips.length == 2);
    expect(player.currentIndex, 1);
    // With Beta now playing, Gamma is legitimately the next lookahead.
    // One request per distinct chunk, not a hard two-request ceiling.
    await _until(() => http.requests.length == 3);
    expect(http.requests.map((request) => request.text),
        ['Alpha', 'Beta', 'Gamma']);
    expect(meter.used, 14);
    expect(output.clips, hasLength(2),
        reason: 'A third paid synthesis must never auto-play over Beta');
    http.complete(2);
    await _until(() => output.warmed.length == 2);
    output.finish(1);
    await _until(() => output.clips.length == 3);
    expect(http.requests, hasLength(3),
        reason: 'Neither Beta nor Gamma may be billed a second time');
    output.finish(2);
    await playback;
    expect(player.currentIndex, 3);
  });

  test('prefetch snapshots the NEXT character voice without switching now',
      () async {
    player.setCloudPrefetch(true);
    player.castVoiceForSegment = (segment) => segment.start == 6
        ? const SpeechVoice(name: 'cedar', locale: 'multi')
        : const SpeechVoice(name: 'marin', locale: 'multi');
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    expect(http.requests.first.voice, 'marin');
    http.complete(0);
    await _until(() => http.requests.length == 2);
    expect(http.requests[1].voice, 'cedar');
    output.finish(0);
    http.complete(1);
    await _until(() => output.clips.length == 2);
    await _until(() => http.requests.length == 3);
    expect(http.requests.map((request) => request.text),
        ['Alpha', 'Beta', 'Gamma']);
    expect(http.requests.map((request) => request.voice),
        ['marin', 'cedar', 'marin'],
        reason: 'The narrator returns after the assigned character');
    expect(output.clips, hasLength(2),
        reason: 'The next narrator clip is synthesized, not yet played');
    http.complete(2);
    await player.pause();
    await playback;
  });

  test('failed prefetch surfaces once at the next segment, no paid retry',
      () async {
    player.setCloudPrefetch(true);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => http.requests.length == 2);
    http.complete(1, status: 429);
    // The current audio finishes normally; next segment throws the
    // retained error rather than reserving the same text a second time.
    output.finish(0);
    await expectLater(playback, throwsA(isA<CloudSpeechException>()));
    expect(http.requests.length, 2);
    expect(meter.used, 9);
    expect(player.currentIndex, 1);
  });

  test('revoking per-book consent prevents prepared clip playback',
      () async {
    player.setCloudPrefetch(true);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => http.requests.length == 2);
    http.complete(1);
    await _until(() => output.clips.length == 1);
    meter.allowed = false;
    output.finish(0);
    await expectLater(playback, throwsA(isA<CloudSpeechBlocked>()));
    expect(output.clips.length, 1);
    expect(http.requests.length, 2);
  });

  test('pause and seek do not play discarded prebuffer after stop',
      () async {
    player.setCloudPrefetch(true);
    final first = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0);
    await _until(() => http.requests.length == 2);
    await player.pause();
    await first;
    http.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(output.clips.length, 1,
        reason: 'Old next chunk cannot auto-play after session invalidation');
    expect(player.currentIndex, 0);
    player.setCloudPrefetch(false);
    await player.seekTo(2);
    final playback = player.play();
    await _until(() => http.requests.length >= 3);
    expect(http.requests.last.text, 'Gamma');
    http.complete(2);
    await _until(() => output.clips.length == 2);
    output.finish(1);
    await playback;
    expect(player.currentIndex, 3);
  });

  test('Stop releases pending lookahead before blocked HTTP responds',
      () async {
    final active = engine.speak(
      'Alpha', language: 'en-US', rate: 0.5, pitch: 1,
    );
    await _until(() => http.requests.length == 1);
    final future = engine.prepareSpeech(
      'Beta',
      voice: const SpeechVoice(name: 'marin', locale: 'multi'),
      language: 'en-US',
      rate: 0.5,
      pitch: 1,
    );

    await engine.stop();
    // The FIRST paid HTTP request remains deliberately unresolved.
    // Waiting for that network response to release lookahead would
    // retain a cancelled task (and potentially hold the next session).
    await future.timeout(const Duration(seconds: 1));
    expect(http.pending[0].isCompleted, isFalse);
    expect(http.requests.map((request) => request.text), ['Alpha']);
    expect(meter.used, 5);
    expect(output.warmed, isEmpty);

    http.complete(0);
    await active;
    expect(output.clips, isEmpty);
    expect(http.requests, hasLength(1),
        reason: 'Stop cannot authorize a second payable synthesis');
  });

  test('a failed first render does not trigger the next paid request',
      () async {
    player.setCloudPrefetch(true);
    final playback = player.play();
    await _until(() => http.requests.length == 1);
    http.complete(0, status: 500);
    await expectLater(playback, throwsA(isA<CloudSpeechException>()));
    await Future<void>.delayed(Duration.zero);
    expect(http.requests.length, 1);
    expect(meter.used, 5);
    expect(output.clips, isEmpty);
  });
}
