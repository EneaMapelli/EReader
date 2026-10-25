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

  /// Only a previously verified, explicitly supplied local voice can reach
  /// the experimental native adapter. UI discovery remains disabled pending
  /// Windows/Android voice, license, stop and background benchmarks.
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
      case SherpaVitsSpeechEngine.providerId:
        final pack = offlineVoicePack;
        if (pack == null) {
          throw UnsupportedError(
            'A verified local VITS pack is required before enabling this engine',
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

  static const availableProviders = ['system', OpenAiSpeechEngine.providerId];
}
