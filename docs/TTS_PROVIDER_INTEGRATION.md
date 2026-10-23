# TTS engines — integration and safety

Status: **code implemented but not compiled or exercised on devices** (2026-10-22). Windows/Android build verification is intentionally deferred to final integration at the owner's request.

## Engines

| Provider ID | Transport | Model | Voices | Permission | Pitch |
|---|---|---|---|---|---|
| system | Windows/Android OS via flutter_tts | OS default | Installed OS voices | Free, offline when installed | Platform-dependent |
| openai-speech | HTTPS POST /v1/audio/speech | gpt-4o-mini-tts or gpt-4o-mini-tts-2025-12-15 | OpenAI built-in voices | Explicit **per-book** opt-in, API key, character budget | **Not available** |

No Azure, ElevenLabs, realtime or neural local adapter has been implemented yet. OpenAI Speech may not read every word verbatim; validate before claiming exact audiobook fidelity.

## Privacy and charging boundaries

1. The default system engine requires no internet, account or API key. Selecting the OpenAI provider or saving an API key does not authorize sending passages.
2. The user grants consent to remote narration separately for each imported book. The UI shows an explicit disclosure before allowing book passages to be transmitted. Merely enabling this setting performs **no request**.
3. SQLite schema v5 stores provider ID, book ID, explicit consent, hard character quota, characters already reserved and approval time. A new request must atomically reserve characters before transmission; retries and HTTP errors count toward the local budget. Revoking consent disables new requests without resetting history. The user cannot lower the quota below already reserved usage.
4. A character budget is **not** a billing cap in euros, and it does not include calls using the same API key elsewhere. Provider pricing can change; no fixed monetary estimate is asserted in the application.
5. API keys are only in flutter_secure_storage, never SQLite, Git, settings exports or query parameters. They can be deleted without erasing book progress. OpenAI requests use the fixed HTTPS host, prohibit redirects, ignore provider error response bodies and limit MP3 response streams to 20 MiB.
6. Cloud speech is requested only after Play for an authorized book and no reusable cached clip. Separately enabling the **session-only, OFF-by-default** prebuffer checkbox may synthesize **one next chunk** before it is heard, consuming characters if the audio is not cached. The system does not upload books for screening automatically.
7. Generated MP3 is saved under private application support storage in a per-book SHA-256 directory. Cache keys are hashes of model, voice and exact spoken text, not raw passages. It is limited to 250 MiB across books and cleaned on book deletion or by an explicit reader-settings action. Audio fragments left by an abrupt process termination still need a startup scavenger.
8. A cache hit requires no new HTTP call, API key or quota reservation, although the book must remain authorized to use its cloud speech engine. Different model, voice or pronunciation will miss cache.
9. The Cloud Speech HTTP API does not expose word marks or direct pitch adjustment in this adapter. Pitch is disabled in the UI for OpenAI, while playback speed can be adjusted through the audio backend.
10. The cloud model may paraphrase despite the original input; precise word-by-word Read Along and alignment are not claimed.

## Contracts and code

- SpeechEngine and SpeechEngineFactory select the native engine or OpenAI adapter; unsupported provider IDs fail explicitly.
- OpenAiSpeechEngine mediates consent, vault, cache, HTTP and MP3 output. It uses a generation token to suppress stale audio playback after Stop, without promising immediate HTTP cancellation.
- SpeechHttpTransport, SynthesizedAudioOutput, SpeechSecretVault, CloudSpeechAccess and SpeechAudioCache are injectable so unit tests do not contact real providers, need devices, or use secrets.
- SpeechProviderScreen controls provider/model selection, key replacement/removal, per-book consent and quota, and cache cleanup. Engine preferences and voice settings are stored without credentials.
- LibraryStore enforces budget limits with SQLite transactions; no payment information is stored.

## Next increments

- Add independent Azure Speech and ElevenLabs adapters, and optional local ONNX/Piper/sherpa-onnx neural voices with capability negotiation; never reuse one provider's consent for another.
- Extend current one-chunk opt-in prebuffer to controlled, cancellable chapter queues only after assessing excess quota and interruption billing; verify licenses and exact narration on real books.
- Build the speaker/character assignment model and optional LLM screening without sending any book text before opt-in.
- Perform final Windows/Android analysis, builds, tests and secure-storage smoke tests; add native platform runners and review network permissions.

## References

- OpenAI Audio Speech: https://developers.openai.com/api/reference/resources/audio
- Flutter secure storage: https://pub.dev/packages/flutter_secure_storage
- just_audio for Windows/Android: https://pub.dev/packages/just_audio and https://pub.dev/packages/just_audio_windows
- Dart http: https://pub.dev/packages/http

Authored tests (NOT executed): OpenAI Speech transport and consent; budget, key and failure modes; audio cancellation; private cache isolation and reuse; SQLite v4-to-v5 migration; speech preferences model serialization.


## Cloud prebuffer implementation (2026-10-23)

The optional `AheadOfTimeSpeechEngine` capability is implemented only by OpenAiSpeechEngine. ReaderScreen exposes a session-only **OFF by default** checkbox explaining that preparing the next cloud chunk can use the per-book quota even if never heard. Preparation is gated until the active audio has rendered successfully, limited to one future chunk, and uses the existing HTTPS consent/cache/key/reservation protocol with a separately captured next voice. The player still emits one MP3 clip at a time. `stop()` invalidates unfinished playback, but a submitted HTTP request may already have incurred billing. Full semantics, tests and limitations: [Cloud TTS Prefetch](CLOUD_TTS_PREFETCH.md). **No Flutter/native tests have run yet.**
