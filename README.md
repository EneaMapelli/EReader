# EReader

**EReader** è un'app Flutter local-first per leggere ebook e ascoltarli con voci sintetiche, inizialmente su **Windows e Android**. Obiettivi a lungo termine: TTS offline/cloud intercambiabile e audiolibri multi-personaggio con analisi LLM e cast vocale controllabile dall'utente.

## Stato del codice

**Prototipo iniziale M0 in sviluppo**, non una release.

Sul branch `feature/m0-flutter-foundation` sono presenti:
- Modello libri e importazione/copia locale di TXT, EPUB e PDF (limite provvisorio 100 MB).
- Biblioteca SQLite con progressi e ancore persistenti, preferenze vocali, dizionario di pronuncia e segnalibri; migrazione automatica dei precedenti schemi JSON/SQLite (fino alla versione 13).
- Estrazione TXT/EPUB in ordine OPF spine con limiti ZIP/XML e mappatura dei capitoli alle posizioni del testo; **il renderer EPUB completo e gli anchor EPUB CFI persistenti non sono ancora implementati**.
- Visualizzazione PDF tramite `pdfrx` e modalità sperimentale di lettura vocale per PDF con testo selezionabile (senza garanzia sull'ordine di colonne, note e tabelle).
- Lettura vocale con voci di sistema Windows/Android, scelta e salvataggio di voce/lingua/pitch/rate per libro e come default globale, navigazione tra segmenti e Read Along con evidenziazione, auto-scroll disattivabile e ripresa della posizione.
- Dizionario di pronuncia globale o per singolo libro (con anteprima), applicato soltanto al testo pronunciato e non alla copia originale.
- **Motori TTS configurabili per libro:** voci gratuite del sistema oppure OpenAI Speech tramite API HTTPS; scelta del modello e delle voci del provider. Le altre API e le voci neurali offline sono previste nelle milestone successive.
- Ricerca testuale offline all'interno del libro e segnalibri nominativi persistenti con navigazione all'ancora sorgente (EPUB spine, PDF pagina o TXT).
- **Protezione uso cloud:** chiavi conservate nello storage sicuro Windows/Android, consenso esplicito per libro, tetto locale di caratteri, possibilità di revoca e contatore consumi. Il tetto caratteri non è una garanzia di spesa massima in euro.
- **Cast vocale manuale:** anagrafica personaggi e alias, voci distinte per provider, attribuzione di interi passaggi o porzioni di testo selezionate a personaggi, e ritorno automatico alla voce narrante. Le virgolette vengono usate soltanto per separare segmenti, non per indovinare chi parla.
- **Analisi dialoghi con LLM (facoltativa):** per capitolo EPUB, pagina PDF o intervallo TXT scelto; API OpenAI Responses con chiave e consenso specifici, quota di caratteri d'ingresso e conferma dell'estratto a ogni richiesta. I suggerimenti JSON sono verificati localmente e restano inattivi fino all'approvazione manuale. Il limite spoiler predefinito è la posizione di lettura salvata; contesto precedente e nomi dei personaggi sono inclusi solo dopo una selezione esplicita. Le prove citate dal modello sono ricollegate al testo originale.
- **Continuità dei personaggi tra capitoli:** ricerca locale, disattivata di default, di brevi menzioni già conosciute negli ultimi capitoli precedenti; solo gli estratti verificati e mostrati nell'anteprima vengono opzionalmente inviati al modello, sempre entro il limite spoiler.
- **Scoperta di nuovi personaggi:** modalità AI separata che propone solo nomi letteralmente presenti nel capitolo o estratto autorizzato. I candidati restano in una coda di revisione finché l'utente non ne conferma la creazione; nessuna voce o battuta viene assegnata automaticamente.
- **Editor dettagliato dei turni di dialogo:** dalla scheda Dialogues si apre una vista locale paginata che separa battute con virgolette e trattini, interruzioni e porzioni con parlanti confermati, mancanti o in conflitto. Una battuta interamente non attribuita può essere etichettata solo dopo scelta manuale esplicita.
- **Prebuffering cloud facoltativo:** durante l'ascolto puoi preparare in anticipo un solo successivo chunk MP3 di OpenAI, dopo che il chunk corrente è pronto. Disattivato di default perché l'anticipo può consumare quota anche se poi salti la battuta; nessuna promessa di audio gapless.
- **Continuità vocale tra chunk TTS:** le attribuzioni manuali precise e legacy vengono risolte su intervalli verificati del libro, anche quando una stessa battuta attraversa più segmenti. I frammenti consecutivi con la stessa voce nella stessa citazione sono riuniti fino a 400 caratteri senza attraversare i confini narratore/personaggio.
- **Diagnostica dei dialoghi complessi:** scheda Dialogues con controllo locale delle battute interrotte o non chiuse, cambi di turno ravvicinati e attribuzioni vocali incomplete o in conflitto; da ciascuna battuta si può correggere manualmente una selezione precisa del testo.
- **Contesto dei dialoghi a più interlocutori:** durante la revisione dei pronomi mostra separatamente chi ha parlato nei passaggi precedenti con attribuzioni già approvate. Una battuta pronunciata non viene mai confusa con il personaggio a cui si riferisce il pronome.
- **Indizi locali sugli antecedenti:** durante la revisione di pronomi e descrizioni mostra fino a cinque menzioni precedenti verificabili di nomi, alias e riferimenti già approvati. Non seleziona mai automaticamente il referente e non modifica le voci.
- **Riferimenti indiretti ai personaggi:** quarta modalità AI per pronomi, titoli e descrizioni, con ipotesi esplicitamente revisionabili e conflitti lasciati irrisolti. L'approvazione aggiunge solo un collegamento narrativo, senza cambiare la voce di lettura.
- **Riconciliazione dei soprannomi:** una terza modalità AI suggerisce collegamenti fra appellativi citati nel testo e personaggi già noti; ogni proposta viene verificata e approvata manualmente prima di aggiungere un alias. I riferimenti ambigui non vengono fusi automaticamente.
- **Unificazione manuale dei personaggi:** anteprima e conferma per fondere due identità duplicate, trasferendo attribuzioni, alias, voci e riferimenti delle proposte AI, con risoluzione esplicita di ogni conflitto vocale e audit locale della fusione.
- **Cache MP3 privata:** stessa voce, modello e testo possono riusare audio già sintetizzato; limite di 250 MiB, pulizia manuale e alla cancellazione del libro.
- Test unitari per modelli, segmentazione, queue player, SQLite/migrazione v1-v13, pronuncia, preferenze, segnalibri, ricerca, TXT e ordine/sicurezza EPUB.
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
- [Riconoscimento assistito di nuovi personaggi e revisione](docs/CHARACTER_DISCOVERY.md)
- [Riconciliazione alias, soprannomi e identità](docs/ALIAS_RECONCILIATION.md)
- [Unificazione manuale di due personaggi e conservazione delle attribuzioni](docs/CAST_IDENTITY_MERGE.md)

Priorità di sviluppo funzionale (senza bloccare ogni incremento sulla compilazione): M0 fondazione tecnica, M1 lettore completo, M2 TTS/read-along, M3 provider avanzati e cloud, M4 cast manuale, M5 LLM multi-personaggio, M6 release. **Nessuna milestone è dichiarata validata o pronta per la distribuzione prima dei test finali.**

## Privacy e licenza

Per impostazione predefinita l'app funziona in locale. L'utente può configurare volontariamente chiavi OpenAI e approvare **separatamente** l'invio di singoli estratti del libro per TTS oppure analisi LLM; **nessuna richiesta cloud è consentita in assenza del relativo consenso per quello specifico libro**. Il codice cloud non è ancora stato collaudato con chiavi reali. I libri e gli MP3 generati vengono conservati in una directory privata dell'app. EPUB DRM non supportati. Licenza del progetto [MIT](LICENSE); i modelli vocali e i pacchetti di terze parti mantengono licenze autonome.
