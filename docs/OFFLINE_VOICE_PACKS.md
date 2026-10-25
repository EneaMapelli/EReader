# Offline neural voice packs — M3 first implementation increment

**Status:** source-only admission and file management; **no audible offline
neural TTS is connected to ReaderPlayer yet**. Do not show these packs in
the app's selectable speech providers until a validated native adapter exists.

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

Before enabling a model in the TTS selector:
1. Choose and pin a compatible sherpa_onnx Flutter version and ensure
   Windows x64 / Android arm64 native assets and licenses pass review.
2. Extend the explicit manifest to cover required phonemizer assets and
   their individual digests; avoid blind ZIP extraction and path traversal.
3. Initialize the FFI runtime on the correct isolate; keep model
   initialization cancellable and avoid blocking UI frames.
4. Add an `OfflineSpeechEngine` implementing the same speech contract,
   with PCM/WAV output and serial stop/disposal; never pretend an unavailable
   model is present or silently switch to paid cloud TTS.
5. Validate real Italian and English voices on Windows/Android with
   pronunciation, memory, cold-start, pause, stop, background, licensing
   and voice-change tests. Provide an uninstall/space management UI.

No pretrained model or voice license has been bundled with this increment.

References:
- https://pub.dev/packages/sherpa_onnx
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OfflineTtsVitsModelConfig-class.html
- https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter-examples
