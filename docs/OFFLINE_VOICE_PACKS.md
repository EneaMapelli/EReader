# Offline neural voice packs — M3 first implementation increment

**Status:** voice-pack validation and experimental sherpa-onnx 1.13.8
SpeechEngine adapter implemented in source. **No real model/native synthesis,
WAV playback, Windows or Android smoke tests have passed yet.** The adapter
is deliberately hidden from the ordinary user-facing provider selector until
the model, phonemizer, audio latency and stop/background gates are validated.

## Goal

The initial M3 step is a trustworthy local file boundary for future
sherpa-onnx VITS/Piper models without shipping large model binaries,
downloading them automatically, or making network requests. The project
continues to offer existing free OS TTS during this increment.

`lib/data/offline_voice_pack.dart` installs a **locally supplied** two-file
VITS candidate (`model.onnx`, `tokens.txt`) into a stable per-ID private
folder. A caller provides an explicit manifest with immutable ID, locale,
display name, license identifier, expected SHA-256 of both files, and a
destination directory that belongs to the app. Manifests are not signatures
or a trust mechanism: the user/publisher must verify provenance and rights.

The installer:
- Requires safe IDs and explicit license IDs, and refuses invalid digests.
- Enforces 600 MiB maximum ONNX and 4 MiB maximum tokens by default,
  both before and while streaming. No giant in-memory copy is made.
- Rejects direct symlink files and empty assets.
- Streams files through SHA-256 into a random staging folder inside the
  private destination; only fully verified files are moved into place.
- Never overwrites a preexisting pack. It rechecks both existing files on
  the same manifest before returning their local paths.
- Cleans up failed verification or partial installations. No model text,
  URI, downloaded code, API key or source book text is logged or uploaded.

## Why this does not yet mean sherpa-onnx works

Piper VITS models can require additional language resources
(e.g. espeak-ng-data), and models differ in phonemizer, symbols, output rate,
speaker IDs and licensing. The two-file test fixture is an *integrity
contract*, not proof of ONNX semantics or suitability for a particular
voice or language.

Initial engine proof of concept (source-only, 2026-10-25):

- `sherpa_onnx: 1.13.8` is pinned, rather than floating to 2.0.0.
- `SherpaVitsSpeechEngine` implements the existing `SpeechEngine` contract.
  `synthesizeVitsWave` performs `initBindings()`, VITS model creation,
  `generate()`, WAV writing and `free()` **inside its own worker isolate**.
  Float32 PCM never transfers through a Flutter UI isolate.
- `JustAudioWaveOutput` provides explicit stop and disposal. Synthesis uses
  a random app-private temporary WAV file, which is cleaned after completion
  or a failed/cancelled read. Each utterance currently initializes its model
  afresh; this is a proof of concept, **not** a low-latency reader benchmark.
- Factory routing exists only when a caller explicitly injects an
  `InstalledOfflineVoicePack`. `availableProviders` intentionally excludes
  `sherpa-vits`, and the ordinary UI does not permit activating it yet.
  Unsupported languages/pitch fail closed instead of silently using cloud.
- Mock-driven engine and factory tests cover voice selection, rendering,
  temporary cleanup, stale results after Stop/dispose, no-model gates and
  language mismatch. They do not exercise the native ONNX library.

Before enabling a model in the TTS selector:
1. Verify native sherpa-onnx 1.13.8 dependencies and licenses in Windows x64
   and Android arm64 real builds, including WAV decoder behavior.
2. Extend verified voice packs to cover necessary `espeak-ng-data` and other
   VITS phonemizer resources. The engine currently accepts a caller-supplied
   `dataDir`, but those resources are NOT yet verified by the pack installer.
3. Replace per-utterance `Isolate.run` initialization with a persistent,
   bounded-memory model worker whose inference can be hard-cancelled on Stop.
   The current generation token suppresses late playback but does not
   interrupt an ongoing native synthesis computation.
4. Verify real Italian and English voices on both devices: locale validation,
   pitch/rate capabilities, cold-start, sustained playback, cleanup, app
   background, sleep/Stop races, CPU/battery/RAM, licenses and voice changes.
5. Add a reviewed model selection/download/uninstall UI, with checksum,
   provenance, clear disk cost and explicit consent to downloads.
6. After these gates, expose the provider ID in the discovery UI and attach
   only actually installed voices. Do not silently switch to paid cloud TTS.

No pretrained model or voice license has been bundled with this increment.

References:
- https://pub.dev/packages/sherpa_onnx
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OfflineTtsVitsModelConfig-class.html
- https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter-examples
