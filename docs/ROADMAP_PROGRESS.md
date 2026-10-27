# EReader — Progress against approved 2026-10-22 roadmap

**Reviewed:** 2026-10-26. **Current branch:** `feature/m0-flutter-foundation` (PR #1 draft).

These percentages are *engineering judgments*, not measured test pass rates.
They describe feature/code coverage against the original milestone exit
criteria, taking unresolved integration into account. Equal-weight average
for M0–M6 is approximately **55%**; estimated practical release readiness is
much lower (**roughly 25–35%**) because native and acceptance gates are open.
No release or completed milestone is claimed.

| Original milestone | Estimated implementation | Evidence already in repository | Key unmet exit criteria |
|---|---:|---|---|
| M0 Foundation and POCs | 60% | Flutter modules, SQLite migrations, EPUB/PDF/system TTS source, bootstrap scripts and test runner | Native `android/` and `windows/` generated projects are not tracked; sherpa-onnx, native platform POCs, licensing/ABI results |
| M1 Reader MVP | 83% | SQLite book library and dedup, EPUB2/3/PDF/TXT, anchors/TOC/bookmarks/search, user-editable title/author/series/language via SQLite v17 and catalog sort/filter | 20-book real corpus, Windows and Android smoke tests, richer EPUB/CSS/CFI and complex PDF reading order |
| M2 Free TTS and read-along | 70% | OS speech adapter, voice controls, text/audio checkpoints, source highlight and scrolling, segment navigation, sleep timer, media session source, interruption guards | Real Android lock-screen, phone-call/audio-focus and Windows key tests; guaranteed chapter-long playback and accurate engine timing |
| M3 Offline neural and cloud | 35% | Secure cloud keys/consent/cache; guarded sherpa VITS worker and manifest-verified assets; local voice status/removal screen | No native ONNX voice qualification, guided model installer or authenticated catalog, no Realtime/second provider, live-cloud validation or monetary ceiling |
| M4 Manual multivoice cast | 75% | Character identities, manual and locked cast spans, voice profiles, quote segmentation, no-speaker fallback, review/editor UI | 3+ character/native audio listening gate, richer segmentation and prosody, speaker performance verification |
| M5 LLM-assisted review | 55% | Opt-in bounded OpenAI analysis, proposals for speakers/characters/aliases, context and spoiler cap, evidence checks, identity reconciliation and review UI | No offline LLM, chapter/full-book screening pipeline with cost ceiling, annotated gold corpus, calibrated precision/recall and large-book validation |
| M6 Release and polish | 10% | Docs, local Windows run harness and manual CI workflow; a number of EPUB performance/robustness tests | Native Windows/Android packaging and signing, accessibility audit, benchmarks, privacy/licensing inventory, release candidate |

### Verification evidence, not an estimate

- Latest published and normalized Windows run:
  `20261025T201001Z-7c89dfc8-a63603` (source `7c89dfc8`).
  **641 passed, 0 failed assertions, 7 errors, 76 discovered test files**;
  overall FAIL. Pub-get and Dart/Flutter version checks succeed.
- Analyzer: **zero errors**, ten source/test warnings, plus informational
  lints; nonzero analyzer exit code remains until warnings/info are resolved.
  Formatting fails for 147 existing Dart files (`dart format` not applied).
- Six source-search widget cases share a Flutter intrinsic-size crash:
  `AlertDialog` measures a lazy result ListView that has no intrinsic width.
  The search dialog now supplies a finite parent width before layout.
- The remaining EPUB worker preflight test failed while Windows held a
  temporary EPUB file (sharing violation 32) during teardown. Its fixture
  cleanup now retries transient Windows locks a bounded number of times.
- Ten nonblocking analyzer warnings have been addressed, and only sanitized
  summaries/results of the newest run remain in the current branch.
  Raw per-command logs were mistakenly committed in a prior commit and
  are excluded from the current tree; `.gitignore` now prevents accidental
  restaging. Removing them from the current tree does not erase older Git
  history.
- **All remedial commits postdate that run**. No updated platform test suite
  has verified these changes; do not count them as passing or declare a
  native Windows/Android milestone completed.

### Highest-impact next steps

1. Execute `tool/run-all-tests.ps1` on the current branch HEAD, publish
   sanitized results, then repair remaining analyzer/test errors.
2. Generate and verify the real Windows and Android project folders and
   smoke-test import, read, close/reopen, no-network system TTS, background
   controls and PDF text-layer handling on devices.
3. Finish M0/M3 offline neural TTS proof of concept and model/license
   inventory, and migrate the transitory OpenAI Speech path to a supported
   Realtime adapter; evaluate a second provider under capability flags.
4. Curate at least 10 representative legal narrative samples for M4/M5
   speaker attribution metrics and golden source-fidelity comparisons.
5. Complete M6 packaging/signing, accessibility, performance/power and
   distribution/license/privacy gates.

**Scope note:** Proposed ER-017–ER-034 extensions (OCR, OPDS, audiobook
export/import, sync, contextual AI, massive-library indexing) are not
included as completed features by merely having been designed in the roadmap.

### Progress note — 2026-10-26

- Added a guarded **offline model manager** reachable from the speech
  settings screen. It lists and verifies installed packs, marks damaged
  entries and supports user-confirmed removal of an individual pack; neural
  synthesis remains unavailable until a licensed model and Windows/Android
  acceptance tests exist. M3 estimate rises cautiously to **35%**; overall
  M0–M6 remains approximately **54%** with equal milestone weighting.
- Latest executed Windows run still reports 641 pass and 7 errors at older
  commit `7c89dfc8`. The search dialog intrinsic-width fix, Windows
  temporary-handle cleanup, warning reductions and this new model manager
  are not yet validated by a new run.

### Progress note — guided import (2026-10-26)

- The new guarded M3 model manager now supports **local Windows VITS
  folder import** after reviewing the manifest, size and declared license,
  with explicit affirmative approval before SHA-256 checked installation.
  A local PowerShell manifest-preparation helper computes checksums for
  previously obtained ONNX/phonemizer resources. No model downloading or
  automatic cloud requests were added.
- This does not authenticate a publisher's checksums or grant usage
  rights. The neural engine remains hidden from user-facing TTS selection
  pending real-model audio tests, Android SAF handling, licensing review
  and native device qualification.
- The previous M3 feature-coverage estimate remains **35%** pending
  passing integration evidence; overall M0–M6 estimate is unchanged.
- The most recent executed Windows report still shows 641 successful tests
  and 7 errors at older source `7c89dfc8`; the new import UI and tests
  have not been run. The 147 previously unformatted files remain a
  separate unresolved check until the formatter utility is executed.

### Progress note — model qualification instrumentation (2026-10-26)

- A new opt-in local neural benchmark now measures actual VITS-produced
  WAV properties, inference wall time, real-time factor and RSS snapshots,
  with two preset phrases per locale and a separate optional Stop probe.
  It accepts either installed verified packs or a source folder that is
  hash-checked into private temporary storage. It can optionally upload a
  whitelisted numeric result; no native result currently exists.
- See [OFFLINE_TTS_QUALIFICATION.md](OFFLINE_TTS_QUALIFICATION.md)
  for Windows commands, limitations and mandatory native acceptance gates.
  **M3 remains 35% estimated** rather than increasing based only on a
  benchmark that has not run; overall M0–M6 remains ~54% feature coverage.
- Most recent executed Windows suite is still `7c89dfc8`: 641 passed,
  no assertion failures, 7 errors, plus 147 unformatted source files.
  Do not count the post-run search/EPUB/M3 changes as validated.

### Progress note — catalog metadata (2026-10-26)

- Completed an additional **M1 product feature**: manually editing
  title, author, series and language in the library; searching and ordering
  by author/series; preserving book hash identity, progress, cast, consent
  and bookmarks through transactional SQLite migration **v17**.
  Optional metadata survives dedup/reimport and restart. Locale is
  intentionally library metadata and does **not** silently change the
  user's configured speech provider or voice.
- Updated M1 estimated feature coverage from 75% to **78%** and the
  equal-weight M0–M6 estimate from ~54% to **~55%**. These are qualitative
  judgments, NOT executed-native acceptance percentages.
- Full point-by-point original plan and approved extensions:
  [ROADMAP_DETAILED_PROGRESS.md](ROADMAP_DETAILED_PROGRESS.md).
- No new Windows test result exists beyond `7c89dfc8`: 641 passes,
  0 assertion failures, 7 error outcomes. The new SQLite migration,
  metadata editor and search changes have not been locally compiled here.

### Progress note — optional real-book corpus coverage (2026-10-26)

- M0/M1 now have an opt-in real EPUB/PDF regression harness for the user's
  local `example/` folder. It covers actual import, decode, reader source
  positions, persisted SQLite progress and native PDF opening, with optional
  EPUB background narration-source consistency checks.
- The tests do not require remote books or auto-publish filenames/results;
  all detailed reports and files stay outside Git. See
  [EXAMPLE_CORPUS_TESTS.md](EXAMPLE_CORPUS_TESTS.md).
- Existing M0/M1 feature percentages remain **60% / 78%**, and overall
  milestone coverage remains **~55%** until real corpus and native client
  results demonstrate what works and what needs repair.

### Progress note — EPUB2/3 OPF auto catalog (2026-10-26)

- Newly imported EPUBs now receive metadata from their embedded OPF
  (title, creator, language and Calibre/EPUB3 series). Pre-existing
  entries can explicitly fill missing fields without replacing user
  edits via the library dialog. Extraction is local, bounded and runs
  on an isolate; no web, LLM or cloud metadata lookup.
- M1 rises qualitatively to **80% feature coverage**; the seven-milestone
  overall rounded estimate remains **~55%**, since no real device or
  local book corpus run has validated this new work.
- Cover thumbnails, complex metadata, PDF reading order, OCR and
  verified Windows/Android rendering remain open.

### Progress note — book cover thumbnails (2026-10-26)

- Declared EPUB2/EPUB3 cover-image assets are now recognized from OPF
  metadata and validated as bounded PNG/JPEG, with no external URL fetch.
  Import caches a digest-named private cover file; the library displays it
  with a format-icon fallback for invalid/absent images. Covers can be
  regenerated by the explicit **Fill from EPUB** action and are removed
  with the corresponding book.
- Cover bytes never enter SQLite, a cloud adapter, or a tracked test report.
  Added parser/cache/UI tests and boolean-only detection in the local
  `example/` corpus report. **No real Flutter/Windows/Android run yet.**
- M1 implementation coverage is estimated at **82%** (was 80%), while the
  milestone-weighted overall estimate remains **~55%** pending device-level
  verification. PDF thumbnails, richer EPUB cover art, and packaging remain
  outside this increment.

### Progress note — PDF navigation and spoken-page alignment (2026-10-26)

- Added physical PDF page stepper, jump-to-page with strict boundaries,
  current/total indicator, and zoom controls backed by `pdfrx`.
- Explicit **Read text aloud** starts narration at the current readable
  physical page while leaving an independent visual checkpoint; returning
  to pages can align to the active spoken PDF text page. Scanned or blank
  page gaps never fabricate text/OCR content.
- M1 rises cautiously from 82% to **83% estimated feature coverage**,
  overall milestone-weighted coverage remains **~55%**. Real PDF testing
  on Windows/Android and multi-column reading order remain unresolved.

### Anteprime PDF in biblioteca (2026-10-26)

- M1: aggiunto rendering **locale e lazy** della prima pagina PDF come
  PNG limitato a 180 × 260 px, con cache privata nominata dall'hash del libro;
  non richiede rete, cloud, nuova migrazione SQLite o chiavi API.
- Una sola generazione contemporanea per libro, fallback sicuro all'icona
  PDF per documenti corrotti/cifrati, cleanup su cancellazione, gestione
  della rimozione durante il rendering. EPUB e TXT restano invariati.
- Aggiunti test sintetici (senza PDFium nativo) per persistenza,
  concorrenza, uscita su errore, cancellazione, e widget di biblioteca.
- **Non ancora eseguiti** i nuovi test Dart/Flutter né un POC di rendering
  PDFium su Windows/Android. M1 resta **83%**, media M0–M6 circa **55%**;
  la verifica nativa e il corpus reale restano criteri d'uscita aperti.
- [Nota implementativa e piano manuale](PDF_LIBRARY_THUMBNAILS.md).

### M2 — controllable EPUB narration of footnotes (2026-10-26)

- A session-only OFF-by-default toggle can skip only fully contained source
  segments of semantically recognized, preview-verified EPUB footnotes.
- Canonical EPUB text, offsets, bookmarks, per-character voices, original
  links and on-screen footnotes are unchanged. Crossing/ambiguous segments
  remain audible rather than removing main prose.
- The player applies the skip before speech, segment-start persistence and
  cloud lookahead: the next skippable chunk is no longer sent for speculative
  synthesis. Already in-flight prebuffering cannot be withdrawn.
- Synthetic EPUB, UTF-16, false-positive, player and cloud-lookahead regression
  tests authored; they have **not** been run with Flutter/Dart nor on devices.
- M2 remains **70%** and the overall feature estimate remains about **55%**,
  since neither continuous playback nor native acceptance gates have closed.
  Implementation and manual acceptance: [EPUB_SPOKEN_NOTE_CONTROL.md](EPUB_SPOKEN_NOTE_CONTROL.md).

### M2 narrator paragraph continuity (2026-10-26)

- Enabled a **source-safe, <=400 UTF-16** narrator-chunk coalescing option
  only for EPUB. No cross-chapter/paragraph, quote group, manual voice
  assignment/mask or verified footnote boundary merges.
- Original source/reader anchors and opt-in note skipping remain intact.
  Fewer TTS handoffs are expected for short prose sentences; no gapless
  playback, lower billed characters, or device-quality result is claimed.
- Added synthetic domain and sequential fake-player cases. Flutter analyze,
  tests and Windows/Android playback were NOT RUN; M2 stays 70%, overall
  M0-M6 ~55%. See
  [NARRATOR_PARAGRAPH_CONTINUITY.md](NARRATOR_PARAGRAPH_CONTINUITY.md).

### M2 — cache-only next clip warmup (2026-10-26)

- New separate cached-MP3 lookahead is default ON for cloud narration,
  user-configurable, and strictly local: without an exact private cached
  hit, it does **not** send HTTPS, reserve characters or synthesize ahead.
- Existing **paid** next-chunk synthesis remains OFF by default and requires
  the already documented explicit opt-in. Both paths now seek the next
  *audible* chunk past user-skipped verified EPUB notes.
- Added fake HTTP/cache/native-output regressions for voice snapshots,
  cache hits/misses, speed, consent revoke and cancellation. Authored but
  not run on Windows/Android; no gapless claim.
- M2 stays 70%, total M0–M6 ~55%; see
  [CACHED_AUDIO_WARMUP.md](CACHED_AUDIO_WARMUP.md).

### M2 — native MP3 decoder Stop optimization (2026-10-26)

- Removed unnecessary `Mp3Decoder.stop()` before first playback and after
  a previously confirmed finalizer Stop, without allowing overlapping audio.
- Failed/partially opened `setFilePath` now triggers Stop before temporary
  file removal; a failed native Stop remains mandatory on retry.
- Added delayed-Stop, cold/warm decoder and partial-failure mock tests.
  **Not executed** (no Dart/Flutter/native SDK in this environment).
- No measured native playback-latency gain is claimed. M2 remains 70%;
  overall roadmap estimate remains ~55%. See
  [MP3_NATIVE_STOP_DEDUP.md](MP3_NATIVE_STOP_DEDUP.md).

### M2 — Android focus interruption + completed-segment checkpoint (2026-10-26)

- Android MediaSession now coalesces repeated audio interruption/noisy events:
  one in-flight native Stop, never an automatic cloud/OS TTS restart. Even
  duplicate interruptions cancel newly pending remote Play commands.
- An already settled-idle player skips gratuitous native Stop on Pausa,
  while still invalidating pending focus/Play and releasing Android focus.
  Native Stop during seek, voice switch and active speech remains mandatory.
- New optional ReaderPlayer completion callback advances the SQLite source
  position to the **next audible segment** only after the current clip
  finished. Interrupting a clip keeps its start offset; verified skipped
  EPUB notes are passed over for the next saved position.
- Mock focus/Stop race and real SQLite recovery integration tests authored,
  NOT RUN. M2 estimate 70%, total ~55%; see
  [AUDIO_INTERRUPTION_CHECKPOINTS.md](AUDIO_INTERRUPTION_CHECKPOINTS.md).

### M2 — PDF page-aligned speech and correct EOF restore (2026-10-26)

- Restored completed-book checkpoints now map to the **finished** speech
  cursor (segment count) instead of replaying the final sentence. An
  explicit EPUB TOC/bookmark/search jump still resolves to a real clip.
  Reader UI shows a completed state and treats Play as restart.
- Final narration checkpoint now stores exact EPUB spine or physical PDF
  page source anchor, and old offset-only EPUB checkpoints preserve a
  valid `source.length` EOF instead of clamping backwards.
- PDF text-layer chunks are segmented independently per physical page,
  with exact UTF-16 offsets and quotation reset at page boundaries.
  PDF visual page turning remains independent from narrated progress.
- Added targeted source, PDF pages/UTF-16/quote and EOF recovery tests,
  NOT RUN; native Windows/Android QA still pending. M2 remains 70%;
  total M0–M6 ~55%. [Design and manual QA](READER_SOURCE_SYNC.md).

### M2 — silent EPUB spines and trailing scanned PDF navigation (2026-10-26)

- OPF spine directory now includes visual-only/whitespace/empty sections
  instead of discarding them. Exact visual source offsets are kept distinct
  from a next-audible TTS index; silent entries are explicitly labeled.
- A silent trailing section, link or source-exact bookmark sets the speech
  cursor to EOF rather than replaying the previous sentence. New serialized
  `seekToSourceEnd` cancels stale auto-resuming seeks without synthesis.
- Selecting a PDF image-only page still moves forward to real text where
  available; when all following pages are textless, Read Aloud now refuses
  clearly rather than narrating a previous page or using stale progress.
- Added pure EPUB, PDF and mock native-player regression tests (not run).
  Source/doc status remains uncompiled. M2 ~70%, overall ~55%.
  [Design and manual QA](VISUAL_ONLY_SOURCE_NAVIGATION.md).

**EPUB extractor integration:** empty/xhtml image-only OPF items are now
recorded as zero-length source ranges instead of being discarded, so the
visual directory can actually display their OPF ordering. All-textless
books still reject; no fake TTS text or rendered illustrations are claimed.
Actual ZIP fixture tests added/updated but not executed.

### M2 — illustrated zero-text EPUB spine blocks (2026-10-26)

- EPUB ZIP extraction now preserves safe local raster image references
  even when their containing XHTML contributes **zero spoken text**.
  `EpubEmbeddedImage.spineIdref` retains exact OPF origin; remote images,
  unsupported formats, malformed raster/dimensions and existing byte budgets
  remain fail-closed.
- Source-integrity auditing now correctly accepts valid leading, middle
  and trailing zero-length XHTML spine entries while still rejecting
  duplicate IDs, invalid Unicode positions, incorrect separators/holes,
  overlaps and fully non-textual books.
- Progressive EPUB rendering creates individual, lazy visual-only blocks
  with title + independently associated PNG/JPEG or an explicit no-text
  placeholder. Two covers sharing one UTF-16 offset no longer misplace
  each other's images.
- Exact OPF-idref scroll/selection/save/restore disambiguate source-empty
  sections; trailing illustrated content preserves speech EOF rather than
  replaying the preceding utterance.
- ZIP-backed, structural and widget regressions authored, NOT RUN.
  See [EPUB_ILLUSTRATED_SPINE.md](EPUB_ILLUSTRATED_SPINE.md).
  Qualitative estimate M2 ~70%; total M0–M6 ~55%.

### M2 — source-ordered inline EPUB figures (2026-10-26)

- EPUB pictures in spoken XHTML paragraphs are now **interleaved at their
  canonical source offset** instead of always being appended below the
  paragraph. Only visual runs split: source string, TTS chunk, voices,
  search/link/footnote offsets and SQLite bookmarks remain unchanged.
- Both progressive (LRU/lazy) and eager/reference layouts attach pictures
  within their originating OPF spine block range; eager layout also retains
  independent image-only OPF visual blocks for parity.
- Equal-offset pictures preserve original order. Defensive source splitting
  never divides a UTF-16 surrogate pair. Flutter uses the same private,
  bounded local image decoding, no added external fetch.
- New pure unit and Flutter widget regression cases authored but NOT RUN;
  full XHTML/CSS geometry, image-only books and table-cell images are
  still separate work. See [EPUB_INLINE_IMAGE_FLOW.md](EPUB_INLINE_IMAGE_FLOW.md).
  M2 qualitative estimate remains ~70%, overall ~55%.

### M2 — XHTML figcaption and in-place table previews (2026-10-26)

- Semantic `<figcaption>` source intervals are extracted, validated and
  preserved through the ZIP/isolate `DocumentContent` adapter. Both eager
  and progressive readers italicize/smaller-style only the original caption
  run: no cloned text, voice, link, note, search or bookmark offset.
- EPUB table previews now enter the source-ordered image/text flow at the
  table **END**, in the correct lazy/eager text block, instead of always
  appearing below the entire paragraph. Source text stays selected/spoken;
  structured `ExpansionTile` preview remains optional and collapsed.
- Added source projection, renderer parity, validation and widget tests,
  authored but NOT RUN. Complex CSS/table merging and full graphical
  EPUB rendering remain outside this increment.
  [EPUB_FIGURE_CAPTION_TABLE_FLOW.md](EPUB_FIGURE_CAPTION_TABLE_FLOW.md).
  M2 remains ~70%, roadmap total ~55%.

### Windows x64 portable Release for first user testing (2026-10-26)

- Added `tool/build-windows.ps1`, which generates the Flutter Windows
  native runner when absent, resolves dependencies, builds
  `flutter build windows --release`, checks `ereader.exe` plus
  `data/flutter_assets`, and ZIPs the **entire Release folder**
  with DLLs, launcher, test-readme and SHA provenance.
- Added a separate Windows-only GitHub Actions workflow
  `windows-user-build.yml` with an unsigned portable ZIP artifact,
  14-day retention, and no analyzer/automated test gate. A push-trigger
  is limited to packaging workflow/script changes; manual rebuilds
  are available via workflow dispatch when GitHub exposes it.
- Local build artifacts are ignored in `.local-windows-build/`.
  Documentation and a manual smoke checklist support first Windows
  end-user testing without uploading owned EPUB/PDF/keys.
- The first runner attempt failed at PowerShell parsing before compiling;
  script syntax was corrected and a second run was launched. A usable
  executable must NOT be claimed until the Release job and uploaded
  artifact are confirmed successful. See
  [WINDOWS_USER_TEST_BUILD.md](WINDOWS_USER_TEST_BUILD.md).

- The first **successful actual** Windows x64 Release artifact was produced
  2026-10-26: [Actions run #40382035244](https://github.com/EneaMapelli/EReader/actions/runs/40382035244),
  code SHA `c1f783ca`. Native packaging contains `ereader.exe`,
  Flutter runtime/data and native audio/PDF/SQLite DLLs; ZIP integrity
  checked. Earlier build blockers fixed: nonexistent pdfrx controller
  dispose and VS 2026 experimental-coroutine rejection in
  just_audio_windows. Pinned Windows Server 2022/VS2022 for packaging
  and manual verification. **Windows user launch / real audio still
  unverified**, even though the Release compiled successfully.
  [User test guide](WINDOWS_USER_TEST_BUILD.md).

### Windows voices: punctuation-aware TTS phrasing (2026-10-26)

- The native Windows `SystemSpeechEngine` now uses a bounded, source-
  independent punctuation planner: commas, periods, questions, quotations
  and narrative dashes become timed, cancellable pauses between phrases,
  rather than literal symbols to be spoken by Windows TTS voices.
- Decimal commas/dots, clock colons, Unicode contractions and hyphenated
  words remain intact; displayed book text, checkpoints, cast indices
  and user pronunciation rules are unchanged. Other TTS providers are
  unaffected. Native Stop cancels remaining phrase pauses.
- Authored new focused planner regressions (NOT RUN); requested a fresh
  Windows x64 portable build so user can check the audio quality manually.
  [Guide](WINDOWS_TTS_PUNCTUATION.md). Estimates unchanged until real audio QA.

### Free offline TTS choices (2026-10-26)

System speech offers two Windows punctuation profiles. The existing VITS/Piper adapter is now opt-in for locally installed, checked voice packs on Windows. No automatic model download, cloud call, or default activation. Kokoro and Chatterbox remain future research candidates. See docs/FREE_TTS_ENGINES.md. Unit tests authored but not executed; device audio quality and stability need manual validation.

### Windows curated Paola model installation (2026-10-27)

Added explicit one-click Piper Paola installation in the Windows offline voice manager. Only after opt-in, the client streams the pre-converted official sherpa-onnx archive, checks its pinned GitHub release SHA-256 before Windows tar extraction, verifies expected model/tokens/eSpeak files and atomically installs locally; no cloud/model redistribution or automatic voice activation. Installer/path corruption test fixtures authored, not run. Windows native voice playback remains unverified. See [PIPER_PAOLA_ONE_CLICK.md](PIPER_PAOLA_ONE_CLICK.md).

### M1 — importazione multipla e gestione errori biblioteca (2026-10-27)

- Il picker supporta ora selezione multipla EPUB/PDF/TXT (massimo 50),
  usando l'API `file_picker.pickFiles()` già presente. Il percorso
  `importPickedBooks` importa in sequenza senza caricare l'intero batch
  in RAM, isola gli errori, segnala duplicati SHA-256 e preserva i
  segnalibri dei libri esistenti; Android SAF senza filesystem continua
  a usare staging bounded e pulizia garantita.
- UI con contatore, barra di avanzamento, **Cancel remaining** (solo fra
  file), riepilogo di successi/duplicati/errori con nomi sanitizzati.
  Un solo libro continua ad aprirsi automaticamente; più libri non
  avviano il TTS. Test Dart scritti ma NON eseguiti.
- Non implementa ancora drag&drop Windows, importazione ricorsiva di
  cartelle né OPDS. [Specifiche e test utente](LIBRARY_BATCH_IMPORT.md).

- Build Windows Release con import multiplo effettivamente
  **compilata e pubblicata**: [windows-test-45a013cf](https://github.com/EneaMapelli/EReader/releases/tag/windows-test-45a013cf),
  run 40465285992. Test d'interazione e corpus non eseguiti.

### M6 — manual-only Windows Actions + private library backup (2026-10-27)

- Windows portable build workflow now has **only `workflow_dispatch`**.
  The `push` trigger and file-watch list were removed as requested;
  ordinary source commits must never consume Windows Actions minutes.
  No workflow was run for this increment.
- Introduced a guarded **local library backup export**: database snapshot
  through SQLite `VACUUM INTO`, all managed EPUB/PDF/TXT copied and
  reverified with SHA-256, plus a portable JSON manifest.
  Database integrity and book identity must pass before atomically
  promoting a staging directory; corrupted/missing files abort without
  creating a completed backup. Old backups are never overwritten.
- Book positions, bookmarks, metadata, voice/cast settings and saved
  DB annotations are represented, but OS credential-vault secrets and
  disposable caches are excluded. Backup is **unencrypted** and needs
  a restore/path-relinking feature before it can be safely imported to
  another installation. No cloud upload.
- UI warning, destination picker, progress and end-of-export summary.
  Unit tests authored but NOT RUN. [Details](LIBRARY_BACKUP_EXPORT.md).

### M6 — guarded library backup restore, no Actions build (2026-10-27)

- New read-only preview checks **the entire** private backup v1:
  manifest, SQLite v17/integrity, catalog/counts, bookmarks/source anchors,
  metadata and reading positions, exactly named managed EPUB/PDF/TXT files,
  SHA-256 per book, bounded sizes and no symlink traversal.
- Add-only restore requires explicit confirmation, copies missing book hashes
  into this installation's managed directory and verifies the copied digest
  before atomically committing each new book's catalog, position, bookmarks
  and visual PDF page. Existing books and all their local state are unchanged.
- This is a conservative cross-device **book/metadata/bookmark restore**,
  not a wholesale database replacement. It does not transfer any native
  credential, cloud/LLM authorization, global/per-book TTS preference,
  voice/cast records or speech/recovery sessions. Book-by-book imports may
  leave earlier successful books if a later one fails; retry skips hashes
  already present. Backups remain unencrypted.
- Library UI: select backup directory, integrity state, preview with
  new/duplicate counts, explicit confirmation, progress and final results.
  New regression fixtures authored but **NOT RUN**; no Windows build
  and no GitHub Actions job started, as requested.
  [Restore specification](LIBRARY_BACKUP_RESTORE.md).

### M1 — drag & drop Windows Explorer nella biblioteca (2026-10-27)

- Aggiunto `desktop_drop: 0.9.2` (Flutter 3.47.7); schermata biblioteca
  Windows avvolta in un target file-only con overlay visivo, indicazione
  permanente e filtro EPUB/PDF/TXT. Android rimane sul picker SAF.
- I file vengono importati in sequenza dalla callback asincrona,
  perché l'accesso ai file virtuali Windows termina al completamento
  del drop. I percorsi trascinati non sono considerati affidabili.
  Zero download di URL o import di cartelle; massimo 50 file.
- Riutilizzate le verifiche/hash, importazione multipla,
  annullamento e messaggio finale con duplicati e file ignorati.
  Aggiunti test unitari di filtro e handoff, **non eseguiti**.
- **Nessuna build Windows e nessuna Action avviata**. I workflow rimangono
  manuali secondo la richiesta. [Guida](LIBRARY_DESKTOP_DRAG_DROP.md).

### M3 — calcolatore opzionale budget USD/limite caratteri (2026-10-27)

- L'impostazione cloud del singolo libro include ora un calcolatore senza
  tariffario preinstallato: l'utente inserisce prezzo **USD per milione di
  caratteri** e budget totale USD. Il calcolo in centesimi interi effettua
  divisione con arrotondamento **per difetto**, fino al limite esistente di
  dieci milioni di caratteri; input anomali, zero e prezzo mancante sono
  respinti. L'eventuale storico già riservato non può essere azzerato.
- **Non** si salva il prezzo o il budget in dollari e non si autorizza alcuna
  chiamata premendo “Calculate”: il risultato compila soltanto il limite
  caratteri, poi richiede la conferma standard per aggiornare la quota
  locale SQLite atomica. Il backend Speech non cambia e il prefetch
  continua a riservare la quota prima di inviare testo remoto.
- Questo è un **preventivo user-supplied**, non un vero tetto di spesa
  monetario: tariffe, arrotondamenti, fallimenti e costi aggiuntivi sono
  determinati dal provider. Mancano ancora prezzi ufficiali verificati,
  ceiling monetario multi-sessione, reporting da API e secondo provider.
  Test puri aggiunti ma NON eseguiti; nessuna nuova Action o build.

### M2 — continuous proper names in Windows speech (2026-10-27)

Windows system narration now avoids extra period pauses in recognized
titles followed by capitalized names, author initials and internal
uppercase dotted acronyms, while retaining normal sentence pauses.
Source offsets, LLM/cast and cloud character usage are unchanged.
Test cases authored but NOT executed. M2 remains ~70% and overall
~55% estimated until native Windows listening and green regression gates.
No Windows build or Actions workflow was started.
