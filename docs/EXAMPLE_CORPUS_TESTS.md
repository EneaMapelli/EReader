# Test sui veri EPUB/PDF della cartella example/

Suite dedicata ai libri **solo locali** dell'utente. Non vengono caricati su GitHub e non sono necessarie copie nel repository remoto.

## Preparazione

Creare/mantenere la cartella `example/` nella radice di EReader, accanto a `pubspec.yaml`. Sono ammesse sottocartelle con file `.epub` o `.pdf`, anche con estensioni maiuscole. La suite enumera ricorsivamente fino a 100 libri da massimo 100 MiB ciascuno. Collegamenti simbolici e junction non sono accettati.

```text
EReader/
  pubspec.yaml
  example/                   ← mai pubblicata su Git
    romanzo.epub
    manuale.pdf
    sottocartella/
      altro.EPUB
```

## Avvio Windows

Dalla radice del repository con Flutter installato:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-example-corpus.ps1
```

Per effettuare anche il confronto approfondito dell'EPUB tra il decoder del lettore e il worker di preparazione in background:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-example-corpus.ps1 -Deep
```

È possibile utilizzare direttamente Flutter, senza lo script:

```powershell
flutter test --dart-define=EREADER_EXAMPLE_CORPUS=true test/local_example_corpus_test.dart
flutter test --dart-define=EREADER_EXAMPLE_CORPUS=true --dart-define=EREADER_EXAMPLE_DEEP=true test/local_example_corpus_test.dart
```

La suite è **disattivata per impostazione predefinita** nei normali test e in `tool/run-all-tests.ps1`. I test sui libri personali devono essere avviati deliberatamente usando le opzioni indicate.

## Verifiche eseguite su ogni file

**EPUB:** verifica della firma e dei limiti tramite la vera procedura di importazione; identificativo/deduplicazione; estrazione del testo; coerenza e limiti degli intervalli spine; round-trip delle ancore a diverse posizioni; salvataggio e ripristino della posizione dopo riavvio SQLite. Il report locale indica capitoli, voci TOC, immagini, diagnostica e tempi. Con `-Deep`, controlla anche che il worker usato per la lettura/narrazione produca esattamente il testo del decoder e che i segmenti non lo riscrivano.

**PDF:** importazione/deduplicazione; apertura tramite il backend nativo `pdfrx`; numero di pagine valido; estrazione del text layer, intervalli delle pagine, ancore, salvataggio e ripresa. Se il PDF contiene soltanto scansioni e manca il testo, è classificato come `scanned-or-no-text-needs-ocr`: il salvataggio della pagina visuale è comunque verificato, ma non viene finta una capacità OCR/TTS che non esiste.

Ogni test usa una **biblioteca SQLite temporanea**, senza modificare i file sorgenti nella cartella `example/`. Non vengono avviati motori vocali, LLM o API cloud.

## Risultati e privacy

```text
.local-test-results/
  example-corpus/
    latest.json                     # risultati per libro, solo locale
    YYYYMMDDTHHMMSSZ.flutter-json.log
    YYYYMMDDTHHMMSSZ.stderr.log
```

Il comando stampa in console esito, formato, nome file e durata di ogni caso. Il JSON locale riporta anche pagine, spine, dimensioni e categorie di errore. Non salva testo dei libri, password, voci o audio. I confronti EPUB non stampano gli estratti quando falliscono.

**Importante:** sia `/example/` sia `.local-test-results/` sono ignorati da Git. Lo script non esegue `git add`, `commit`, `push` o caricamenti web. Non caricare volontariamente i log privati nella cartella dei report tracciati `test-results/`.

## Come interpretare i fallimenti

Se un libro non viene aperto, viene riportato un test fallito: EPUB corrotto o fuori limite, PDF cifrato/non supportato, errore dell'estrattore, posizione non stabile oppure libreria non ripristinabile. Un PDF scannerizzato **senza** text layer non è invece un crash: compare una classificazione che identifica la necessità futura dell'OCR.

Questi test documentali non sostituiscono le prove visive del reader Flutter (impaginazione, scorrimento, zoom e selezione), né test completi di TTS/Android. I risultati sono una base riproducibile per individuare errori su libri reali.

## Controllo dei metadati automatici EPUB

Il report locale `latest.json` include ora i valori booleani
`opfAuthorDetected`, `opfSeriesDetected`, `opfLanguageDetected` e
`opfTitleDetected` per segnalare la copertura dei campi letti dal
manifest OPF. Non include i nomi degli autori, il titolo effettivo,
la lingua o il nome della serie. Un campo assente può dipendere dal
file d'origine e non deve necessariamente essere considerato un errore.

## Riconoscimento della copertina EPUB

La suite registra anche `opfCoverDetected` (`true` o `false`) per
ciascun EPUB, senza copiare né pubblicare l'immagine di copertina.
L'assenza di una copertina dichiarata nel manifest non rende il libro
illeggibile e non costituisce da sola un errore del decoder.
