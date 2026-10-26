# EReader

**EReader** è un'app Flutter local-first per leggere ebook e ascoltarli con voci sintetiche, inizialmente su **Windows e Android**. Obiettivi a lungo termine: TTS offline/cloud intercambiabile e audiolibri multi-personaggio con analisi LLM e cast vocale controllabile dall'utente.

## Stato del codice

**Prototipo iniziale M0 in sviluppo**, non una release.

Sul branch `feature/m0-flutter-foundation` sono presenti:
- Modello libri e importazione/copia locale di TXT, EPUB e PDF (limite provvisorio 100 MB).
- Biblioteca SQLite con progressi e ancore persistenti, preferenze vocali, dizionario di pronuncia e segnalibri; migrazione automatica dei precedenti schemi JSON/SQLite (fino alla versione 16).
- Estrazione TXT/EPUB in ordine OPF spine con limiti ZIP/XML e mappatura dei capitoli alle posizioni del testo; **il renderer EPUB completo e gli anchor EPUB CFI persistenti non sono ancora implementati**.
- **Renderer EPUB per paragrafi (codice, da validare):** il testo è presentato in blocchi fluidi con larghezza di lettura limitata, carattere serif, evidenziazione TTS dentro il paragrafo e tap sulle singole porzioni vocali. Intestazioni accessibili, suddivisione Unicode sicura e temi sistema/sepia/notte. Il layout XHTML/CSS resta parziale. [Specifiche](docs/EPUB_PARAGRAPH_RENDERER.md).
- **Formattazione originale EPUB (codice, da validare):** recupera grassetto, corsivo e intestazioni h1–h6 dai tag XHTML, usando intervalli verificati sul testo estratto per non alterare ancore o lettura vocale. Script, CSS, risorse esterne e stili ambigui non vengono eseguiti né indovinati. [Specifica e test](docs/EPUB_INLINE_FORMATTING.md).
- **Risorse locali EPUB (codice, da validare):** immagini PNG/JPEG incorporate con limiti di dimensione, link verso sezioni dello stesso libro e anteprime espandibili delle tabelle. Nessuna apertura di URL esterni né modifica degli offset TTS; le immagini in capitoli solo illustrati e le tabelle HTML complesse restano incomplete. [Sicurezza e limiti](docs/EPUB_EMBEDDED_CONTENT.md).
- **Navigazione EPUB per capitoli (codice, da validare):** titoli ricavati dalle intestazioni XHTML, indice navigabile, capitolo corrente e pulsanti precedente/successivo. Il salto salva un'ancora spine e mette in pausa il TTS senza avviare nuove sintesi. I segmenti vocali non attraversano i confini dello spine. Non equivale ancora a un indice EPUB3 NAV/NCX completo o a un renderer XHTML. [Specifica](docs/EPUB_CHAPTER_NAVIGATION.md).
- **Indice editoriale EPUB3 NAV / EPUB2 NCX (codice, da validare):** mostra sezioni annidate del sommario dell'editore, con precedente/successivo secondo l'indice e fallback allo spine. I riferimenti alle note consentono di aprire sezioni dello stesso libro e tornare al testo precedente senza riavviare TTS o cloud; posizioni e contenuti rimangono invariati. [Dettagli](docs/EPUB_NAV_NCX_FOOTNOTES.md).
- **Anteprima delle note EPUB (codice, da validare):** toccando un riferimento a una nota riconosciuta nello spine compare un popup testuale locale, selezionabile e scorrevole. Chiudere non cambia pagina, TTS, segnalibri o cronologia; aprire la nota completa richiede un comando separato. Note non disponibili o troppo lunghe conservano la navigazione interna quando la destinazione è supportata. [Specifiche](docs/EPUB_FOOTNOTE_PREVIEW.md).
- **Note EPUB esterne allo spine (codice, da validare):** anteprima testuale passiva di file XHTML ausiliari dichiarati nel manifest e richiamati da veri noteref. Nessun testo aggiunto al TTS, nessun offset artificiale e nessun pulsante per navigare nel libro a una posizione inesistente. [Limiti e sicurezza](docs/EPUB_AUXILIARY_FOOTNOTES.md).
- **Compatibilità note EPUB2 (codice, da validare):** supporta riferimenti in apice, classi legacy `footnote-ref`/`fnref` e note in contenitori o liste esplicitamente riconoscibili, incluse ancore `<a name>`. Il riferimento viene promosso a nota solo se anche la destinazione è verificata; niente falsi offset TTS né accesso a risorse non dichiarate. [Specifica](docs/EPUB2_LEGACY_FOOTNOTES.md).
- **Codifiche EPUB legacy e XHTML non convenzionale (codice, da validare):** UTF‑8 rigoroso, UTF‑16 LE/BE e Windows‑1252/ISO‑8859‑1 solo se dichiarati; BOM, metadati incompatibili e sequenze errate vengono verificati, non indovinati. Le interruzioni `<br>` con attributi sono normalizzate con le stesse regole per testo TTS, formattazione e link. [Specifiche e casi di prova](docs/EPUB_CHARACTER_ENCODING.md).
- **Diagnostica EPUB e controllo ancore (codice, da validare):** indica nel lettore le risorse opzionali scartate (immagini, link, note, indice editore) senza bloccare il testo. Prima dell'uso verifica che capitoli, collegamenti e riferimenti TTS siano coerenti con gli offset UTF‑16 originali; ancore duplicate, fuori range o in mezzo a un emoji sono rifiutate. [Dettagli](docs/EPUB_IMPORT_DIAGNOSTICS.md).
- **Ripresa EPUB dopo aggiornamenti del parser (codice, da validare):** le nuove ancore salvano due impronte locali SHA-256 del contesto testuale, senza salvare estratti del libro. Se cambia la suddivisione dei paragrafi, una posizione viene recuperata solo quando la corrispondenza nello stesso capitolo è univoca; riprese e segnalibri ambigui vengono segnalati, non spostati arbitrariamente. Le ancore SQLite v1 rimangono compatibili. [Specifiche](docs/EPUB_PROGRESS_RECOVERY.md).
- **Ottimizzazione EPUB voluminosi (codice, da validare):** evita copie temporanee di interi capitoli e la creazione anticipata delle stringhe di tutti i paragrafi; le porzioni visibili ricavano il testo originale dagli offset UTF‑16 solo quando richiesto. Tabelle/immagini ricreano solo i blocchi interessati, capitoli e segmenti usano ricerche binarie, le note usano lookup indicizzati e il recupero delle ancore SHA-256 calcola la seconda impronta solo sui candidati compatibili. [Limiti e stress test](docs/EPUB_LARGE_BOOK_PERFORMANCE.md).
- **Rendering EPUB realmente progressivo (codice, da validare):** il lettore indicizza solo gli intervalli dei paragrafi all'apertura e ricostruisce formattazione, link, immagini, tabelle e note **quando il paragrafo viene visualizzato**. Una cache LRU limitata a 48 blocchi evita di conservare tutte le strutture visive di libri con migliaia di paragrafi; l'indice editoriale apre direttamente vicino al capitolo corrente. [Design e test di confronto](docs/EPUB_PROGRESSIVE_LAYOUT.md).
- **Apertura EPUB in background (codice, da validare):** la decompressione ZIP, l'analisi XHTML, la segmentazione TTS iniziale e i confini dei paragrafi vengono preparati in un isolate Dart separato dal thread dell'interfaccia. File oltre la quota ZIP vengono rifiutati prima di allocarne i byte; ancore e ID di capitoli sono indicizzati per letture e riprese veloci. [Architettura e test](docs/EPUB_BACKGROUND_PREPARATION.md).
- **Annullamento EPUB e tempi di apertura (codice, da validare):** chiusura del lettore o nuovi caricamenti terminano l'isolate EPUB superato e impediscono ai risultati vecchi di sostituire il lettore attivo. Il pulsante prestazioni mostra in locale i tempi delle singole fasi di estrazione, segmentazione e configurazione vocale, senza salvare il testo del libro o fare telemetria. [Dettagli e test](docs/EPUB_CANCELLATION_TIMINGS.md).
- Visualizzazione PDF tramite `pdfrx` e modalità sperimentale di lettura vocale per PDF con testo selezionabile (senza garanzia sull'ordine di colonne, note e tabelle).
- **Ripresa visuale dei PDF, anche scansionati (codice, da validare):** salva per libro la pagina visualizzata e la ripristina alla riapertura, indipendentemente dalla posizione TTS. Migrazione SQLite v15; nessun OCR o sincronismo a livello di riga. [Specifica e test](docs/PDF_VISUAL_RESUME.md).
- Lettura vocale con voci di sistema Windows/Android, scelta e salvataggio di voce/lingua/pitch/rate per libro e come default globale, navigazione tra segmenti e Read Along con evidenziazione, auto-scroll disattivabile e ripresa della posizione.
- **Sleep timer sessione:** stop automatico della lettura vocale dopo 10/15/30/45/60 minuti, annullabile o reimpostabile; il conteggio segue l'ora reale anche durante la pausa. Il timer non garantisce il funzionamento dopo la terminazione del processo Android.
- **Controlli media Android (codice, non ancora validato):** servizio audio con Play/Pausa/Stop/precedente/successivo in notifiche, schermata di blocco e cuffie, con pausa su chiamate/perdita focus/cuffie scollegate; mantenuto il consenso cloud anche per Play remoto. Manifest Android applicato dagli script bootstrap; Windows resta invariato. [Dettagli e limiti](docs/ANDROID_BACKGROUND_MEDIA.md).
- **Protezione transizioni TTS/Android (codice, non validato):** il player distingue una pausa effettiva dai cambi segmento/voce ancora in corso. Focus Android e checkpoint di recupero vengono rilasciati solo dopo lo stop nativo, evitando rilasci prematuri; lo sleep timer rilascia il focus anche senza comandi dalla notifica. Play remoti concorrenti sono deduplicati. [Dettagli e regressioni](docs/AUDIO_TRANSITION_SAFETY.md).
- **Timeout prudente per Stop TTS (codice, non validato):** il comando Stop attende al massimo 8 secondi per default. Se il motore non conferma l'arresto, EReader blocca ogni nuova sintesi e annulla le ripartenze automatiche; uno Stop confermato in ritardo consente solo una nuova azione Play esplicita. I checkpoint di recupero restano validi finché l'arresto è incerto. [Dettagli](docs/NATIVE_STOP_TIMEOUT.md).
- **Continua a leggere (codice, non validato):** la biblioteca ricorda l'ultimo libro aperto con SQLite v14 e mostra un accesso rapido dopo il riavvio. Recupera l'ancora sorgente già salvata; non riavvia autonomamente audio o richieste cloud, e ignora libri i cui file locali mancano.
- **Recupero TTS dopo chiusura improvvisa (codice, non validato):** checkpoint SQLite v16 scritto atomicamente con la posizione del segmento. Al riavvio un avviso consente di riaprire il libro, ma la lettura vocale non riparte e non vengono inviate richieste API prima di un nuovo Play esplicito. Pause, fine lettura e chiusure normali eliminano il checkpoint. [Dettagli](docs/NARRATION_CRASH_RECOVERY.md).
- **Gestione del ciclo di vita Android (codice, non validato):** schermo spento/background mantengono il TTS solo quando il libro possiede il media handler Android; altrimenti il TTS va in pausa. Chiusura da task manager o rimozione della notifica interrompono senza ripartenza automatica; i controlli obsoleti non possono pilotare un altro libro.
- Dizionario di pronuncia globale o per singolo libro (con anteprima), applicato soltanto al testo pronunciato e non alla copia originale.
- **Motori TTS configurabili per libro:** voci gratuite del sistema oppure OpenAI Speech tramite API HTTPS; scelta del modello e delle voci del provider. Le altre API e le voci neurali offline sono previste nelle milestone successive.
- Ricerca testuale offline all'interno del libro e segnalibri nominativi persistenti con navigazione all'ancora sorgente (EPUB spine, PDF pagina o TXT).
- **Protezione uso cloud:** chiavi conservate nello storage sicuro Windows/Android, consenso esplicito per libro, tetto locale di caratteri, possibilità di revoca e contatore consumi. Il tetto caratteri non è una garanzia di spesa massima in euro.
- **Cast vocale manuale:** anagrafica personaggi e alias, voci distinte per provider, attribuzione di interi passaggi o porzioni di testo selezionate a personaggi, e ritorno automatico alla voce narrante. Le virgolette vengono usate soltanto per separare segmenti, non per indovinare chi parla.
- **Analisi dialoghi con LLM (facoltativa):** per capitolo EPUB, pagina PDF o intervallo TXT scelto; API OpenAI Responses con chiave e consenso specifici, quota di caratteri d'ingresso e conferma dell'estratto a ogni richiesta. I suggerimenti JSON sono verificati localmente e restano inattivi fino all'approvazione manuale. Il limite spoiler predefinito è la posizione di lettura salvata; contesto precedente e nomi dei personaggi sono inclusi solo dopo una selezione esplicita. Le prove citate dal modello sono ricollegate al testo originale.
- **Continuità dei personaggi tra capitoli:** ricerca locale, disattivata di default, di brevi menzioni già conosciute negli ultimi capitoli precedenti; solo gli estratti verificati e mostrati nell'anteprima vengono opzionalmente inviati al modello, sempre entro il limite spoiler.
- **Scoperta di nuovi personaggi:** modalità AI separata che propone solo nomi letteralmente presenti nel capitolo o estratto autorizzato. I candidati restano in una coda di revisione finché l'utente non ne conferma la creazione; nessuna voce o battuta viene assegnata automaticamente.
- **Editor dettagliato dei turni di dialogo:** dalla scheda Dialogues si apre una vista locale paginata che separa battute con virgolette e trattini, interruzioni e porzioni con parlanti confermati, mancanti o in conflitto. Una battuta interamente non attribuita può essere etichettata solo dopo scelta manuale esplicita.
- **Navigazione audio robusta:** nelle richieste rapide di Play/Pausa/Seek prevale l'ultima scelta; cambi vocali nativi in corso vengono serializzati e il segmento corrente viene riavviato dopo la conferma di velocità, pitch o lingua, senza riprodurre clip obsolete.
- **Decoder MP3 preriscaldato:** quando il prebuffer cloud è attivo, un secondo player locale carica il file successivo durante l'ascolto del primo. La riproduzione resta seriale, il file è temporaneo e non ci sono nuove chiamate API; la continuità perfetta non è ancora garantita.
- **Prebuffering cloud facoltativo:** durante l'ascolto puoi preparare in anticipo un solo successivo chunk MP3 di OpenAI, dopo che il chunk corrente è pronto. Disattivato di default perché l'anticipo può consumare quota anche se poi salti la battuta; nessuna promessa di audio gapless.
- **Continuità vocale tra chunk TTS:** le attribuzioni manuali precise e legacy vengono risolte su intervalli verificati del libro, anche quando una stessa battuta attraversa più segmenti. I frammenti consecutivi con la stessa voce nella stessa citazione sono riuniti fino a 400 caratteri senza attraversare i confini narratore/personaggio.
- **Diagnostica dei dialoghi complessi:** scheda Dialogues con controllo locale delle battute interrotte o non chiuse, cambi di turno ravvicinati e attribuzioni vocali incomplete o in conflitto; da ciascuna battuta si può correggere manualmente una selezione precisa del testo.
- **Contesto dei dialoghi a più interlocutori:** durante la revisione dei pronomi mostra separatamente chi ha parlato nei passaggi precedenti con attribuzioni già approvate. Una battuta pronunciata non viene mai confusa con il personaggio a cui si riferisce il pronome.
- **Indizi locali sugli antecedenti:** durante la revisione di pronomi e descrizioni mostra fino a cinque menzioni precedenti verificabili di nomi, alias e riferimenti già approvati. Non seleziona mai automaticamente il referente e non modifica le voci.
- **Riferimenti indiretti ai personaggi:** quarta modalità AI per pronomi, titoli e descrizioni, con ipotesi esplicitamente revisionabili e conflitti lasciati irrisolti. L'approvazione aggiunge solo un collegamento narrativo, senza cambiare la voce di lettura.
- **Riconciliazione dei soprannomi:** una terza modalità AI suggerisce collegamenti fra appellativi citati nel testo e personaggi già noti; ogni proposta viene verificata e approvata manualmente prima di aggiungere un alias. I riferimenti ambigui non vengono fusi automaticamente.
- **Unificazione manuale dei personaggi:** anteprima e conferma per fondere due identità duplicate, trasferendo attribuzioni, alias, voci e riferimenti delle proposte AI, con risoluzione esplicita di ogni conflitto vocale e audit locale della fusione.
- **Cache MP3 privata:** stessa voce, modello e testo possono riusare audio già sintetizzato; limite di 250 MiB, pulizia manuale e alla cancellazione del libro.
- Test unitari per modelli, segmentazione, queue player, SQLite/migrazione v1-v16, pronuncia, preferenze, segnalibri, ricerca, TXT e ordine/sicurezza EPUB.
- [Workflow GitHub Actions](https://github.com/EneaMapelli/EReader/actions/workflows/manual-verify.yml) **solo manuale**, avviabile da main scegliendo il branch da verificare; Flutter 3.47.7, Android e Windows.

**Verifiche rinviate all'integrazione finale su richiesta del proprietario:** compilazione, test automatici effettivi, migrazioni SQLite reali e uso su Windows/Android. Gli ambienti Flutter/Dart e i toolchain Windows/Android non erano disponibili nel contesto di sviluppo. Le cartelle native `android/` e `windows/` devono ancora essere generate e versionate dopo il bootstrap.

## Test completi Windows e report automatici (branch unico)

Per eseguire analisi statica, formattazione non distruttiva e **tutti i
test Flutter**, usando il branch di sviluppo e pubblicando automaticamente
gli esiti filtrati nello stesso repository privato:

```powershell
git switch feature/m0-flutter-foundation
git pull --ff-only origin feature/m0-flutter-foundation
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1
```

Al termine, i nuovi risultati sono consultabili in
[`test-results/latest.md`](test-results/latest.md) e
[`test-results/latest.json`](test-results/latest.json), con esiti per
singolo test, cronologia e posizioni degli eventuali errori di compilazione.
Lo script pubblica i report anche se i test falliscono. I log completi
restano **esclusivamente sul PC** in `.local-test-results/`, esclusa da Git.

**Non crea altri branch, non sovrascrive commit altrui e non esegue build.**
Un push rifiutato da Git lascia i risultati locali per una pubblicazione
sicura successiva. Per istruzioni e opzioni: [Windows test runner e
report automatici](test-results/README.md).

## Test utente Windows — versione EXE portatile

Per provare l'app senza installare Flutter sul PC di test, usa
preferibilmente la [sezione Releases](https://github.com/EneaMapelli/EReader/releases):
dopo ogni compilazione riuscita, il workflow pubblica una prerelease
`windows-test-<sha>` con lo ZIP `EReader-Windows-x64-<sha>.zip`
direttamente sotto **Assets**. Estrai quello ZIP e avvia `ereader.exe`
tenendo DLL e cartella `data/` assieme. La prerelease è privata e non
modifica `main`. Se non è ancora disponibile una nuova prerelease,
puoi usare la procedura alternativa di GitHub Actions:

1. Apri [Windows portable build](https://github.com/EneaMapelli/EReader/actions/workflows/windows-user-build.yml) e scegli l'ultima esecuzione **riuscita** sul branch `feature/m0-flutter-foundation`.
2. Scarica l'artefatto `EReader-Windows-x64-portable` (visibile nella sezione **Artifacts** della run con accesso al repo privato).
3. Estrai lo ZIP scaricato da GitHub; al suo interno trovi un secondo ZIP `EReader-Windows-x64-<commit>.zip`. Estrai **anche quello**: contiene `ereader.exe`, le DLL e `data/`. Avvia `ereader.exe` mantenendo tutti i file nella stessa cartella.
4. Verifica il commit compilato in `BUILD_INFO.txt` e segui la [checklist manuale Windows](docs/WINDOWS_USER_TEST_CHECKLIST.md).

La build è **unsigned**, senza installer e non ancora validata in uso reale.
Il job genera una Release Windows **senza eseguire i test automatici**,
separatamente dal precedente workflow manuale di verifica. L'artefatto
GitHub scade dopo 14 giorni.

Per generare la stessa Release sul proprio PC Windows (Flutter + Visual
Studio C++ richiesti):

```powershell
git switch feature/m0-flutter-foundation
git pull --ff-only origin feature/m0-flutter-foundation
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build-windows.ps1
```

Lo ZIP locale si trova in `.local-windows-build/releases/` (ignorata da Git).
[Guida completa all'eseguibile Windows](docs/WINDOWS_USER_TEST_BUILD.md).

## Avvio su Windows

Prerequisiti: Flutter **3.47.7** con Dart **3.13.5** (versione CI di riferimento), Android SDK per Android, Visual Studio con carico di lavoro **Desktop development with C++** per Windows, Developer Mode Windows per i plugin che creano symlink.

```powershell
git clone https://github.com/EneaMapelli/EReader.git
cd EReader
git switch feature/m0-flutter-foundation
.\tool\bootstrap.ps1
flutter run -d windows
```

Il bootstrap esegue `flutter create --platforms=windows,android .`, `pub get`, `analyze`, `test`. Su Linux è fornito `bash tool/bootstrap.sh` (non può compilare Windows senza host appropriato). Per Android avviare dispositivo/emulatore e usare `flutter run -d <device-id>`.

**Attenzione:** una versione minima del sistema operativo e i requisiti di compilazione dipendono da Flutter e dai plugin; l'M0 serve a verificare compatibilità, licenze e tempi reali.

## Architettura

- `lib/domain/`: modello libri e segmenti UTF-16.
- `lib/data/`: biblioteca SQLite e decoder (TXT/EPUB/PDF testuale).
- `lib/audio/`: interfaccia TTS + adapter OS e player.
- `lib/features/library/`, `lib/features/reader/`: schermate Flutter.
- `test/`: unit test senza engine TTS reale.
- `docs/IMPLEMENTATION_STATUS.md`: matrice implementato/parziale/mancante e controlli da eseguire.

## Roadmap approvata

- [Decisione di approvazione e stato](docs/DECISIONS.md)
- [Piano generale](docs/DEVELOPMENT_PLAN.md)
- [Navigazione EPUB per capitoli e continuità delle ancore/TTS](docs/EPUB_CHAPTER_NAVIGATION.md)
- [Renderer EPUB per paragrafi, temi di lettura e sincronizzazione TTS](docs/EPUB_PARAGRAPH_RENDERER.md)
- [Formattazione EPUB originale: corsivo, grassetto e titoli XHTML](docs/EPUB_INLINE_FORMATTING.md)
- [Immagini EPUB locali, link interni e anteprime delle tabelle](docs/EPUB_EMBEDDED_CONTENT.md)
- [Indice editoriale EPUB3 NAV / EPUB2 NCX e ritorno dalle note](docs/EPUB_NAV_NCX_FOOTNOTES.md)
- [Anteprima popup delle note EPUB senza modificare la lettura](docs/EPUB_FOOTNOTE_PREVIEW.md)
- [Note EPUB ausiliarie fuori dallo spine: anteprime locali sicure](docs/EPUB_AUXILIARY_FOOTNOTES.md)
- [Compatibilità note EPUB2 legacy: verifica incrociata di riferimenti e destinazioni](docs/EPUB2_LEGACY_FOOTNOTES.md)
- [Codifiche EPUB: UTF-8, UTF-16, Windows-1252/Latin-1 e XHTML `<br>`](docs/EPUB_CHARACTER_ENCODING.md)
- [Diagnostica EPUB, avvisi di compatibilità e verifica integrità delle ancore](docs/EPUB_IMPORT_DIAGNOSTICS.md)
- [Recupero delle posizioni EPUB con fingerprint del contesto e retrocompatibilità v1/v2](docs/EPUB_PROGRESS_RECOVERY.md)
- [Prestazioni su EPUB molto lunghi, caricamento per paragrafi e stress test](docs/EPUB_LARGE_BOOK_PERFORMANCE.md)
- [Rendering EPUB progressivo con cache LRU limitata e indici di paragrafi](docs/EPUB_PROGRESSIVE_LAYOUT.md)
- [Apertura EPUB in background, ZIP con budget e ancore indicizzate](docs/EPUB_BACKGROUND_PREPARATION.md)
- [Annullamento worker EPUB, protezione dai caricamenti precedenti e tempi locali](docs/EPUB_CANCELLATION_TIMINGS.md)
- [Ripresa EPUB verificata nel worker annullabile con checkpoint anti-race](docs/EPUB_BACKGROUND_PROGRESS_RECOVERY.md)
- [Campionamento locale dei frame EPUB durante lo scorrimento](docs/EPUB_FRAME_SAMPLING.md)
- [Serializzazione Stop e prebuffer MP3 per decoder nativi](docs/MP3_DECODER_STOP_SERIALIZATION.md)
- [Architettura tecnica](docs/TECHNICAL_ARCHITECTURE.md)
- [Casting dei personaggi e attribuzione dei dialoghi](docs/VOICE_CASTING_SPEC.md)
- [Implementazione e test](docs/IMPLEMENTATION_STATUS.md)
- [Provider TTS, sicurezza, privacy e cache](docs/TTS_PROVIDER_INTEGRATION.md)
- [Casting manuale, voci e attribuzioni](docs/MANUAL_CASTING_IMPLEMENTATION.md)
- [Selezione precisa dei dialoghi e protocollo di revisione LLM](docs/CAST_SPAN_PROTOCOL.md)
- [Analisi dialoghi LLM, consenso per libro e API Responses](docs/LLM_DIALOGUE_ANALYSIS.md)
- [Contesto verificato dei personaggi dai capitoli precedenti](docs/HISTORICAL_CHARACTER_CONTEXT.md)
- [Revisione dei riferimenti indiretti: pronomi e titoli](docs/INDIRECT_CHARACTER_REFERENCES.md)
- [Indizi locali sugli antecedenti per la disambiguazione manuale](docs/LOCAL_ANTECEDENT_CUES.md)
- [Interlocutori confermati vs riferimenti narrativi](docs/CONVERSATION_SPEAKER_CONTEXT.md)
- [Revisione dei dialoghi complessi e battute interrotte](docs/COMPLEX_DIALOGUE_REVIEW.md)
- [Editor dettagliato e paginato dei turni di dialogo](docs/COMPLEX_DIALOGUE_TURNS.md)
- [Continuità delle voci nelle battute TTS spezzate in più chunk](docs/CROSS_CHUNK_TTS_CASTING.md)
- [Prebuffering cloud a un chunk e gestione prudente della quota](docs/CLOUD_TTS_PREFETCH.md)
- [Decoder MP3 doppio e preparazione locale del prossimo file](docs/MP3_DECODER_PRELOAD.md)
- [Sicurezza delle sessioni TTS: Play, Pausa, Seek, voce e velocità](docs/PLAYBACK_SESSION_SAFETY.md)
- [Controlli media Android, focus e servizio in background](docs/ANDROID_BACKGROUND_MEDIA.md)
- [Transizioni TTS, focus Android e salvataggi solo dopo lo stop effettivo](docs/AUDIO_TRANSITION_SAFETY.md)
- [Timeout Stop nativo TTS, blocco prudente e test](docs/NATIVE_STOP_TIMEOUT.md)
- [Ripristino libro recente, lifecycle e arresto sessione](docs/SESSION_RESUME_AND_LIFECYCLE.md)
- [Recupero checkpoint di narrazione dopo chiusure improvvise](docs/NARRATION_CRASH_RECOVERY.md)
- [Ripresa pagina visuale PDF e separazione dalla posizione TTS](docs/PDF_VISUAL_RESUME.md)
- [Riconoscimento assistito di nuovi personaggi e revisione](docs/CHARACTER_DISCOVERY.md)
- [Riconciliazione alias, soprannomi e identità](docs/ALIAS_RECONCILIATION.md)
- [Unificazione manuale di due personaggi e conservazione delle attribuzioni](docs/CAST_IDENTITY_MERGE.md)

Priorità di sviluppo funzionale (senza bloccare ogni incremento sulla compilazione): M0 fondazione tecnica, M1 lettore completo, M2 TTS/read-along, M3 provider avanzati e cloud, M4 cast manuale, M5 LLM multi-personaggio, M6 release. **Nessuna milestone è dichiarata validata o pronta per la distribuzione prima dei test finali.**

## Privacy e licenza

Per impostazione predefinita l'app funziona in locale. L'utente può configurare volontariamente chiavi OpenAI e approvare **separatamente** l'invio di singoli estratti del libro per TTS oppure analisi LLM; **nessuna richiesta cloud è consentita in assenza del relativo consenso per quello specifico libro**. Il codice cloud non è ancora stato collaudato con chiavi reali. I libri e gli MP3 generati vengono conservati in una directory privata dell'app. EPUB DRM non supportati. Licenza del progetto [MIT](LICENSE); i modelli vocali e i pacchetti di terze parti mantengono licenze autonome.

### Segmentazione più naturale nei dialoghi (M2)

Il separatore deterministico delle frasi ora riconosce anche la
punteggiatura di fine frase seguita da virgolette e parentesi di chiusura,
per esempio `«Ciao!» Poi…`. Questo riduce le divisioni innaturali
durante la lettura vocale, senza modificare gli offset UTF-16 del libro,
le voci attribuite ai personaggi, i limiti TTS o il consenso cloud.
[Dettagli e test](docs/SPEECH_SENTENCE_BOUNDARIES.md). La modifica
richiede ancora una verifica locale aggiornata.
