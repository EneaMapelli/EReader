import 'dart:io';

import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/audio/speech_engine_factory.dart';
import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final factory = SpeechEngineFactory(vault: PlatformSpeechSecretVault());
  final store = LibraryStore();

  test('free system voices expose interpreted and native punctuation modes',
      () {
    expect(SpeechEngineFactory.availableProviders, contains('system'));
    expect(SpeechEngineFactory.availableProviders,
        contains('system-native'));
    final interpreted = factory.create(
        preferences: const SpeechPreferences(providerId: 'system'),
        bookId: 'test', store: store);
    final native = factory.create(
        preferences: const SpeechPreferences(providerId: 'system-native'),
        bookId: 'test', store: store);
    expect(interpreted, isA<SystemSpeechEngine>());
    expect(native, isA<SystemSpeechEngine>());
    // No native platform channel calls in pure selection tests.
  });

  test('opt-in interpreted punctuation is a free system engine on Android',
      () {
    expect(SpeechEngineFactory.availableProviders,
        contains('system-interpreted'));
    final selected = const SpeechPreferences(
      providerId: 'system-interpreted',
      language: 'it-IT',
      dialogueTurnPauseMs: 260,
    );
    final interpreted = factory.create(
      preferences: selected, bookId: 'test', store: store,
    );
    expect(interpreted, isA<SystemSpeechEngine>());
    final restored = SpeechPreferences.fromJson(selected.toJson());
    expect(restored.providerId, 'system-interpreted');
    expect(restored.dialogueTurnPauseMs, 260);
    // Merely creating the adapter makes no native TTS calls, triggers
    // no cloud requests and never downloads a voice model.
  });

  test('Piper/VITS cannot be enabled without a selected verified pack', () {
    const preferences = SpeechPreferences(
        providerId: 'sherpa-vits', modelId: 'piper-it-paola',
        language: 'it-IT', pitch: 1.0);
    expect(() => factory.create(
        preferences: preferences, bookId: 'test', store: store),
        throwsUnsupportedError);
  });

  test('invalid VITS model identity/phonemizer never reaches native FFI',
      () {
    const manifest = OfflineVoicePackManifest(
      id: 'piper-it-paola',
      displayName: 'Example Italian voice',
      locale: 'it-IT',
      licenseId: 'MIT',
      modelSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      tokensSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    const pack = InstalledOfflineVoicePack(
      manifest: manifest, modelPath: 'safe/model.onnx',
      tokensPath: 'safe/tokens.txt',
    );
    final withPack = SpeechEngineFactory(
        vault: PlatformSpeechSecretVault(), offlineVoicePack: pack);
    expect(() => withPack.create(
      preferences: const SpeechPreferences(
          providerId: 'sherpa-vits',
          modelId: 'another-pack', language: 'it-IT'),
      bookId: 'test', store: store,
    ), Platform.isWindows ? throwsFormatException : throwsUnsupportedError);
    expect(() => withPack.create(
      preferences: const SpeechPreferences(
          providerId: 'sherpa-vits',
          modelId: 'piper-it-paola', language: 'it-IT'),
      bookId: 'test', store: store,
    ), Platform.isWindows ? throwsFormatException : throwsUnsupportedError,
        reason: 'Without an installed eSpeak phonemizer no native VITS trial');
  });

  test('speech preferences retain distinct selected local model and provider',
      () {
    final chosen = const SpeechPreferences().copyWith(
      providerId: 'sherpa-vits',
      modelId: 'piper-it-paola',
      clearVoice: true,
    );
    expect(chosen.modelId, 'piper-it-paola');
    expect(chosen.providerId, 'sherpa-vits');
    expect(SpeechPreferences.fromJson(chosen.toJson()).modelId,
        'piper-it-paola');
    expect(chosen.voiceName, isNull);
  });
}
