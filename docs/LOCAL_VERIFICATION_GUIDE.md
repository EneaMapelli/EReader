# Guida unica ai test locali — EReader (Windows)

Questo documento distingue prove automatiche, prove con libri privati,
simulazione di lettura, ONNX reale e ascolto del doppio decoder.

## Prerequisiti

Aprire PowerShell nella radice del repository, accanto a pubspec.yaml:

    git switch feature/m0-flutter-foundation
    git pull --ff-only origin feature/m0-flutter-foundation
    flutter doctor -v

Salvare prima eventuali modifiche locali. Il progetto richiede Dart
>=3.13; il workflow manuale usa Flutter 3.47.7. Flutter deve essere
nel PATH oppure FLUTTER_ROOT deve puntare alla cartella dell'SDK.

## Tutti i test locali ordinari + simulazione della lettura

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1

L'orchestratore richiama esplicitamente run-all-tests.ps1 -NoPublish,
quindi pub get, Dart format check, Flutter analyze, l'intera suite
flutter test e isolamento per file se il run globale fallisce. Prosegue
poi con una simulazione sintetica di 200 segmenti, senza ONNX reale.

Con 500 passaggi di lettura e test EPUB/PDF nella cartella privata
example/ (incluso confronto approfondito del worker EPUB):

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1 -SoakIterations 500 -IncludeCorpus -DeepCorpus

Solo regressioni audio + analisi + simulazione, senza suite completa:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1 -AudioOnly -SoakIterations 500

Sono disponibili anche -SkipSoak e -SoakIterations N (2-2000).
L'opzione -DeepCorpus implica -IncludeCorpus.

## Comandi individuali

Suite generale e report dettagliati, rigorosamente senza push:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1 -NoPublish

Regression sui due decoder, VITS e worker persistente:

    flutter test test/audio/wav_decoder_race_test.dart test/audio/sherpa_vits_engine_test.dart test/audio/sherpa_vits_session_test.dart

Soak synthetic, senza modelli/download/audio hardware:

    flutter test tool/offline_vits_soak_test.dart --dart-define=EREADER_SOAK_ITERATIONS=500

Libri nella cartella example/, analisi approfondita:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-example-corpus.ps1 -Deep

Evitare run-all-tests.ps1 senza -NoPublish: può pubblicare report
tramite git commit e git push. Evitare anche gli script di formatter
con opzioni di commit se non si intende modificare il repository.

## Modello ONNX reale: solo opt-in

Richiede una cartella voce VITS/Piper compatibile, licenza controllata
e test esplicitamente autorizzato. NON viene eseguito per impostazione
predefinita e non scarica automaticamente voci.

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-offline-voice-qualification.ps1 -SourceFolder "C:\voice-models\italian" -AcceptNativeRisk -ExerciseStop

Oppure nello stesso orchestratore:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1 -NativeVoiceSourceFolder "C:\voice-models\italian" -AcceptNativeRisk -ExerciseNativeStop

Con -RetainWav (script individuale) o -RetainNativeWav (runner
complessivo) si conservano i WAV reali di qualifica per ascolto.
NON aggiungere -PublishSummary per mantenere tutto locale.

Il benchmark ONNX CLI include l'avvio a freddo del modello. Un PASS
non certifica il worker persistente e non misura il tempo di inizio
udibile o le pause reali tra due WAV.

## Ascolto e prova manuale con app Windows gia disponibile

Senza ricompilare, aprire un eseguibile EReader precedentemente
costruito e adatto al commit da provare. Per una prova effettiva delle
nuove modifiche serve comunque un eseguibile costruito da quei sorgenti,
ma questa procedura NON avvia alcuna build.

- Leggere per almeno 20 minuti un EPUB lungo IT e uno EN.
- Ascoltare almeno 10 transizioni di frase a pari voce e velocita,
  prima con e poi senza la preparazione anticipata WAV.
- Ripetere Pause/Stop/Seek durante sintesi e preparazione. Nessuna
  vecchia voce deve ripartire spontaneamente.
- Cambiare velocita, voce, libro e dispositivo di uscita; verificare
  che il decoder preparato non riproduca una frase errata.
- Chiudere durante la riproduzione e riaprire: controllare ancore,
  ripristino e cartelle WAV residuo; provare due istanze concorrenti.
- Controllare nelle diagnostiche ONNX sintesi, P95, file riutilizzati,
  errori, memoria RSS di processo e WAV in attesa di pulizia.

Per il silenzio tra frasi serve una misurazione audio reale (registrazione
di loopback o ascolto controllato); il solo handoff al decoder non misura
il primo campione udibile. Il runner sintetico non utilizza un
dispositivo audio reale, dunque non prova la qualita o la latenza.

