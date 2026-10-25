import 'dart:io';

import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/audio/sherpa_vits_engine.dart';
import 'package:ereader/audio/speech_engine_factory.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoCloudVault implements SpeechSecretVault {
  @override
  Future<String?> readKey(String providerId) =>
      throw StateError('An offline voice must never request a cloud key');
  @override
  Future<void> saveKey(String providerId, String value) =>
      throw StateError('Unexpected cloud key save');
  @override
  Future<void> deleteKey(String providerId) =>
      throw StateError('Unexpected cloud key deletion');
}

void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-vits-factory-');
    store = LibraryStore(homeDirectory: root);
  });
  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  SpeechPreferences local({String language = 'en-US'}) => SpeechPreferences(
    providerId: SherpaVitsSpeechEngine.providerId,
    language: language,
  );

  test('offline engine remains hidden until native device qualification', () {
    expect(SpeechEngineFactory.availableProviders,
        isNot(contains(SherpaVitsSpeechEngine.providerId)));
    expect(SpeechEngineFactory.availableProviders,
        contains('system'));
  });

  test('factory refuses offline selection when no verified pack was provided',
      () {
    final factory = SpeechEngineFactory(vault: _NoCloudVault());
    expect(() => factory.create(
      preferences: local(), bookId: 'book-id', store: store,
    ), throwsUnsupportedError);
  });

  test('factory refuses model locale mismatch before native library startup',
      () {
    final manifest = OfflineVoicePackManifest(
      id: 'en-test', displayName: 'English sample',
      locale: 'en-US', licenseId: 'MIT',
      modelSha256: 'a' * 64,
      tokensSha256: 'b' * 64,
    );
    final installed = InstalledOfflineVoicePack(
      manifest: manifest,
      modelPath: p.join(root.path, 'model.onnx'),
      tokensPath: p.join(root.path, 'tokens.txt'),
    );
    final factory = SpeechEngineFactory(
        vault: _NoCloudVault(), offlineVoicePack: installed);
    expect(() => factory.create(
      preferences: local(language: 'it-IT'),
      bookId: 'book-id', store: store,
    ), throwsFormatException);
  });
}
