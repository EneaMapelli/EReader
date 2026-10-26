import 'dart:io';

import '../data/library_store.dart';
import '../data/offline_voice_pack.dart';
import '../domain/speech_preferences.dart';
import 'openai_speech_engine.dart';
import 'speech_audio_cache.dart';
import 'secret_vault.dart';
import 'speech_engine.dart';
import 'sherpa_vits_engine.dart';

/// Explicit provider selection, without probing external networks or silently
/// falling back to a paid engine. Instantiation never generates audio.
class SpeechEngineFactory {
  const SpeechEngineFactory({
    required this.vault,
    this.offlineVoicePack,
  });
  final SpeechSecretVault vault;

  /// Only a previously checked, explicitly supplied local voice can reach
  /// the experimental native adapter. Windows UI enables this by opt-in;
  /// native voice quality, license and Stop/audio testing remain open gates.
  final InstalledOfflineVoicePack? offlineVoicePack;

  SpeechEngine create({
    required SpeechPreferences preferences,
    required String bookId,
    required LibraryStore store,
  }) {
    preferences.validate();
    switch (preferences.providerId) {
      case 'system':
        return SystemSpeechEngine();
      case 'system-native':
        // A/B mode on Windows: let the OS TTS parse punctuation itself.
        // No network, installation or new voices, unlike neural engines.
        return SystemSpeechEngine(interpretWindowsPunctuation: false);
      case SherpaVitsSpeechEngine.providerId:
        // Explicit opt-in only: the Windows-native sherpa ONNX adapter
        // is still experimental and must never run on untested Android.
        if (!Platform.isWindows) {
          throw UnsupportedError(
              'Experimental offline neural speech is Windows-only');
        }
        final pack = offlineVoicePack;
        if (pack == null) {
          throw UnsupportedError(
            'A verified local VITS pack is required before enabling this engine',
          );
        }
        if (pack.manifest.id != preferences.modelId ||
            pack.phonemizerDataDir == null) {
          throw const FormatException(
            'Selected offline voice does not match a verified VITS '
            'pack with phonemizer data',
          );
        }
        if (preferences.language.toLowerCase().replaceAll('_', '-') !=
            pack.manifest.locale.toLowerCase().replaceAll('_', '-')) {
          throw const FormatException(
            'Installed offline voice does not match configured book language',
          );
        }
        return SherpaVitsSpeechEngine(
          pack: pack,
          // Only manifest-verified phonemizer assets may reach native FFI.
          dataDir: pack.phonemizerDataDir ?? '',
        );
      case OpenAiSpeechEngine.providerId:
        return OpenAiSpeechEngine(
          bookId: bookId,
          modelId: preferences.modelId,
          access: store,
          vault: vault,
          cache: PrivateMp3SpeechCache(),
        );
      default:
        throw UnsupportedError(
          'Speech engine not yet available: ' + preferences.providerId,
        );
    }
  }

  static const availableProviders = [
    'system',
    'system-native',
    SherpaVitsSpeechEngine.providerId,
    OpenAiSpeechEngine.providerId,
  ];
}
