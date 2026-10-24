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
