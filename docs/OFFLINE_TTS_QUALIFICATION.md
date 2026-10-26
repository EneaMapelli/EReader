# M3 — Local sherpa-onnx VITS qualification

**Status:** repeatable opt-in source and Windows host commands are implemented.
No actual Italian/English model has been run by the GitHub-connected
development environment. **Do not enable `sherpa-vits` in the production
provider selector based solely on this harness.**

## Prerequisites

- Windows with the project's Flutter/Dart SDK and native sherpa-onnx
  1.13.8 dependencies present and loading correctly. Build/run a Windows
  Flutter app separately before treating a Dart CLI pass as proof of native
  application integration.
- An authorized VITS/Piper ONNX voice for `it-IT` or `en-US`, with
  `model.onnx`, `tokens.txt`, optional enumerated eSpeak resources, and
  a version-1 `voice-pack.json` with correct SHA-256 values.
- Independently check the actual model publisher, license,
  redistributability, phonemizer requirements and expected hashes. A
  locally generated checksum confirms consistency, not authenticity.
- At least 1 GiB of temporary free disk space for some model copies,
  plus room for synthesized WAV. Use the existing locally verified pack
  mode to avoid duplicating the ONNX model.

## Prepare a local model folder (if no manifest exists)

For files you have legitimately obtained and reviewed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\prepare-offline-voice-pack.ps1 -SourceDirectory "C:\voice-models\italian" -Id it-voice -DisplayName "Italian voice" -Locale it-IT -LicenseId "<actual verified license ID>"
```

The illustrative source folder and name are placeholders, not a downloaded or
bundled model. This command fails if the manifest already exists and does not
download anything.

## Native generation and metrics

**Simplest:** qualify the original locally prepared folder (the model is
copied through the canonical SHA-256 installer into a private temporary
directory and deleted after the run):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-offline-voice-qualification.ps1 -SourceFolder "C:\voice-models\italian" -AcceptNativeRisk
```

**Alternative:** if you already imported a voice into EReader, point to the
parent `offline-voices` directory in application support:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-offline-voice-qualification.ps1 -ModelsDirectory "C:\path\to\EReader\offline-voices" -PackId it-voice -AcceptNativeRisk
```

The separate opt-in `-ExerciseStop` checks whether the synthetic worker
cancellation request settles on this host; native code may not be instantly
preemptible and a device test is still necessary. To manually listen to
generated fixed sample phrases, add `-RetainWav`. Only with that switch are
the sample WAVs copied to the gitignored
`.local-test-results/offline-voice-listening/` directory.

A `PASS` requires SHA-256/manifest checks, native VITS generation of two
fixed public demonstration phrases, WAV container validation and bounded
duration. A `FAIL` uses a sanitized stage name, never book passages,
source paths, API keys, audio content or native stacks.

Measurements included:

| Field | Interpretation |
|---|---|
| `synthesisMs` | Wall-clock native job time including model initialization |
| `audio.durationMs` | Length of actual generated PCM output |
| `realTimeFactor` | Synthesis wall time divided by audio duration; below 1 means faster than playback |
| `processRssMiB` | A whole-process resident-memory **snapshot**, not model-attributable peak RAM |
| `stopOutcome` | Optional cancellation result; `completed-before-cancel` is a race, not proof of cancellation |
| `failureStage` | Limited, safe stage name for troubleshooting a failed run |

This prototype currently loads the model for **each phrase**, so the RTF
includes repeated cold initialization and should not be treated as a
streaming or persistent-worker latency benchmark. Also monitor CPU, battery,
true peak RSS, playback stop/pause, background and lock-screen behavior
separately with the actual Windows/Android app.

## Publish sanitized results for review (optional)

Add `-PublishSummary` to the same command. The wrapper refuses a dirty or
incorrect Git checkout, stages only
`test-results/offline-voice-qualification-latest.json`, commits and pushes
normally on `feature/m0-flutter-foundation`, **without a force push**.

The published data is an allowlist of status, source Git commit, time,
locale, numeric audio durations, synthesis latency, RTF, process RSS and
(optional) stop outcome. It never commits the WAVs, model directory,
manifest bytes, source text, exact local paths or unredacted runtime errors.
A failed run may still publish a `FAIL` report with its safe failure stage.

If publication is not explicitly requested, all results remain under
`.local-test-results/offline-voice-qualification/` and are never uploaded.

## Acceptance gates for enabling the offline engine

1. **Both languages:** authenticated and compatible Italian and English
   model candidates, with license and phonemizer evidence
2. **Desktop/device:** Windows x64 and Android arm64 native build and real
   playback smoke tests with headset/background/interruption transitions
3. **Speech quality:** human listening to both retained WAV samples and
   at least 10 independently chosen narrative passages per language,
   including dialogue and proper names
4. **Performance:** cold first-audio latency, warmed continuous reading,
   memory peak, storage size, CPU/battery and low-end Android benchmarks
5. **Control:** repeated pause, stop, change voice, app close and phone
   interruption without native crash, stale WAV playback or private leaks
6. **Privacy:** no model downloads or book-text transfers without explicit
   approval, no silent fallback to a paid cloud provider

Passing the local CLI alone satisfies none of the complete device-level
milestone requirements.

## Source

- `lib/audio/offline_wave_metrics.dart`: streaming RIFF/PCM header inspector
- `tool/qualify_offline_voice.dart`: explicit native workload and measured metrics
- `tool/run-offline-voice-qualification.ps1`: Windows launcher, isolated
  private result storage, optional whitelisted Git publication
- `test/audio/offline_wave_metrics_test.dart`: header and failure cases
- `test/config/offline_voice_qualification_tool_test.dart`: opt-in/report
  source-structure regressions
