# EReader — Piano di sviluppo Windows + Android

**Versione:** 1.0 · **Data:** 2026-10-22 · **Stato:** proposta iniziale approvabile per implementazione  
**Repository:** [EneaMapelli/EReader](https://github.com/EneaMapelli/EReader) · **Branch:** main

## 1. Visione e risultato atteso

Realizzare un lettore di ebook multipiattaforma (Windows e Android) che combini lettura visuale, riproduzione TTS gratuita/offline oppure via API a pagamento e, facoltativamente, una modalità di *narrazione multi-personaggio*. Quest'ultima analizza il libro con un LLM, costruisce un catalogo dei personaggi, attribuisce le battute e assegna voci coerenti. L'utente deve poter verificare e correggere ogni associazione.

**Principi:** local-first; nessun account o server obbligatorio; nessuna spesa di API senza opt-in; progressivo miglioramento senza bloccare la lettura; architettura estendibile per formati, motori TTS e modelli LLM; accessibilità e protezione della privacy per impostazione predefinita.

### 1.1 Utenti e casi d'uso prioritari

1. Importo un EPUB/PDF, leggo con layout personalizzabile, riprendo dalla posizione precedente.
2. Avvio lettura ad alta voce senza chiavi API, scegliendo una voce di sistema o un modello locale scaricato.
3. Configuro un provider cloud (OpenAI, Azure, ElevenLabs, ecc.), una voce, un budget; vedo stima e consuntivo dei costi.
4. Scelgo «voci dei personaggi», effettuo uno screening iniziale configurabile e approvo/correggo il cast; la narrazione mantiene una voce per personaggio anche nei capitoli successivi.
5. Posso usare un LLM locale per preservare la riservatezza o uno remoto solo previa autorizzazione specifica.
6. Passo tra testo e audio preservando la posizione; uso controlli di riproduzione, timer e audio in background dove supportato.

## 2. Piattaforme, stack e convenzioni

- **UI:** Flutter/Dart, codebase unica Windows (x64 prima) e Android (arm64 prima). Layout responsive con navigazione da mouse/tastiera e touchscreen.
- **Persistenza:** SQLite con migrazioni e repository layer; file importati nella sandbox dell'app o referenziati con permessi persistenti; metadati con percorsi relativi e ID stabili.
- **Documenti:** EPUB con parser Dart (valutare \`epubx\` e compatibilità EPUB 2/3), visualizzatore XHTML sanitizzato; PDF con motore PDFium tramite \`pdfrx\` dopo POC su estrazione testo e coordinate; TXT come formato semplice di avvio. Nessun singolo viewer deve possedere la logica TTS.
- **TTS locale base:** adapter dei motori di sistema tramite \`flutter_tts\`, con verifica delle capacità voce/pausa/progress per piattaforma.
- **TTS neurale offline:** adapter \`sherpa_onnx\` con modelli ONNX/Piper compatibili, installabili separatamente; selezionare voci/licenze modello per modello.
- **Audio:** pipeline PCM/audio file/stream con riproduzione sequenziale e prefetch; soluzione player Flutter da qualificare per background Android, media session, notifiche e cuffie.
- **LLM:** interfaccia provider-agnostica; remoto (es. OpenAI o endpoint API compatibili) e locale opzionale (runtime da validare per RAM/CPU/ABI). Output JSON validato da schema; nessuna inferenza remota implicita.
- **Qualità:** unit/component/integration test + smoke test *reali* su Windows e Android, pipeline CI manuale all'inizio e automatizzata solo dopo stabilizzazione se desiderata.

## 3. Formati supportati

| Formato | Priorità | Lettura visuale | TTS | Vincoli |
|---|---|---|---|---|
| EPUB 2/3 non-DRM | MVP | Layout rifluibile, TOC, immagini | Sì, da spine XHTML | CSS complessi, footnote, reading order, CFI da testare |
| PDF con text layer | MVP | Pagina fedele, zoom, ricerca | Sì, ordine estratto da correggere | Colonne, note, formule, testo ripetuto |
| TXT UTF-8/encodings comuni | MVP | Reflow | Sì | Rilevazione encoding |
| HTML/Markdown locali | Dopo MVP | Reflow sanitizzato | Sì | Link/risorse esterne bloccati di default |
| FB2, DOCX | V1 | Reflow via adapter | Sì | Validazione librerie, immagini e note |
| MOBI/AZW3 senza DRM | V1/V2 | Import/convertitore *opzionale* | Sì dopo conversione | Licensing e fattibilità tecnica da verificare |
| PDF scannerizzato | V2 | Pagine | Solo dopo OCR opzionale | Lingue, accuratezza, consumi |
| CBZ/CBR fumetti | V2 | Immagini | Solo con OCR | CBR e tool di estrazione richiedono verifica |
| EPUB/PDF protetti da DRM | Fuori scope iniziale | No bypass DRM | No | Rispettare diritti e licenze |

Il successo dei vari formati va misurato su un corpus di test, non dedotto dal semplice riconoscimento dell'estensione.

## 4. Requisiti funzionali

### 4.1 Biblioteca e lettore
- Import via selezione file, condivisione Android e drag & drop Windows; validazione formato/MIME, dimensioni, file ZIP e percorsi interni.
- Copertina, titolo, autore, lingua, serie, dimensione, data import, ricerca, ordinamento; duplicati con hash file.
- Testo: font, dimensioni, margini, interlinea, tema chiaro/scuro/sepia, pagina/scroll, indice, note, evidenziazioni, segnalibri e ricerca.
- PDF: navigazione pagine, zoom, selezione, indicazione di testo non disponibile e fallback audio quando non si può estrarre.
- Ripresa esatta della posizione: EPUB tramite anchor/CFI o identificatori stabili della spine; PDF tramite pagina+offset testo/coordinate; TXT via offset.
- Focus accessibile, controlli tastiera e screen reader; lingua della sintesi auto da metadata o configurazione manuale.

### 4.2 Player TTS
- Play, pausa, stop, seek per unità testuale, salta frase/paragrafo/capitolo, velocità e volume, sleep timer.
- Evidenziazione testo durante lettura: granularità parola **solo dove il motore restituisce timing affidabili**, altrimenti frase/paragrafo.
- Separare \`SpeechProvider\` da \`AudioPlayback\`: l'uno produce stream/file o controlla TTS di sistema; l'altro gestisce buffering/riproduzione dove possibile.
- Stessa interfaccia per TTS di sistema, sintetizzatore offline e provider remoto; esporre capacità per evitare controlli fittizi.
- Prefetch delimitato, cache su disco configurabile, LRU, pulizia e invalidazione selettiva; in caso di errore remoto, retry con backoff e fallback locale **solo previo consenso all'eventuale cambio voce**.
- Lettura a schermo spento su Android, gestione audio focus/cuffie/chiamate, ripresa della sessione e controlli Media Session; Windows media keys da verificare.

### 4.3 Configurazione TTS e LLM
- Provider TTS e modello configurabili globalmente, per libro e per singola voce personaggio; anteprima prima dell'applicazione.
- Voce/base voice ID, lingua, velocità, pitch, volume, stile/emozione, eventuale SSML e seed **solo se supportati** dal provider.
- TTS indipendente dal provider LLM (es. LLM locale + TTS cloud; LLM cloud + TTS locale).
- API key gestite in storage sicuro OS (Android Keystore, Windows Credential Manager/DPAPI tramite integrazione verificata); mai nel DB o nei log in chiaro.
- Prezzi da configurare/aggiornare, stimatore prima dell'elaborazione, budget per libro/sessione/mese, rate limiting e avviso di esaurimento; nessuna richiesta a pagamento se budget non autorizzato.
- Sui servizi cloud: consenso esplicito all'invio dei *passaggi testuali* ed eventualmente dei metadati; indicare provider, dati e costi prima dell'avvio.
- UI di provenienza audio sintetico e verifica dei termini d'uso dei fornitori.

## 5. Modalità lettura intelligente: analisi iniziale e cast vocale

Modalità **facoltativa**: OFF (voce unica), CAST MANUALE (l'utente etichetta le battute), CAST ASSISTITO (LLM produce proposte, utente rivede).

1. **Normalizzazione:** testo estratto, suddivisione in capitoli/paragrafi/frasi con anchor che risalgono alla sorgente; conservare dialoghi, virgolette, trattini, lingua e corsivi.
2. **Screening iniziale:** campionamento capitoli introduttivi o scansione completa opzionale; pipeline gerarchica per libri lunghi (capitoli > aggregazione), con limiti token/costo e capacità di ripresa. Profilazione spoiler-safe (mostrare solo personaggi incontrati fino alla posizione di lettura, se scelto).
3. **Entità:** ID canonici, alias, nome, pronomi e genere *se esplicitamente supportati dal testo*, indizi contestuali, età apparente/timbro/ritmo/tratti vocali descritti, relazioni, confidenza e fonti con anchor. Non inferire automaticamente il sesso o il genere da nomi o stereotipi.
4. **Dialoghi:** identificare intervalli testuali esatti e speaker probabile; supportare monologhi, discorso indiretto, citazioni dentro citazioni, dialoghi senza tag, speaker multipli e capitoli con POV variabile.
5. **Attribuzione:** confidenza >= 0,85 assegnazione proposta, 0,60–0,85 revisione suggerita, < 0,60 mantenere narratore/non attribuito (soglie iniziali tarabili su test). Verificare coerenza e assenza di sovrapposizioni; permettere correzioni in batch.
6. **Casting:** ogni personaggio ottiene \`VoiceProfile\` persistente: provider/model/voice ID, lingua, pitch, rate, volume, stile, eventuale prompt prosodico. Proposta da caratteristiche narrate, non solo da sesso/genere; priorità a voce nativa appropriata, pitch moderato solo per rifinitura.
7. **Sintesi:** narratore per testo non dialogato; battuta del personaggio con voice profile; segnali di emozione opzionali per *battuta*, non sostitutivi dell'identità; pause e mix normalizzati.
8. **Persistenza/edit:** modifica ID/alias/personaggio, profilo voce, singola attribuzione; annullamento, rigenerazione **solo dei segmenti interessati**; feedback correzioni per capitoli seguenti.
9. **Aggiornamento progressivo:** personaggi introdotti tardi aggiunti senza alterare la storia già ascoltata; riconciliazione alias versionata; scene o narratori inaffidabili possono rimanere \`unknown\`.

**Garanzia fondamentale:** i segmenti da leggere derivano dal *testo originale*, non da una riscrittura LLM. Il modello restituisce solo annotazioni/ID/riferimenti. Ogni battuta non attribuita viene comunque letta dal narratore: la lettura non deve bloccarsi.

## 6. Provider e matrice capacità (obiettivo)

| Provider | Tipo | Costi | Capacità da esporre/validare |
|---|---|---|---|
| Android/Windows system TTS | Locale OS | Nessuna API; voci disponibili dipendono dal sistema | voices, language, rate, pitch; eventi posizione non equivalenti su tutte le piattaforme |
| sherpa-onnx + modelli compatibili | Offline integrabile | Nessuna API; storage/download, licenze modelli | voci modello, file PCM, multivoce se modello, CPU/RAM e velocità |
| OpenAI Realtime | Cloud BYOK | A consumo | audio session/streaming, voci abilitate, output, affidabilità di lettura verbatim |
| Azure AI Speech | Cloud BYOK | A consumo | SSML, profili vocali, pitch/rate/stile se supportati per voce |
| ElevenLabs | Cloud BYOK | A consumo | voice IDs, modelli, opzioni espressive, streaming, limiti |
| Endpoint TTS custom | Cloud/self-hosted | Dipende dal server | Contratto plugin documentato, capabilities dinamiche |

**Nota API OpenAI (verifica 2026-10-22):** \`tts-1\`, \`tts-1-hd\` e la famiglia \`gpt-4o-mini-tts\` hanno shutdown annunciato per **2027-01-06**; migrare a \`gpt-realtime-2.1-mini\` via Realtime API. **Non** inviare \`gpt-realtime-2.1-mini\` all'endpoint \`/v1/audio/speech\`, perché sono API diverse. Qualsiasi adapter Speech legacy va trattato come transitorio e disabilitato prima della dismissione. La lettura letterale e la gestione degli stream Realtime richiedono un POC specifico.

Il supporto a pitch/timbro/emozione non è uniforme. Se il provider non implementa pitch, scegliere una voce già vicina al target; un post-processing audio opzionale deve evitare artefatti, non dare per scontato che il pitch-shift simuli una differente identità vocale.

## 7. Roadmap per incrementi consegnabili

**M0 — Fondazione / spike tecnici (P0)**
- Scaffold Flutter Windows/Android; package modulari, lint, test runner, migrazioni SQLite; build locali.
- POC EPUB: spine/TOC/CFI/HTML sandbox con 3 libri reali; POC PDF: pagina > testo > anchor; POC TTS system Windows/Android e sherpa-onnx con voce italiana/inglese; POC playback Android in background.
- Licenze e dimensioni di eventuali modelli vocali; verifica Windows native assets, Android ABI e min SDK.
- **Exit:** import+render+estrazione+tasti play su entrambe le piattaforme senza servizio esterno; rischi tecnici documentati.

**M1 — Reader MVP (P0)**
- Biblioteca locale, EPUB/PDF/TXT, lettore, navigazione, indice, temi, progressi, ricerca base.
- **Exit:** 20 libri di test aperti senza crash; posizione persiste tra riavvii; rendering riproducibile su Windows e Android.

**M2 — TTS gratuito e sincronizzazione (P0)**
- Adapter TTS di sistema; voice picker; play/pause, salta, velocità, progress per frase/paragrafo; foreground/background Android.
- Modello comune \`TextSegment\` + \`SpeechRequest\`; buffer e recupero da interruzioni.
- **Exit:** lettura consecutiva di un capitolo, navigazione mentre parla, ripresa dopo stop/chiamata; zero configurazioni cloud necessarie.

**M3 — Offline neurale e cloud configurabile (P1)**
- sherpa-onnx e download/modellazione delle voci; registry provider, secret storage, OpenAI Realtime POC e adapter stabile, almeno un secondo provider cloud.
- Cost estimator/budget/caching e fallback; health check con sample audio.
- **Exit:** cambio provider senza riscrivere player; cost ceiling enforceable; libri non inviati in rete quando provider locale.

**M4 — Cast manuale + segmentazione dialoghi (P1)**
- Identificazione dialoghi con regole deterministiche iniziali; editor dei parlanti e dei profili vocali; supporto multivoce anche senza LLM.
- **Exit:** scena test con 3+ personaggi e narratore riprodotta con assegnazioni persistenti; segmenti non attribuiti sicuri.

**M5 — Screening LLM e casting automatico revisionabile (P1)**
- Adapter LLM locale/cloud, estrazione JSON con schema, entità/alias, attribuzione battute con confidenza e provenance, QA UI, profili da descrizioni, analisi per capitolo/full-book.
- **Exit:** gold corpus annotato; misure precision/recall per speaker, ambiguità non mascherate; non più di una lettura testuale alterata rispetto al documento per errore di segmentazione.

**M6 — Rifinitura e release (P1/P2)**
- Migliorie accessibilità, power/RAM, download e gestione cache, crash reporting opt-in, export/import backup e impostazioni, packaging MSI/MSIX + APK/AAB; documentazione.
- **Exit:** suite smoke Windows/Android reale, release candidate con inventario licenze, indicazioni privacy e guida BYOK.

**Post-MVP / backlog (P2):** OCR PDF scannerizzati, FB2/DOCX/MOBI/AZW3, sync cross-device end-to-end cifrato, audio export nei limiti delle licenze, libreria cloud/OPDS, personalizzazione dizionario pronunce, traduzione, iOS/macOS/Linux, modello LLM offline Android ottimizzato.

Le milestone non implicano date fisse: stimare durata e capacità dopo i POC di M0. Non iniziare M5 prima di avere un M2 stabile; M3 e M4 si possono sviluppare parzialmente in parallelo.

## 8. Backlog iniziale ordinato

| ID | Priorità | Deliverable | Dipendenza |
|---|---|---|---|
| ER-001 | P0 | Flutter scaffold / build Windows+Android | — |
| ER-002 | P0 | Modello \`Book/Chapter/TextSegment/Anchor\` + DB | ER-001 |
| ER-003 | P0 | Import EPUB/TXT + parsing sicuro e TOC | ER-002 |
| ER-004 | P0 | PDF rendering, estrazione e verifica ordine | ER-002 |
| ER-005 | P0 | Reader UI e progress persistence | ER-003,004 |
| ER-006 | P0 | Provider contracts + system TTS | ER-002 |
| ER-007 | P0 | Player controls e sync testo/audio | ER-005,006 |
| ER-008 | P0 | Android background audio e Windows hotkeys | ER-007 |
| ER-009 | P1 | Offline TTS sherpa-onnx + models manager | ER-006 |
| ER-010 | P1 | BYOK, vault, stime costi, budget e consenso | ER-006 |
| ER-011 | P1 | OpenAI Realtime + provider TTS cloud secondario | ER-010 |
| ER-012 | P1 | Editor cast, voci per personaggio e unknown | ER-007 |
| ER-013 | P1 | LLM analysis provider + JSON schema/provenance | ER-002 |
| ER-014 | P1 | Alias/speaker attribution/review UI | ER-012,013 |
| ER-015 | P1 | Cache audio per hash di segmenti/profili | ER-009,011,012 |
| ER-016 | P1 | QA, corpus gold e benchmark cross-platform | Tutti incrementi |

## 9. Criteri di qualità e misurazione

- **File import:** un catalogo con file validi, corrotti, ZIP bomb, caratteri speciali, EPUB RTL/Unicode, PDF due colonne, footnote, file grandi; import fallito gestito e cancellabile.
- **Fedeltà:** confronto automatico testo sorgente normalizzato vs testo inviato al TTS; 0 omissioni/duplicazioni *non giustificate* sui campioni P0. La qualità prosodica è un controllo separato.
- **Attribuzione:** corpus manuale con almeno 10 opere/libri o estratti liberamente utilizzabili e rappresentativi di generi/lingue; speaker accuracy, precision, recall, F1, coverage, unknown rate e rischio *false confident*. Definire target numerici dopo baseline annotata.
- **Qualità vocale:** ascolto cieco per lingua e provider, preservazione della distinzione tra speaker, intelligibilità, assenza di clipping, pause e pronuncia dei nomi.
- **Prestazioni:** first-page e first-audio latency, tempo generazione/minuto ascolto, throughput offline, peak RSS RAM Android, batteria, spazio modello/cache; soglie dopo dispositivi di riferimento M0.
- **Affidabilità:** test offline, perdita rete, timeout/429/5xx, key invalida, budget terminato, processo chiuso, chiamate in arrivo, riavvio, cambi voce e provider.
- **Regressione:** golden tests del mapping \`anchor ↔ segment ↔ playback\` e snapshot per versioni di parser/modello.
- **Sicurezza:** nessuna fuga di token/API keys; XHTML/ZIP/PDF malevoli isolati; nessun upload non autorizzato; controlli supply-chain e licenze dei pesi ONNX.

## 10. Rischi e mitigazioni

1. **EPUB/PDF hanno ordini di lettura complessi:** mantenere document adapters separati, golden mapping e fallback esplicito su PDF problematici.
2. **Dialoghi ambigui o narrazioni a POV multiplo:** confidence + unknown + editor; vietato riscrivere il testo; memorizzare prova e posizione.
3. **TTS non supporta pitch/emozioni/timing uniformi:** capability negotiation; filtri UI condizionali; fallback a voice IDs distinti.
4. **Cloud costoso e privacy dei libri:** stima, cap, conferma esplicita per libro e caching, BYOK, nessun backend nostro obbligatorio.
5. **Prestazioni di ONNX/LLM su Android:** download opzionale, benchmark su device economici, limite RAM, cancel/resume e offload user-controlled.
6. **DRM/licenze modelli e copyright:** non aggirare DRM, limitare estrazione a materiali leciti e uso personale; attribuire correttamente licenze modelli e dipendenze.
7. **API esterne instabili:** adapters versionati e test contrattuali; OpenAI Speech legacy in sunset a inizio 2027.
8. **Correzioni invalidano interi audiolibri:** cache per segmenti a hash, invalidate solo quando testo/profilo/provider/parametri cambiano.
9. **Voce sintetica di persone reali:** niente clonazione senza consenso del titolare della voce; usare voci commerciali consentite e disclosure AI dove prevista.

## 11. Fuori scope della prima release

DRM, vendita/hosting libri, streaming cataloghi protetti, sincronizzazione via server proprietario, clonazione di voci non autorizzate, modelli locali multi-GB obbligatori, rendering multimodale avanzato di libri illustrati, correzione automatica dei testi PDF difettosi senza revisione.

## 12. Decisioni ancora da chiudere dopo M0

- Mappatura EPUB CFI robusta con renderer usato su Windows+Android.
- Provider e runtime per LLM locale, inclusa fattibilità Android in 4–6 GB RAM.
- Licenze/dimensioni del pacchetto base e delle voci offline italiane.
- Player per audio cloud che supporti gapless, timemap e background.
- Metodo di sincronizzazione word-level per i provider che non restituiscono speech marks.
- Policy download/rimozione files importati, export audiolibro e garanzie privacy per ciascun provider.
- Target minimi device/OS basati su utenti e benchmark, non assunzioni implicite.

## 13. Documenti di approfondimento

- [Architettura tecnica](TECHNICAL_ARCHITECTURE.md): contratti adapter, data model, sequenze, configurazione.
- [Specifiche cast vocale intelligente](VOICE_CASTING_SPEC.md): schema JSON, pipeline LLM, revisioni, quality gates.

## 14. Riferimenti verificati al 2026-10-22

- Flutter, piattaforme: https://docs.flutter.dev/reference/supported-platforms
- TTS di sistema: https://pub.dev/packages/flutter_tts
- Offline TTS: https://pub.dev/packages/sherpa_onnx
- Parser EPUB: https://pub.dev/packages/epubx
- PDF viewer basato su PDFium: https://pub.dev/packages/pdfrx
- OpenAI Text to speech: https://developers.openai.com/api/docs/guides/text-to-speech
- OpenAI deprecazioni: https://developers.openai.com/api/docs/deprecations
- Azure SSML: https://learn.microsoft.com/azure/ai-services/speech-service/speech-synthesis-markup-voice
- ElevenLabs TTS: https://elevenlabs.io/docs/overview/capabilities/text-to-speech

**Nota:** librerie, modelli, disponibilità voci, licenze e prezzi devono essere bloccati/verificati al momento dell'implementazione. Questo piano descrive obiettivi e scelte candidate, non funzionalità già realizzate.


## 15. Funzionalità aggiuntive candidate — valutazione prima del codice (2026-10-22)

Queste sono **proposte di estensione**, non promesse per l'MVP. Distinguere capacità da prevedere nell'architettura fin da M0 e funzioni effettivamente da implementare negli incrementi successivi. Non spostare M1–M2 finché non esiste un lettore affidabile e TTS offline.

| ID | Feature | Priorità proposta | Implementazione candidata | Dipendenze / vincoli |
|---|---|---|---|---|
| ER-017 | **Read Along**: auto-scroll e highlight sincronizzati, switch testo/audio con resume esatto | P0, rafforzare M2 | progress anchor unico e audio timeline indipendente da provider | Word-level *solo* con marks verificabili; altrimenti frase |
| ER-018 | **Dizionario pronunce** globale/per libro/per personaggio | P1, M3–M4 | regole nome→pronuncia, IPA/SSML dove disponibili, editor e preview | Non tutti i provider espongono lessici/phonemes: fallback per voce |
| ER-019 | **Lingue miste e rilevamento lingua per segmento** | P1, M3–M5 | override lingua per libro/capitolo/frase + voice selection per lingua | Non inferire varietà linguistica affidandosi solo ai metadati |
| ER-020 | **Regia audio**: pause, cambio speaker, enfasi, loudness, stili emotivi | P1, M4–M5 | prosody marks separati da speaker, pause templates, normalizzazione audio | Interpretazioni sottili/ironia non necessariamente riconoscibili; test A/B |
| ER-021 | **Audiobook export** M4B/MP3/Opus con capitoli, copertina, resume export e stima costi | P1/P2, M6 | job queue separata dal player; segmenti in cache ricomponibili | Verifica diritti di uso, redistribuzione, e termini TTS; niente export dove vietato |
| ER-022 | **Audiobook import** MP3/M4B, EPUB 3 Media Overlays embedded | P1/P2, M6 | modello \`AudioSource\` separato da \`SpeechProvider\`; parse chapter marks/SMIL | Gli EPUB Media Overlays associano audio e contenuto già allineati |
| ER-023 | **Allineamento audiolibro esterno ↔ testo** con forced alignment opzionale | P2 | matching capitoli e timing, revision UI | Solo se l'utente possiede sia testo sia audio; accuratezza, costi e privacy |
| ER-024 | **Schede personaggi spoiler-safe**: identità, alias, relazioni, citazioni già lette | P1/P2, dopo M5 | knowledge graph versionato per capitolo e cutoff di posizione | RAG solo su porzioni già viste; protezione spoiler anche su risultati ricerca |
| ER-025 | **Assistente di lettura contestuale** (chi è X?, termine, recap fin qui) | P2 | retrieval su chapter range ammesso + citazioni/anchor | LLM può allucinare: risposte con evidenza, scelta offline/cloud, nessun spoiler |
| ER-026 | **Backup e sync opzionali cross-device** (WebDAV/Nextcloud/local folder) | P1/P2, progettare M0, rilasciare dopo M3 | sync engine separato da DB; ID contenuto stabili, encryption, conflict resolution | Sync progress/bookmarks/cast/pronunce; file dei libri solo con opt-in |
| ER-027 | **Cataloghi OPDS 1.2/2.0** e integrazione Calibre via OPDS | P2 | \`CatalogSource\` import plugin | No bypass DRM; credenziali secure storage; verifica link/copyright |
| ER-028 | **Accessibility++**: OpenDyslexic opzionale, font personalizzati, modalità concentrazione, maschera righe, tema high contrast, tap-to-speak | P1, M1–M2 | reader UX e screenreader semantics, preferenze per libro | Font specifici non sono efficaci per tutti; controllare contrasto/tasti |
| ER-029 | **PDF reading-order correction** e OCR locale opzionale | P1, M1 raffinamento + V2 | editor ordine blocchi/colonne, OCR adapter con anchors | PDF scannerizzati non diventano searchable/TTS senza OCR |
| ER-030 | **Book audio preparation**: prerender per capitolo/libro, limiti spazio, offline queue, Wi-Fi only | P1, M3 | background jobs, quota disco e cost cap; cancel/resume idempotente | Costi approvati prima, device power constraints |
| ER-031 | **Audio session completa**: lock screen/BT controls, Android Auto se supportato, sleep timer/fade-out, retry e resume | P0/P1, M2–M3 | Android Media3 MediaSessionService, player service native; Windows OS integration | Widget controls diversi per device e player live TTS |
| ER-032 | **Lettura personalizzata**: skipping note/intestazioni, numeri pagina, footnote spoken on demand | P1, M2 | semantic text block filters con traccia del testo escluso | Non eliminare intere frasi per errore |
| ER-033 | **Cronologia/obiettivi**: tempo ascolto/lettura, statistica progressi, sessioni | P2 | analytics solo locale e azzerabile; nessuna telemetria nascosta | Non blocca requisiti core |
| ER-034 | **Interfaccia per biblioteca massiva**: serie, tag, raccolte smart, ricerca full-text offline | P1/P2, M1–M6 | SQLite FTS e indexer cancellabile | Duplicati, file rinominati, indice solo su consenso |

### 15.1 Raccomandazione di scope

**Da progettare subito e realizzare presto (P0/P1):** read-along con anchors robusti, dizionario pronunce, lingua per segmento, gestione pause/cambio speaker, preparazione audio a blocchi, Android background media session, reader accessibile. Questo evita migrazioni costose del data model e dei contratti provider.

**Da prevedere nell'architettura ma rilasciare dopo stabilità del core:** import/export audio, EPUB 3 Media Overlays, sync WebDAV, OPDS, audiolibro esterno sincronizzato, Q&A dei personaggi, stats. Progettare la separazione \`AudioSource\`/\`SpeechProvider\`, ma **non** far crescere l'MVP.

**Differenzianti da testare con utenti e campioni narrativi:** regia audio, glossario spoiler-safe, riassunti "fino al punto corrente", casting A/B. Mantenere espliciti in UI confidenza, fonti e possibilità di disabilitare.

### 15.2 Ulteriori decisioni da prendere in M0

- Consentire una singola entità \`ReadingPosition\` per visuale/audio/annotazioni con mapper stabile, altrimenti sync successiva fragile.
- Persistenza \`PronunciationRule\` con \`scope = global | book | character\`, versione e override.
- \`AudioSource\`: TTS live, synthetic cached, prerecorded file, EPUB Media Overlays; interfaccia comune al player senza pretendere che ogni fonte offra marks.
- \`ProsodyCue\` separato dal \`VoiceProfile\`, così voci permanenti e stato emotivo momentaneo non si confondono.
- Plugin \`LibrarySource\` separato da parsers: in seguito OPDS, Calibre, WebDAV, filesystem, share sheet.
- Schema degli eventi di modifica e versioni per sync futuro (book/content hash, anchor, revisione per annotazione); nessun server in M0.
- Rilevazione spoiler \`visibleAtAnchor\` anche per alias, relazioni, risultati Q&A e cast, non soltanto nel widget.
- Storage modelli audio e job cache come contenuto potenzialmente voluminoso: quote, cleanup e metadati esportabili indipendenti dai file generati.
- **Nessun requisito legato al solo provider**: feature flag per capacità audio, licenze e fiducia nei marks; le funzioni disabilitate devono essere trasparenti all'utente.

### 15.3 Riferimenti standard e piattaforma

- EPUB Media Overlays (audio sincronizzato con XHTML): https://w3c.github.io/epub-specs/epub33/core/#sec-media-overlays
- OPDS Catalog 2.0: https://specs.opds.io/opds-2.0
- Android Media3 background playback: https://developer.android.com/media/media3/session/background-playback
