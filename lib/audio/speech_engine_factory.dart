import '../data/library_store.dart';
import '../domain/speech_preferences.dart';
import 'openai_speech_engine.dart';
import 'speech_audio_cache.dart';
import 'secret_vault.dart';
import 'speech_engine.dart';

/// Explicit provider selection, without probing external networks or silently
/// falling back to a paid engine. Instantiation never generates audio.
class SpeechEngineFactory {
  const SpeechEngineFactory({required this.vault});
  final SpeechSecretVault vault;

  SpeechEngine create({
    required SpeechPreferences preferences,
    required String bookId,
    required LibraryStore store,
  }) {
    preferences.validate();
    switch (preferences.providerId) {
      case 'system':
        return SystemSpeechEngine();
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