## Report e privacy

Il nuovo script produce per ogni fase:

    .local-test-results/local-verification/<run-id>/summary.json
    .local-test-results/local-verification/<run-id>/*.stdout.log
    .local-test-results/local-verification/<run-id>/*.stderr.log

La suite esistente produce anche:

    .local-test-results/<run-id>/summary.json
    .local-test-results/<run-id>/failures.json
    .local-test-results/example-corpus/latest.json
    .local-test-results/offline-voice-qualification/

I log raw possono includere percorsi personali o metadati di libri:
rimangono locali e sono ignorati dal git. Il runner non crea build
Windows, non attiva workflow, non effettua upload, commit o push.

Questi comandi sono stati scritti, non eseguiti in questo ambiente
GitHub-only. Segnalare i veri errori e risultati dopo l'esecuzione.


## Come farmi leggere i risultati dopo i tuoi test

Per farmi analizzare i problemi SENZA pubblicare dati personali,
puoi allegare in chat il file summary.json del run locale e il file
failures.json della suite completa, controllandone prima il contenuto.

Se invece vuoi pubblicare soltanto il report sanitizzato dell'ULTIMA
suite ordinaria nel branch GitHub, esiste uno script separato di
pubblicazione esplicita, da utilizzare soltanto dopo aver verificato
i file JSON ed esserti assicurato che non contengano informazioni
sensibili:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\publish-local-test-report.ps1

Questo script crea commit e push del solo report filtrato della suite
ordinaria; NON include i libri, i log raw, il soak o la qualifica ONNX.
verify-local.ps1 non lo esegue mai automaticamente. Se non desideri
pubblicare niente, non usarlo.

## Ripristino degli errori di compilazione del 27/10

Il vecchio log grezzo (successivamente rimosso dal branch per privacy)
includeva 19 errori reali (oltre a lint/info), quindi
`flutter analyze` NON era INFO_ONLY. Sono stati corretti cast delle
statistiche offline, StateError non const, variabile mancante per
test MP3, funzione di checkpoint dichiarata troppo tardi, stringhe
Dart interpolate involontariamente, import PreparedCastSpeech e API
`desktop_drop` 0.9.2. Il file lock delle dipendenze era ancora su
`desktop_drop` 0.8.0: **eseguire `flutter pub get`** per rigenerarlo
localmente prima di analizzare o provare la suite.

Queste modifiche sono soltanto sorgenti; nessun test Windows è stato
eseguito nell'ambiente di modifica GitHub. Il report originale resta
una misura del commit precedente e non convalida le correzioni.

## Test VITS con file temporanei su Windows

I test audio/widget utilizzano una pulizia limitata a 5 secondi con retry
sul solo percorso casuale creato dal test. Il timeout NON viene soppresso:
se un decoder/worker continua a trattenere il file, la suite registra
ancora l'errore. Le attese sul completamento I/O VITS adesso sono
limitate dal tempo effettivo (5 secondi), invece di usare solo 50–100
turni microtask, che su Windows possono finire prima dell'accesso disco.
Queste sono modifiche ai fixture di test, non un'affermazione che il
motore audio abbia già superato i test nativi.

## Pulizia dei file grezzi pubblicati accidentalmente (2026-10-28)

Il branch di sviluppo conserva solo risultati di test strutturati e
riepiloghi filtrati; i file `.log`, i wrapper `.cmd`, gli
`.exit-code` e i due dump `latest-*.txt` sono stati eliminati
dal tree Git. `.gitignore` ne previene la nuova aggiunta ordinaria.
Sul PC i log utili possono rimanere in `.local-test-results/`.
Un commit di cancellazione NON rimuove il contenuto dai commit Git
storici: non condividere i vecchi commit o gli archivi dei log.

## Preflight failure for locked Flutter native assets (2026-10-28)

The test script now recognizes Flutter setup errors such as
`Flutter failed to delete file ... build/native_assets/windows/sqlite3.dll`.
When the runner sees this blocker, it records
`environment_native_asset_lock` and stops the per-file loop: the
unattempted 106 files are recorded as **not executed**, rather than
falsely labeled compilation failures. It does **not** delete or
force-unlock DLLs, kill processes or rebuild Windows executables.
Unblock the owning process first; a single file may then be tested
with `flutter test --concurrency=1 test/audio/wav_decoder_race_test.dart`.

The VITS regression `changed speed waits for unfinished speculative
synthesis` now gates only the FIRST 'Next' synthesis attempt, avoiding
a double-complete of its `Completer` when the audible retry occurs.
This test correction needs a local rerun before being declared PASS.
