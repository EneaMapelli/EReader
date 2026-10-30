# EReader — audit punto per punto del piano approvato

**Ultimo esame del codice:** 2026-10-26, branch
`feature/m0-flutter-foundation`, PR #1 in bozza.
**Fonte:** [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) (piano del 2026-10-22)
e [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

Questo documento misura la **copertura implementativa del piano**, non
pass/fail, maturità del prodotto, percentuali di codice o certezza di
rilascio. Le percentuali sono stime qualitative motivate da evidenze
nel repository. I test non eseguiti non aumentano la quota di conformità
nativa. Anche una funzione che esiste nel codice ma non funziona sui
dispositivi resta **parziale**.

## A. Le sette milestone del piano iniziale

| Milestone | Copertura stimata | Concretamente presente | Non completo / condizione di uscita mancante |
|---|---:|---|---|
| **M0 — Fondazione e POC** | **60%** | Flutter/Dart modulari, SQLite con migrazioni fino a v22, parser e adattatori, bootstrap Windows/Android, runner e CI manuale | Progetti nativi generati fuori da Git; POC realmente passati su Windows e Android, ABI/minSDK/licenze, corpus EPUB/PDF e voci sherpa-onnx native |
| **M1 — Reader MVP** | **83%** | Import EPUB/PDF/TXT e dedup, lettura, TOC, source anchors, progressi, segnalibri e ricerca, anteprime note, temi/layout, biblioteca con ricerca/ordinamento e editor di titolo/autore/serie/lingua | Test su 20 libri reali e due piattaforme, copertine, estrazione metadati automatica, CSS/CFI complessi, PDF multicolonna, drag&drop Windows e condivisione Android da verificare |
| **M2 — TTS gratuito e read-along** | **70%** | Sistema TTS, voci e rate/pitch per capacità, segmentazione, seek, posizione sorgente, sleep timer, media handler e policy Stop/recovery | Capitolo continuativo provato su dispositivi, audio focus/interruzioni/cuffie/lock screen e chiavi multimediali Windows reali; timing parola non promesso |
| **M3 — Offline neurale + cloud** | **35%** | Cloud Speech transitorio con consenso/quote per libro, chiavi protette, cache/prefetch; prototipo sherpa VITS con job cancellabili, gestore modelli, import locale e benchmark opt-in | VITS non abilitato/qualificato con voce reale, catalogo firme/licenze, SAF cartella Android, OpenAI Realtime, secondo provider cloud, cost ceiling monetario per sessione/mese e fallback esplicito |
| **M4 — Cast manuale** | **75%** | Identità/alias, segmentation dialoghi, editor, revisioni, speaker unknown, profili voce e mappatura persistente per fonte | Demo audio nativa con narratore + 3 personaggi, prosodia e misure su dialoghi reali |
| **M5 — Screening LLM** | **55%** | Analisi OpenAI opt-in con quote, speaker proposals, indizi, alias, confidenza, revisioni, provenance e protezione delle modifiche manuali | Runtime locale, screening completo gerarchico, confidenza calibrata, corpus gold con precision/recall, verifica grandi libri e budget in valuta |
| **M6 — Polish e release** | **10%** | Documentazione, strumenti di diagnosi, CI manuale e alcune prove prestazionali EPUB | Accessibilità/power/RAM audited, backup/export, MSI/MSIX e APK/AAB firmati, prova end-to-end native, release candidate, privacy e inventario licenze |

**Media aritmetica a milestone di pari peso: circa 55%.** È
un indicatore sintetico di avanzamento dello **sviluppo**, non significa
che l'app sia pronta al 55% per un rilascio. La maturità di release è
sensibilmente inferiore perché M0 e M6 non hanno superato i rispettivi
gate su dispositivi reali.

## B. I sedici deliverable prioritari ER-001–ER-016

| ID | Stima | Stato effettivo e lavoro ancora aperto |
|---|---:|---|
| **ER-001** Scaffold/build Windows+Android | 65% | Flutter, bootstrap e CI presenti; generazione/build e test nativi su entrambi i target non chiusi |
| **ER-002** Book/Chapter/Segment/Anchor + DB | 90% | Entità e repository SQLite con evoluzioni/migrazioni; consolidare schema e mapping EPUB/PDF su corpus reali |
| **ER-003** Import EPUB/TXT, sicurezza, TOC | 85% | Decoder, import picker incluso stream Android, validazioni e navigazione; import da share sheet, EPUB complessi e ZIP stress |
| **ER-004** PDF rendering/testo/ordine | 55% | Visualizzatore e text layer via pdfrx, progresso visuale; ordine colonne/note e PDF scannerizzati non risolti |
| **ER-005** Reader UI/progressi | 78% | Layout EPUB/TXT/PDF, ricerca, bookmarks, note, source anchor; gate 20 libri e due piattaforme aperti |
| **ER-006** Provider contracts/system TTS | 75% | Contratti motori, factory, configurazione e adapter OS; capacità native da certificare per Windows e Android |
| **ER-007** Player e sincronizzazione | 70% | Player, segmenti, offset, Stop/seek/recovery; passaggi di timing e flusso continuo reali da validare |
| **ER-008** Background Android/Windows hotkeys | 45% | Handler/media manifest/audio session e policy nel codice; prove lock-screen, cuffie, chiamate, tasti Windows mancanti |
| **ER-009** sherpa-onnx e model manager | 48% | Import, integrità, modello locale, FFI isolate, gestione UI e benchmark opt-in; nessun test riuscito con ONNX reale, provider ancora nascosto |
| **ER-010** BYOK/vault/consenso/budget | 58% | Chiavi protette, consenso e quote caratteri per libro, caching; manca budget reale in euro/dollari, sessione/mese e pricing dinamico |
| **ER-011** Realtime + secondo cloud TTS | 10% | Contratti provider riutilizzabili, adapter Speech OpenAI **transitorio**; Realtime e Azure/ElevenLabs non implementati |
| **ER-012** Editor cast/manuale/unknown | 80% | UI revisione, segmenti, attribuzione e voci persistenti; ascolto nativo scenari multi-attore non completato |
| **ER-013** LLM JSON/schema/provenance | 60% | Adapter OpenAI, consenso, proposte e validazioni; manca adapter locale e schema provider-agnostico certificato |
| **ER-014** Alias/speaker/review | 70% | Alias, identità, merge, evidence e review; corpus gold, costi e qualità d'attribuzione da misurare |
| **ER-015** Audio cache per segmenti/profili | 65% | Cache e prefetch MP3 con chiavi e controlli, cleanup; composizione offline multi-provider e limiti estesi da qualificare |
| **ER-016** QA/corpus/benchmark | 35% | Ampia suite Dart e strumenti di timing/benchmark EPUB/TTS; suite ancora rossa, gold corpus, dispositivo Android e ascolto reale assenti |

Le stime ER non sono mediate nella percentuale generale per evitare doppio
conteggio delle milestone che questi deliverable compongono.

## C. Capacità del piano iniziale non comprese in un unico deliverable

| Capacità | Stato | Precisazione |
|---|---|---|
| **EPUB/PDF/TXT** | Implementate in codice, qualificazione parziale | CSS/footnotes/reading order/PDF complessi da verificare |
| **Autore, serie, lingua, titolo** | Modifica manuale M1 aggiunta | Migrazione SQLite v17, ricerca e sort; ancora manca auto-estrazione e cover art |
| **HTML/Markdown, FB2/DOCX/MOBI/AZW3** | Non implementati | Sono post-MVP e V1/V2, non inclusi nel reader base |
| **PDF OCR/scannerizzati** | Non implementato | Il text layer non equivale a OCR |
| **Cloud privacy e costi** | Parziale | Opt-in esplicito e quota caratteri; budget in valuta e secondo provider mancanti |
| **LLM locale** | Non implementato | OpenAI remoto attuale non equivale alla modalità completamente privata |
| **Voce caratteri, attribuzione, QA UI** | Ampiamente in codice | Benchmark di pronuncia/3+ personaggi e misure gold non conclusi |
| **Media session in background** | Implementata come source/manifest | Non qualificata su lock-screen/cuffie/chiamate reali |
| **Accessibility e storage gestito** | Parziale | Alcuni controlli UI; audit screen reader/focus e packaging mancanti |
| **Backup/export/sync e installatori** | Non completati | Gate reale M6, non sostituibile da script di test |

## D. Ampliamenti ER-017–ER-034 accettati dopo il piano

Questi punti **non** sono inclusi nel 55% come funzionalità
automaticamente consegnate: sono ampliamenti dello scope.

| Estensione | Stato |
|---|---|
| ER-017 Read-along avanzato | Parziale: source anchor/sync; non parola-per-parola universale |
| ER-018 Dizionario pronunce | Parziale: regole e UI; fonemi/SSML per-provider da validare |
| ER-019 Lingue miste | Non completo: lingua libro manuale; rilevamento per segmento mancante |
| ER-020 Regia audio e prosodia | Parziale: segmenti e pause; normalizzazione/mixing/emozioni avanzate mancanti |
| ER-021 Esportazione audiolibri M4B/MP3 | Non implementata |
| ER-022 Import audiolibri/media overlays | Non implementato |
| ER-023 Allineamento audio esterno al testo | Non implementato |
| ER-024 Schede personaggio spoiler-safe | Fondamenta alias/evidence; knowledge graph spoiler-safe da completare |
| ER-025 Assistente contestuale | Non implementato |
| ER-026 Backup/sync cifrato | Non implementato |
| ER-027 OPDS/Calibre | Non implementato |
| ER-028 Accessibilità avanzata | Parziale: lettore personalizzabile; audit/maschere/focus high-contrast mancanti |
| ER-029 PDF reading order/OCR | Non implementato; visualizzazione text layer non basta |
| ER-030 Preparazione audio capitoli/libro | Parziale: prefetch/cache, non job queue full-book |
| ER-031 Audio session evoluta | Parziale: media handler e sleep timer, piattaforme non qualificate |
| ER-032 Skipping note/struttura | Parziale: preview note e struttura, filtro spoken non completo |
| ER-033 Statistiche/obiettivi | Parziale: catalogo, tempi giornalieri e per libro in SQLite v23/v24, obiettivo globale, storico 7 giorni, cancellazione selettiva/globale e opt-out persistente dal tracciamento. Restano campionamento euristico e QA Windows/Android |
| ER-034 Libreria massiva/collezioni/FTS | Parziale: metadati avanzati, raccolte manuali/smart (v25), indice FTS5 opt-in (v26), apertura al match UTF-16 verificato e refresh incrementale manuale. Mancano OCR, refresh automatico opzionale, ricerca semantica tra termini distanti e QA nativa/large-library |

## E. Evidenza e priorità

- Ultimo Windows report realmente eseguito: origine `7c89dfc8`
  del 2026-10-25, **641 pass, 0 assertion fail, 7 error outcomes**
  su 76 file; `dart format` aveva 147 file da formattare.
- L'ultima serie di correzioni successive e la migrazione M1 v17 non hanno
  ancora un run locale aggiornato; Flutter/Dart non sono installati in
  questo ambiente di editing GitHub. Non presentare come passati test
  non eseguiti.
- Prima priorità di prodotto **M1/M2**: metadati EPUB automatici,
  copertine, controllo PDF e lettura consecutiva su dispositivi.
- Poi **M3**: voce neurale realmente provata, modello/licenze italiani
  e inglesi; OpenAI Realtime e almeno un secondo cloud provider con
  un cost ceiling monetario coerente.
- Poi **M4/M5**: corpus dialoghi e gold QA; solo dopo M0/M2 stabili.
- Infine **M6**: inclusione piattaforme native, firma/distribuzione,
  accessibilità e privacy audit.

**Interpretazione:** molto del codice applicativo esiste e continua a
crescere, ma lo sviluppo resta lontano da una release affidabile senza
chiudere prima il ciclo sui dispositivi reali.

### Auto-import dei metadati EPUB (2026-10-26)

- Supportati OPF2/OPF3 title, author, locale e serie tramite
  identificatori Calibre o EPUB3 collection-type=series.
- La UI permette il backfill esplicito dei campi mancanti.
- La copertina non è ancora estratta né mostrata in biblioteca;
  le percentuali restano stime qualitative senza nuovi test nativi.

### Copertine EPUB nella biblioteca (2026-10-26)

- Estrazione locale da manifest EPUB2/EPUB3 di immagini di copertina
  esplicitamente dichiarate, PNG/JPEG con limiti su byte e pixel.
- Copie derivate sotto application support, denominate con digest SHA-256;
  visualizzazione thumbnail nella lista dei libri e fallback alle icone.
  Cancellazione con il libro e recupero manuale da OPF.
- Rimangono da implementare le anteprime PDF, il rilevamento di copertine
  non dichiarate, cataloghi remoti/OPDS e l'audit visuale sui dispositivi.
  Percentuale M1 aggiornata a 82%; media complessiva stimata ~55%.

### Navigazione PDF e sincronizzazione pagina/testo (2026-10-26)

- Implementati i comandi pagina precedente/successiva, pagina N su totale,
  salto validato, zoom e mappatura esplicita da pagina visuale a inizio testo
  TTS, con supporto a pagine senza text layer.
- Il checkpoint visuale resta separato dall'anchor della narrazione; il
  pulsante per tornare alle pagine individua il segmento testuale attivo.
- **Non** è ancora stato risolto l'ordine dei blocchi multicolonna,
  la segmentazione di note/tabelle o l'OCR dei PDF scannerizzati.
- La verifica nativa resta aperta. M1 stimato **83%**.

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

### Controllo lettura vocale delle note EPUB (2026-10-26)

- ER-032/M2: aggiunta opzione di sessione (di default disattivata) per non
  pronunciare i segmenti completamente contenuti in note EPUB verificate.
  Note visuali, link, testo sorgente, cast e posizioni persistenti restano
  invariati. Gli intervalli misti nota/prosa **non** vengono saltati.
- Il filtro entra prima della sintesi e del prefetch cloud: nessuna nuova
  richiesta anticipata per il segmento escluso, salvo richieste già partite
  prima del cambio d'impostazione.
- Test sintetici per parsing, UTF-16, continuità e cloud prefetch aggiunti
  ma **non eseguiti**. La percentuale M2 rimane 70% e quella aggregata ~55%.
  [Specifica e checklist](EPUB_SPOKEN_NOTE_CONTROL.md).

### Continuità audio dei paragrafi narrati (2026-10-26)

- M2: l'EPUB ora può unire frammenti consecutivi e non attribuiti dello
  **stesso paragrafo**, massimo 400 unità UTF-16. Non attraversa capitoli,
  citazioni, cast manuale, blocchi con narrator lock o note EPUB verificate.
- Nessuna riscrittura del testo, migrazione o richiesta cloud supplementare;
  meno transizioni di sintesi potenziali, ma senza dichiarare audio gapless.
- Test per confini, voci multiple, UTF-16 e riproduzione fake aggiunti,
  **non eseguiti**. M2 rimane **70%**; totale circa **55%**.
  [Note tecniche](NARRATOR_PARAGRAPH_CONTINUITY.md).

### Precaricamento MP3 già presenti nella cache locale (2026-10-26)

- M2: l'audio cloud già generato viene precaricato nel decoder MP3 inattivo
  tramite cache privata; comportamento **abilitato di default** ma
  disattivabile dall'utente. Nessuna richiesta HTTPS/chiave/quota aggiuntiva
  da questo preriscaldamento: cache miss = nessuna sintesi anticipata.
- Resta separata e **disabilitata di default** la sintesi cloud a pagamento
  della clip successiva. Entrambi i percorsi saltano i segmenti di note EPUB
  verificate esclusi volontariamente dalla narrazione e scelgono il primo
  successivo segmento pronunciabile.
- Test mock per cache, voci, note, quote cloud, Stop e consenso aggiunti
  ma **non eseguiti**. Percentuali invariate: M2 ~70%; totale ~55%.
  [Dettagli e prove manuali](CACHED_AUDIO_WARMUP.md).

### Riduzione delle chiamate Stop native ridondanti (2026-10-26)

- M2: ogni decoder MP3 evita uno Stop *superfluo* prima del caricamento
  solo quando risulta appena creato o già arrestato con conferma.
  La chiusura delle clip, i blocchi Stop/Seek e i passaggi narratore/voce
  continuano a essere serializzati; nessuna sovrapposizione è introdotta.
- In caso di caricamento parziale/fallito, prova uno Stop prima della
  cancellazione del file. Se lo Stop fallisce, un nuovo caricamento deve
  ripeterlo.
- Aggiunti test fake per Stop lento e fallito, clip consecutive e decoder
  preparato, senza esecuzione reale. Nessun guadagno di latenza misurato:
  M2 ancora 70%, complessivo ~55%.
  [Specifica](MP3_NATIVE_STOP_DEDUP.md).

### Audio focus Android e avanzamento segnalibro dopo clip completata (2026-10-26)

- M2: le interruzioni audio duplicate vengono raggruppate in una sola
  attesa dello Stop nativo, invalidando ogni comando Play successivo ma
  precedente all'ultima interruzione. Non si riparte automaticamente dopo
  la riconquista del focus.
- Il checkpoint SQLite avanza al prossimo segmento effettivamente narrabile
  solo **dopo** il completamento della clip precedente; un'interruzione a
  metà mantiene l'offset iniziale, evitando di saltare parole. Note EPUB
  espressamente escluse non spostano l'ancora su segmenti silenziosi.
- Aggiunti test per race media/focus e verifica integrata storage, non
  eseguiti. Stime invariate M2 ~70%, M0–M6 ~55%.
  [Specifiche e casi manuali](AUDIO_INTERRUPTION_CHECKPOINTS.md).

### Sincronizzazione posizione, capitoli EPUB e pagine PDF (2026-10-26)

- M2: il cursore narrativo ripristinato a fine libro rimane **completato**,
  senza ripetere l'ultima clip; un salto esplicito da TOC, ricerca o
  segnalibro continua invece a scegliere un segmento pronunciabile.
  Interfaccia con stato finale e Play che riparte dall'inizio.
- Fine libro ora salva anche l'ancora sorgente EPUB/PDF corretta.
  Ripristino legacy EPUB senza ancora conserva la posizione `text.length`.
- Sintesi PDF segmentata per **pagina fisica**, senza clip a cavallo,
  mantenendo offset UTF-16 e azzerando gli stati di citazione a ogni pagina.
  Voltare pagine PDF resta indipendente dalla posizione audio.
- Aggiunti test sintetici, non eseguiti. Stime invariate: M2 ~70% e
  complessivo ~55%; validazione nativa ancora aperta.
  [Specifica](READER_SOURCE_SYNC.md).

### Sezioni EPUB mute e pagine PDF senza testo estratto (2026-10-26)

- M2: l'indice OPF include anche capitoli senza segmenti TTS, conservando
  l'offset visuale originale e distinguendolo da quello della prima clip
  successiva. La navigazione non genera audio né invia API.
- Le destinazioni EPUB silenziose in coda portano il cursore parlato a EOF
  senza ripetere l'ultima frase. Uno Stop nativo in volo blocca la ripresa,
  e un Seek precedente viene invalidato secondo l'ordine ultimo-vince.
- PDF: le pagine finali scansionate senza testo successivo non tornano
  alla pagina leggibile precedente; un tentativo di lettura esplicita
  produce un messaggio e non avvia la sintesi.
- Test simulati/dominio aggiunti, non eseguiti. Percentuali invariate:
  M2 ~70%, complessivo ~55%. [Dettagli](VISUAL_ONLY_SOURCE_NAVIGATION.md).

**Integrazione dell'estrattore:** gli elementi XHTML dello spine che non
producono testo restano come intervalli a lunghezza zero e nell'ordine
OPF, invece di essere scartati prima di costruire l'indice. Un libro
interamente privo di testo leggibile viene ancora rifiutato. Test ZIP
aggiornati, non eseguiti; nessuna illustrazione inventata.

### Immagini EPUB in sezioni OPF senza testo pronunciabile (2026-10-26)

- M2: l'estrattore EPUB ora riconosce immagini PNG/JPEG incorporate anche
  in XHTML senza testo, senza inventare caratteri sorgente né TTS.
  Mantiene i controlli locali su manifest, MIME, dimensioni e budget.
- L'audit delle ancore ora ammette spine OPF a lunghezza zero valide
  mantenendo i rifiuti per corruzione, collisioni ID e separatori.
- Rendering EPUB progressivo: un blocco visuale autonomo per ciascun
  elemento illustrato, con immagini associate all'idref OPF; le sezioni
  che condividono l'offset restano distinte anche per scorrimento,
  segnalibri, chiusura e riapertura. Il TTS resta indipendente.
- Test ZIP, pure Dart e widget aggiunti ma non eseguiti. Non è un
  renderer XHTML/CSS completo né supporta libri composti solo da immagini.
  Stime invariate M2 ~70%, totale ~55%.
  [Specifiche](EPUB_ILLUSTRATED_SPINE.md).

### Immagini EPUB intercalate al testo nella posizione originale (2026-10-26)

- M2: immagini all'interno di paragrafi XHTML visualizzate nel punto
  corrispondente all'offset sorgente, non più tutte dopo il paragrafo.
  Spezzati soltanto i frammenti grafici: indici TTS, annotazioni di voce,
  link, note, ricerche, testo e segnalibri restano originali.
- Renderer progressivo e eager allineati sulla proprietà OPF e sui blocchi
  XHTML privi di testo. Più immagini a uno stesso offset conservano l'ordine.
  Guard per non spezzare i caratteri UTF-16 a coppia surrogata.
- Test unitari e widget aggiunti, non eseguiti. Non è reflow CSS completo
  e non supporta ancora tutti i fumetti EPUB solo immagini. Stime M2 ~70%
  e complessivo ~55%. [Dettagli](EPUB_INLINE_IMAGE_FLOW.md).

### Didascalie e anteprime tabelle EPUB nel flusso sorgente (2026-10-26)

- M2: gli elementi `figcaption` vengono riconosciuti da XHTML,
  propagati attraverso l'estrattore ZIP/worker e resi in corsivo con
  dimensione leggermente ridotta. Il contenuto resta nel testo originale,
  narrato una sola volta e con gli stessi offset/link/note/voci.
- L'anteprima di `table` è ancora facoltativa ed espandibile ma compare
  immediatamente **dopo** il testo tabellare originale, non più alla fine
  del paragrafo. Supporto concorde nei renderer lazy ed eager.
- Aggiunti test su estrazione, annotazioni, Unicode, tabelle e widget,
  ancora **non eseguiti**. Griglie complesse HTML/CSS restano escluse.
  Avanzamento M2 ~70%, totale ~55%.
  [Specifica](EPUB_FIGURE_CAPTION_TABLE_FLOW.md).

### M1 — Import multiplo ebook nella biblioteca (2026-10-27)

Il picker di Windows/Android permette fino a 50 EPUB/PDF/TXT in un'unica
selezione. Import seriale, progressi/cancellazione tra file, errori
isolati, riconoscimento duplicati tramite SHA-256 e supporto Android
SAF senza percorso, mantenendo l'archiviazione locale originale.
Nessuna richiesta TTS o cloud durante l'importazione; ripresa e dati
SQLite dei duplicati restano invariati. Test scritti, non eseguiti;
manca ancora drag&drop Esplora risorse e integrazione con librerie
esterne. [Dettagli](LIBRARY_BATCH_IMPORT.md).

### M6 — backup locale della biblioteca (2026-10-27)

Nuova opzione esplicita di esportazione privata della biblioteca con
snapshot SQLite consistente `VACUUM INTO`, copia integrale dei libri
EPUB/PDF/TXT verificata SHA-256 e manifest del progresso/metadati.
Salvataggio atomico in una cartella autonoma, errori fail-closed,
nessun overwrite, nessun upload o segreto credenziali OS.
Backup ancora privo di cifratura e ripristino automatico; test unitari
scritti ma non eseguiti. `windows-user-build.yml` è stato reso
esclusivamente manuale: i commit non avviano più build Actions.
[Guida](LIBRARY_BACKUP_EXPORT.md).

### M6 — ripristino conservativo e verificato della biblioteca (2026-10-27)

Implementati verifica completa del backup v1, preview read-only,
conferma esplicita e import add-only dei soli libri assenti. Per ogni
ebook la copia originale viene ricontrollata SHA-256 e i suoi metadati,
segnalibri, ancore, progressi e pagina PDF sono inseriti con una
transazione SQLite. Nessun overwrite dei record locali, nessuna
riattivazione consensi LLM/cloud, nessuna preferenza TTS/cast, cache
o credenziale trasferita. Le importazioni riuscite restano anche
in caso di fallimento successivo; cartella sorgente non modificata.
Test previsti in `test/data/library_backup_restore_test.dart`
ma non eseguiti, nessuna compilazione/actions.
[Guida](LIBRARY_BACKUP_RESTORE.md).

### M1 — drag & drop libri Windows (2026-10-27)

Implementato target native desktop DropTarget limitato a file con
overlay "Drop EPUB, PDF or TXT", basenames sanitizzati, filtro
formati ammessi e limite 50. Passaggio allo stesso importer seriale
del picker, senza leggere i percorsi originali e consumando gli
stream dentro onDrop; riepilogo dei file scartati con privacy.
Android non cambia. Test Dart scritti, non eseguiti. Nessuna Action
o Release generata, workflow manuali. [Specifica](LIBRARY_DESKTOP_DRAG_DROP.md).

### M4/M2 — Multilingual character speech handoff (2026-10-29)

- Narrator → character → narrator playback now passes the **resolved installed
  character voice's locale** into synthesis for explicitly assigned turns.
  Narration, missing/removed character voices and provider-wide `multi`
  voices keep the book's configured language.
- Cloud and offline lookahead receive the same per-turn resolved language and
  voice snapshot as actual speech; paid speculative prefetch remains OFF by
  default, with no new cloud/consent/billing behavior.
- Asynchronous native voice choices for cast turns are serialized with
  explicit narrator switches. A late selection superseded by Pause/Seek
  cannot be accepted as the next session's voice; the next segment waits for
  the native selection gate before speaking.
- New fake-engine tests cover English/Spanish dialogues in an Italian book,
  narrator recovery, stale voice fallback, multilingual provider profiles,
  prefetched locale, and rapid Seek during delayed voice selection.
  **Tests not executed, no platform build/Actions launched**. Acceptance
  still requires real Windows/Android native voices, user listening, focus,
  pronunciation and timing checks. No milestone percentage increase claimed.
- See [MULTILINGUAL_CAST_HANDOFF.md](MULTILINGUAL_CAST_HANDOFF.md).

### M2/M4 — Overlap native handoff and atomic multilingual cast (2026-10-29)

- A completed source segment now allows the *silent* native
  `chooseVoice` operation and the cancellable Windows punctuation /
  narrator-to-character breath to run concurrently. The next source
  checkpoint and visual highlight still wait for **both** to finish.
  This removes sequential platform-switch overhead but makes no
  gapless, sample-accurate timing claim.
- Per-segment character voice and spoken language are now resolved
  from **one** installed-voice snapshot, instead of invoking the
  mutable cast resolver once for timbre and again for locale. The next
  offline/cloud lookahead receives the same internal snapshot policy.
  Missing installed voices still fall back to the narrator/book locale;
  `multi` provider voices keep the configured book language.
- Added gated concurrency/cancellation cases and mock multilingual
  voice/language snapshot cases. **Tests authored but not executed**;
  native Windows/Android acceptance remains pending, without platform
  builds or GitHub Actions. Milestone percentages unchanged.
- See [LONG_DIALOGUE_HANDOFF_OPTIMIZATION.md](LONG_DIALOGUE_HANDOFF_OPTIMIZATION.md).


### M2/M4 — Serialized persisted voice selection and preference-race safety (2026-10-29)

- `ReaderPlayer.applyPreferences()` now enters the same native voice
  selection queue used by per-character playback and explicit voice changes.
  Pending auto-resuming Seek and superseded profile updates cannot later
  select the wrong voice or restart a paused book.
- Profile settings commit only when the winning native selection has
  finished. If that selection fails, the previous saved playback settings
  remain usable and the next explicit retry may succeed. An unsafe native
  Stop still blocks reconfiguration.
- Corrected a source-level Dart constructor issue: the dialogue pause is a
  normal argument initializing a private backing field, not an
  initializing-formal targeting a getter.
- Authored six regression cases covering overlapping profiles, stale manual
  voice selection, active playback pause, Seek/Stop racing, rejected native
  selection/retry and provider mismatch. **Tests not executed**; no native
  builds or Actions. No change to milestone acceptance percentages.
- [PERSISTED_VOICE_PREFERENCE_RACES.md](PERSISTED_VOICE_PREFERENCE_RACES.md).


### M1/M6 — Persisted visual reading appearance (2026-10-29)

- Reader appearance is now persistable **globally and per book**:
  14–32 text size, 1.2–2.4 interline spacing, serif/sans-serif/monospace
  family and EPUB paper/night/system palette. Added a reader settings
  dialog with Save book / Set global / Use global / Cancel actions.
- Existing quick font-size and EPUB palette controls also save the
  current book's preferences instead of resetting on reopen.
- SQLite **v18** introduces a separate `reading_preferences` table,
  with no migration of speech profiles, cloud consent, bookmarks or
  source anchors. Book removal cleans up its style override.
- EPUB rendering uses preferences without rewriting any source text,
  run offsets, cast spans, links or highlights. TXT and PDF text layer
  use font and spacing; faithful PDF pages retain native zoom.
- Domain, persistence/reopen/migration and widget regressions authored;
  **not executed**. No builds, GitHub Actions or milestone percentage
  increase without native visual acceptance.
- [PERSISTENT_READING_APPEARANCE.md](PERSISTENT_READING_APPEARANCE.md).


### M1/M2/M6 — Foreground keyboard controls for reading (2026-10-29)

- Added safe keyboard navigation for the active reader: **Space**
  Play/Pause, **Left/Right** spoken segment, **Ctrl/Cmd+F** search,
  **Ctrl/Cmd+B** bookmarks, **F1** in-app shortcut reference.
- Uses existing TTS player and cloud-consent checks; does not start a
  new engine, move visual-only EPUB source positions or bypass native
  Stop/Seek protection. PDF page view remains unchanged.
- Focus-aware routing ignores editable text fields, open dialogs,
  inactive routes, repeats/key-up and modified navigation keys.
  Reader controls now expose discoverable shortcut tooltips/help.
- Authored mapping, widget, modal focus and accessibility regression
  cases. **Not executed**; no Windows/Android build or GitHub Actions.
  No milestone completion percentage changes without device testing.
- [READER_KEYBOARD_SHORTCUTS.md](READER_KEYBOARD_SHORTCUTS.md).


### M1/M2 — Whole-book visual source progress and safe scrubber (2026-10-29)

- Replaced a speech-segment-only progress readout with a **separate**
  canonical-text percentage and source seek slider in EPUB, TXT and
  PDF **text mode**. Do not confuse source percentage with audio time.
- Dragging previews only; release pauses narration before navigating,
  so it cannot trigger cloud TTS or resume unexpectedly. EPUB navigates
  using existing source-exact destinations, including silent trailing
  content; TXT/PDF seek their real next spoken segment or source EOF.
- Fine-grained manual scroll updates only the progress control unless
  an EPUB directory title actually changes, minimizing rebuilds in
  large books. Faithful PDF page mode remains page-based.
- Added pure bounds and widget interaction regressions, **not run**;
  no builds or GitHub Actions and no milestone percentage increase.
- [WHOLE_BOOK_SOURCE_PROGRESS.md](WHOLE_BOOK_SOURCE_PROGRESS.md).


### M1/M6 — Accessible reading column and high-contrast EPUB palette (2026-10-29)

- Added per-book/global **480–1000 px responsive column width** and
  **original/left/justified paragraph alignment** for EPUB, TXT and PDF
  text mode; unchanged faithful PDF page rendering.
- EPUB gains an explicit **high-contrast white/black** palette with
  separate legible link, active speech and search highlight colors.
- Extended existing SQLite v18 appearance **JSON v1** without a schema
  migration. Old saved profiles retain their previous typography and
  layout: newly absent fields use 760 px and original alignment.
- Authored domain compatibility, SQLite reopen and source-preserving
  Flutter widget regressions. **Not executed**; no native builds or
  GitHub Actions. Real-device contrast/focus acceptance remains open.
- See [PERSISTENT_READING_APPEARANCE.md](PERSISTENT_READING_APPEARANCE.md).


### M1 — Physical PDF page scrubber and SQLite fixture correction (2026-10-29)

- In the **faithful visual PDF viewer**, added an accessible physical-page
  percentage and fast scrubber. Dragging previews a page; releasing
  requests a single native page transition through the existing callback.
  The exact Go-to-page number dialog remains available for long manuals.
- The slider is hidden until a multi-page PDF is ready, uses a bounded
  number of ticks for large files and does **not** mutate text-layer
  anchors, cloud consent or any TTS session.
- Corrected the existing legacy PDF migration regression to expect
  SQLite v18 after the previous appearance migration. Added four
  unexecuted widget regression cases for release-only seeking, labels,
  large PDFs and unavailable/single-page PDFs.
- [PDF_VISUAL_RESUME.md](PDF_VISUAL_RESUME.md).
- **Tests not run**, no Windows/Android builds or GitHub Actions;
  M1/M6 release acceptance remains pending native testing.


### M1/M6 — PDF physical bookmarks and repaired cross-version backup restore (2026-10-29)

- Added a dedicated **PDF page bookmarks** dialog: name/save the
  currently visible page, list and open saved pages, and delete marks.
  Works for scanned/image-only documents without OCR or any TTS engine.
  Out-of-range page targets are displayed but cannot navigate.
- SQLite **v19** adds a separate FK-backed `pdf_visual_bookmarks`
  table with page-number validation, transactional migration from v18
  and automatic cleanup when the PDF is deleted. The narration
  bookmark table, last PDF visual page and source/TTS anchor are
  independent and unchanged.
- Corrected a real portability bug: the backup inspector formerly
  rejected EReader's own v18 exports because it required **v17**.
  It now accepts v17–v19, validates all v19 physical bookmarks
  and restores them atomically *only* with missing books. Existing
  books and their settings are never overwritten.
- Authored local persistence/migration, UI and cross-version backup
  regressions. **Not run** (no Flutter/Dart SDK), no Windows/Android
  builds or GitHub Actions; release/restore acceptance remains open.
- [PDF_VISUAL_RESUME.md](PDF_VISUAL_RESUME.md) and
  [LIBRARY_BACKUP_RESTORE.md](LIBRARY_BACKUP_RESTORE.md).


### M1/ER-034 — Library favorite stars, search filter and portable backup (2026-10-29)

- Books can be starred/unstared with one tap. Added a Favorites filter
  combining with existing search/format/activity criteria and a
  Favorites-first sort. Existing book order remains the default.
- SQLite **v20** persists a bounded boolean catalog flag, migrating
  older libraries with all titles unstarred. TTS, progress, last-opened
  history, source anchors and consents do not change when starring.
- Export includes favorite state in manifest plus standalone SQLite
  snapshot. Restore accepts SQLite **v17–v20**, validates v20 manifest
  against stored favorite values and restores stars **only** when adding
  a new book. Existing titles retain local choices.
- Authored domain, store/migration, Flutter widget and backup
  round-trip/tamper tests. **Not executed**; no Windows/Android builds
  or GitHub Actions, no milestone percentage change without native QA.
- [LIBRARY_FAVORITES.md](LIBRARY_FAVORITES.md).


### M1/M6 — Explicit reading shelves and portable v21 state (2026-10-29)

- Every book can be manually marked **To read**, **Reading**, or
  **Finished**, with a dedicated library filter that combines with
  Favorites, format, text query and opened-history filters.
  Added Reading-shelf sort and compact book-row actions for Android.
- SQLite **v21** migrates v20 books to To read without rewriting
  favorites, bookmarks, progress, native PDF pages or TTS/cloud state.
  These statuses do **not** auto-infer that a book was finished.
- Export writes the shelf to both manifest and standalone SQLite
  snapshot. Restore accepts **v17–v21** archives, validates v21
  metadata, defaults absent legacy shelf values to To read, and
  never overwrites existing books' local shelf preferences.
- Authored store/domain, Flutter UI, backup round-trip and tampering
  regression cases. **Not executed**, no Windows/Android build or
  GitHub Actions. Native acceptance remains outstanding.
- [LIBRARY_READING_SHELVES.md](LIBRARY_READING_SHELVES.md).


### M1/ER-034 — User-managed multi-book collections (2026-10-29)

- Added **Manage collections** to the library: create, rename and
  delete named categories without touching stored source files.
  Each book can be added to multiple categories using its More menu.
- Combined **Collection** filter with query, format, Favorites,
  opened/unopened and reading-shelf filters; Clear filters never
  removes saved memberships.
- SQLite **v22** adds validated names, unique case-insensitive
  catalog IDs and FK-cascaded many-to-many membership. Migration
  preserves existing book positions, status, favorites, bookmarks,
  cloud consent and TTS settings.
- Full v22 portable backup/restore retains all collection names,
  **including empty categories**. The manifest is validated
  against the snapshot. Restore accepts **v17–v22**, creates only
  missing category names and assigns only newly imported books.
- Authored repository, filter, UI and portable-backup regression
  tests. **Not executed**; no Windows/Android builds or GitHub
  Actions, and no release readiness claim.
- [LIBRARY_COLLECTIONS.md](LIBRARY_COLLECTIONS.md).

### M2 — Auto-select system TTS locale from catalog metadata (2026-10-29)

- Books without any saved speech preference now infer their narration
  language from EPUB OPF or user-edited catalog locale: `en` maps to
  `en-US`, explicit regions such as `en-GB` are retained.
- Per-book speech preferences override global preferences; global settings
  override inferred language; malformed/unsupported bare language tags
  preserve the existing Italian default. Inference is never persisted and
  never chooses or downloads a paid TTS provider.
- Added pure locale normalization and SQLite scope/restart regressions.
  **Tests not run** (Dart/Flutter SDK unavailable in this environment);
  native system voice availability and pronunciation remain unverified.
  No Windows/Android build or GitHub Actions started.

### M2 — Capability-gated native speech volume (2026-10-29)

- Added a **0–100%** slider for the two OS system-TTS modes only.
  Free/native flutter_tts receives the configured volume before each
  utterance; a committed slider change restarts the current source segment
  using the existing cancellation and native Stop safety sequence.
- Added volume to version-1 speech preferences (global and per-book),
  retaining the existing SQLite schema and JSON version. Older settings
  default to 100%; nonfinite or out-of-range input is rejected.
- Cloud and experimental offline engines do **not** claim volume support.
  Their existing saved profiles can round-trip the field but never apply
  it, initiate any synthesis or grant cloud access.
- Authored domain and injectable ReaderPlayer capability/volume tests.
  **Not run** without Dart/Flutter; no Windows/Android build or GitHub
  Actions triggered. Physical OS volume behavior remains an acceptance gate.

### M2/M4 — Recover native voice failures and language-safe narration (2026-10-30)

- Explicit and automatic voice selection failures no longer leave a
  permanently rejected Future in the player's serialized voice barrier.
  The failing request still reports its original error, while a later
  user-initiated Play can safely retry from the same source segment.
- An interrupted native voice choice invalidates cached speaker identity;
  the next Play reasserts the last committed narrator rather than trusting
  a backend that may have changed the physical voice before failing.
  Native SystemSpeechEngine records a new voice only after setVoice succeeds.
- Unsaved system narrator defaults now prefer an installed exact locale
  match, then a same-language regional voice, before the historic fallback.
  Existing manual narrator/cast choices still take precedence; automatic
  choices are never persisted and do not affect cloud/VITS providers.
- Authored controlled-failure tests for manual, saved and cast changes,
  plus book-language fallbacks. **Not run**: Dart/Flutter SDK unavailable.
  No Windows/Android build or GitHub Actions initiated; physical OS
  behavior and spoken-voice verification are pending manual acceptance.

### M2/M3 — Isolate speculative lookahead errors from audible playback (2026-10-30)

- Fixed a real asynchronous audio lifecycle hazard: after invoking
  `SpeechEngine.speak`, the player inspected the *next* segment's
  pronunciation, cast or note-filtering callbacks **before** awaiting
  the already-running audio Future. A synchronous exception in optional
  lookahead could abandon playback, report idle/error and release focus
  while the current utterance was still audible.
- Speculative preview inspection now fails closed: no premature
  completion, no new TTS request, no source-anchor/checkpoint mutation,
  no automatic cloud retry. The current audio always reaches its normal
  completion/cancellation path. Actual next-segment processing still
  reports real errors; lookahead cannot hide those failures.
- Added controlled offline fake-engine regressions for failing
  pronunciation, cast and note-skip previews. They assert spoken order,
  live playback state, source checkpoint callbacks and clean EOF.
- Tests **authored, not executed** without Flutter/Dart SDK. No Windows
  or Android builds or GitHub Actions initiated. Native sound/focus
  acceptance remains open.

### M2 — Completed-segment acknowledgment barrier (2026-10-30)

- Fixed an audible-completion/async-checkpoint race: Pause or a voice
  change during an already-heard segment's delayed checkpoint could
  discard its cursor increment and replay the whole completed clip.
- ReaderPlayer now counts outstanding completed-segment acknowledgments
  and keeps the crash marker/audio focus unsettled until they finish.
  Successful acknowledgments advance the cursor even if Pause arrived;
  failed persistence preserves the original index for safe replay.
- Native Stop has its own 8-second safety deadline. A slow SQLite
  acknowledgment cannot masquerade as a failed native Stop or permanently
  lock the device; later Play/Seek still wait for both operations.
- NarrationRecoveryBinding accepts completion of an **already audible**
  segment during Pause, but only while the player proves an acknowledgment
  is in flight. Interrupted utterances never enter that state.
- Added fake-engine regressions for Pause, Seek, rapid Pause/Play and
  failing acknowledgments, plus SQLite integration across delayed
  completion, marker clearance and store reopen.
- Tests **written but not run** (Flutter/Dart SDK unavailable); no
  Windows/Android build or GitHub Actions started.

### M2 — Separate native Stop queue from completed-segment checkpoints (2026-10-30)

- Fixed repeat Pause/Seek commands behind an outstanding completed-segment
  SQLite acknowledgment: the previous serialized Stop queue contained
  checkpoint latency, so a second physical Stop could incorrectly exceed
  its native 8-second deadline and lock narration even though audio had
  already stopped.
- Added a native-only Stop queue alongside the existing full-settlement
  queue. Only the native chain is subject to the safety timeout; Play and
  navigation still wait for *all* prior stop/checkpoint work.
- Scoped TimeoutException handling strictly to the actual physical
  Stop, never to an asynchronous SQLite callback that may itself time out.
- Added regression tests for duplicate Pause, rapid skip requests
  during a held completion checkpoint and checkpoint-specific timeout.
  The tests verify last-command-wins cursor semantics, no premature
  audio and no false native engine recovery lock.
- **Tests not run** without Dart/Flutter; no Windows or Android builds
  or GitHub Actions started. Physical background/phone-call acceptance
  remains pending.

### M2/Android — Reassert interruption after direct in-reader controls (2026-10-30)

- Fixed a race in Android media-session interruption coalescing: a second
  phone/noisy event previously shared the first unfinished Pause even if
  ReaderScreen had initiated a *new* direct Play or Seek meanwhile. That
  newer control operation could restart audio when the first native Stop
  finally resolved.
- Added a read-only ReaderPlayer control revision. The media handler
  continues to coalesce genuinely duplicate interruption events, while
  reasserting Pause and joining both native-stop Futures whenever the
  reader has issued newer control intent. Pending remote Play remains
  invalidated without requiring a native operation for duplicates.
- Added controlled integration tests for direct Play, direct Seek and
  repeated interruption callbacks with a delayed native Stop. Check that
  no later synthesis occurs, repeated callbacks share the new Stop and
  the reader stays settled without automatic resume or cloud activity.
- Tests authored but **not run** (Flutter/Dart SDK unavailable). No
  Windows/Android build or GitHub Actions started; real device audio-focus
  and incoming-call verification remains an acceptance requirement.

### M2/Android — Media skip cursor and silent EOF (2026-10-30)

- Corrected Android Next on the last spoken source segment: it now
  advances to ReaderPlayer's explicit *silent* EOF instead of clamping
  back to and replaying the final utterance. A further Next at settled
  EOF is idempotent and does not invoke the native Stop again. Previous
  at EOF returns to the last audible segment; Play at EOF still represents
  an explicit user-directed restart.
- Remote Next/Previous presses that arrive while native Stop/checkpoint
  barriers are pending now accumulate relative to their last requested
  source position. ReaderPlayer's existing navigation epoch makes only
  the newest target effective. A newer direct in-reader navigation uses
  its own revision and supersedes that remote accumulation.
- Authored fake-engine regressions for last-segment EOF, Previous after
  EOF, three rapid Next operations, opposite rapid controls and direct
  Seek interleaving. No synthetic playback times, speculative synthesis,
  new cloud permissions or duplicate media streams introduced.
- Tests authored but **not run** (Flutter/Dart SDK unavailable).
  No Windows/Android builds or GitHub Actions started; verify lock-screen
  labels, focus and chapter-boundary behavior on an actual device.

### M2/Android — Compose external skips with direct pending Seek (2026-10-30)

- Exposed a read-only ReaderPlayer intended-navigation index for
  in-flight Seek/source-end operations. Only the current navigation
  revision owns the pending target; an interrupted or superseded Seek
  cannot leak an obsolete cursor.
- The Android media handler uses that target when a direct in-reader
  navigation is followed by a remote Previous/Next while native Stop
  is pending. This fixes interleaving that would otherwise step from
  the last *committed* cursor instead of the newer direct selection.
- Added deterministic pending/superseded Seek regression tests.
  Updated the mixed direct+remote media test in the preceding commit.
- Tests authored but **not executed** without Dart/Flutter.
  No build, release or GitHub Actions initiated.

### M2/Android — Real EPUB chapter transport navigation (2026-10-30)

- Wired the ReaderScreen's existing verified OPF spine chapter boundaries
  into ReaderMediaHandler at book attach. When EPUB chapters exist, remote
  Next/Previous now move between *narratable chapter starts*, not individual
  TTS chunks; PDF/TXT retain segment navigation. Previous from inside a
  chapter restarts its beginning, from the beginning selects the previous.
- Silent/illustrated spine items do not synthesize audio or create duplicate
  remote steps. The final chapter's Next reaches explicit silent speech EOF;
  no extra Play, cloud request or synthetic chapter timing is inferred.
- Binary-search target resolution, sorted deduplicated immutable boundaries
  and the existing native Stop/SQLite barriers protect rapid button presses.
  Remote intents clear after settlement, preventing old targets from being
  reused after natural speech advances. Direct reader navigation still wins.
- Remote chapter moves notify ReaderScreen after the winning Seek so the
  visual/source cursor, optional scrolling and a paused SQLite bookmark
  remain consistent; no second native seek or unsolicited synthesis.
- Authored Android media-handler regressions for real chapters, Previous
  semantics, rapid mixed chapter commands, silent duplicate starts and
  TXT book reattachment fallback. **Not run** without Dart/Flutter SDK.
  No Windows/Android build or GitHub Actions started; real device controls
  and visual EPUB behavior remain to be accepted manually.

### M2/EPUB — Source-exact remote chapter/illustration bookmarks (2026-10-30)

- Fixed external-media EOF navigation for books whose last narrated
  chapter is followed by illustrated-only OPF spine entries. UTF-16
  offsets can be identical across multiple silent image sections; an
  offset-only jump could display/save the wrong illustrated appendix.
- ReaderScreen now builds an immutable per-book map of actual narrated
  chapter starts to source offsets; at audio EOF it chooses the **first**
  trailing silent section with its unique spine `idref`. The visual
  viewport uses blockForSpine and the paused SQLite bookmark stores an
  EPUB-spine ReadingAnchor, so reopen preserves the correct illustration.
- Removed per-button O(chapter-count) source scanning in the remote
  navigation callback. Ordinary narrated chapters and TXT/PDF fallbacks
  retain their original source positions and completion semantics.
- Added pure navigation regressions for 20,000 long chapters, two
  illustration-only appendices at the same source offset, immutable
  target maps and ordinary book EOF, plus a real illustrated-layout
  identity test. Tests **written but not run** (Dart/Flutter unavailable).
  No Windows/Android build or GitHub Actions started.

### M2/EPUB — Verify silent appendices across layout and SQLite reopen

- Added an integration fixture with **two actual illustrated OPF
  appendices sharing one UTF-16 source offset**. Confirmed the intended
  first appendix resolves to its own progressive-layout tile and image,
  instead of the adjacent distinct illustration.
- Added SQLite restart regression for the paused remote-EOF bookmark:
  first trailing silent spine `idref`, EPUB anchor round trip, exact
  source position, no false interrupted-narration marker and completed
  TTS cursor (never replay the final audio clip).
- Tests authored but not executed: local Flutter/Dart SDK unavailable;
  no build, packaging or GitHub Actions started.

### M2 — Prevent older speech acknowledgments overriding visual bookmarks (2026-10-30)

- Added an in-process per-book manual-position revision to LibraryStore.
  Successful manual/visual `savePosition` writes increment it; internal
  speech checkpoints do not. No new SQLite schema or migration required.
- NarrationRecoveryBinding captures that revision after checkpointing the
  start of the audible segment. A delayed completed-segment callback that
  resumes after the user saved a newer manual bookmark cannot move the
  durable book progress back to its older audio destination. Native audio
  completion can still advance its own in-memory cursor.
- ReaderScreen now discards a superseded in-reader `_select` after the
  serialized Seek returns, before persisting or repainting an obsolete
  visual bookmark. Latest manual selection and current player destination
  must still agree. Explicit source-exact EPUB/spine anchors are retained.
- Added SQLite regressions for a delayed completed-speech callback racing
  a manual bookmark, durability across database reopen, and a fresh Play
  properly superseding that older manual bookmark. Tests not executed
  (Dart/Flutter unavailable); no build, release or GitHub Actions started.

### M2 — Unified in-reader source stepping and reliable EOF (2026-10-30)

- Reused ReaderScreen._select for Left/Right and onscreen Previous/Next.
  It owns the serialized native Stop, supersession checks, exact source
  bookmark persistence and EPUB visual checkpoint; the old _move wrote
  unguarded positions after possibly superseded awaits.
- ReaderPlayer.sourceStepDestination composes consecutive user controls
  from the most recent *intended* Seek instead of stale currentIndex,
  including one deliberate silent EOF position. Next from the last spoken
  segment now stops cleanly and saves source EOF; another Next at settled
  EOF is a no-op; Previous moves to the final audible segment.
- Expanded _select's explicit source-EOF handling to TXT and PDF. EPUB
  source EOF selects the first trailing illustrated OPF spine by ID, not
  a same-offset but different appendix. The EPUB EOF lookup is linear
  only when needed, without building a per-book Android navigation map
  for Windows or each in-reader button press.
- Prevented viewport callbacks and delayed scroll-timer writes while
  ReaderPlayer is temporarily non-playing but **not settled idle**
  (pending Stop, auto-resuming Seek or speech completion checkpoint).
  These frames must not replace the crash recovery anchor.
- Added deterministic player and EPUB pure lookup regressions for
  rapid intents, EOF, and shared-offset illustrated appendices.
  Tests **authored but not executed** without Dart/Flutter SDK.
  No Windows/Android builds, releases or GitHub Actions started.

### M2 — Compare and select installed free system voices (2026-10-30)

- Added explicit Windows/Android `Speech engines` preview for the
  actual installed OS voice catalog, with fixed local sample text,
  language-appropriate samples, user-selected voice persistence and
  interpreted-vs-native Windows punctuation comparison.
- Native samples are isolated from the active book player; selection is
  written only when explicitly saving book speech preferences. Stop,
  provider changes and screen disposal invalidate pending catalog,
  voice choice and speak requests; a native stop barrier prevents
  overlapping preview engines. No book text or cloud credentials enter
  the preview workflow.
- Fake-engine regressions added for catalog deduplication, installed
  voice validation, language choice, blocked catalog/voice operations,
  Stop/Dispose and missing voices. Flutter/Dart tests **not executed**,
  native voice quality unverified. No Actions, builds or releases run.

### M2 — Persist chosen system voice across app restart

- Added SQLite integration test: selecting one installed OS voice in
  per-book SpeechPreferences survives LibraryStore close/reopen and
  retains voice identity across both free system punctuation modes.
  Switching to cloud preferences explicitly clears the stale OS voice.
- Manual native playback acceptance remains open; no TTS SDK was available
  in this environment, so the tests are source-only and not executed.

### M2 — Explicit system narrator / local voice language filter (2026-10-30)

- Free installed Windows/Android voices can now be browsed by primary
  language (including all installed languages), without network discovery,
  cloud cost or a spoken book preview.
- The voice picker always includes `Automatic — match book language`:
  opening or refreshing the settings screen does **not** silently select
  the first installed voice matching the current book locale.
- Explicit per-book voices are restored only if actually installed;
  a missing/deleted voice does not silently become a different narrator.
  A user-selected reset to Automatic survives a catalog refresh and the
  SQLite preference round-trip, while the existing installed preview and
  Save controls continue to require deliberate user action.
- Added deterministic catalog language/filter/explicit-identity tests,
  plus SQLite reopen test for reset to unpinned system narration.
  Flutter/Dart tests authored but **not run**; no Windows/Android builds
  or GitHub Actions started.

### M2 — Voice locale fidelity and more free preview languages (2026-10-30)

- When a user explicitly pins an installed Windows/Android system voice,
  the selected voice's locale now accompanies the generated utterance,
  even when it differs from the imported book language. Book metadata and
  saved per-book language are not silently rewritten. Without an explicit
  voice, the automatic narrator still uses the book's locale and the
  matching-installed-first resolver.
- Missing cast voices fall back to that explicit narrator's locale;
  multi-language cloud voices and verified cast locale resolution retain
  their prior behavior. No extra synthesis, cloud fallback or new cost.
- Extended source-independent, local audition samples to Dutch, Polish,
  Swedish, Russian, Japanese and Chinese.
- Added fake-engine locale regressions for explicit narrator, reverting
  to automatic mode, and unavailable cast voice, plus six sample tests.
  Flutter/Dart tests **authored but not run**; no build or GitHub Actions.

### M3 — Comparable system/neural offline preview and native Stop barrier (2026-10-30)

- Free sherpa/VITS previews now use the exact same short, fixed
  locale-specific public phrase as the free system-voice audition.
  Expanded offline sample coverage to the supported language scripts
  without sending book passages or initiating any cloud operation.
- Fixed a native ownership race: Stop during asynchronous ONNX
  `chooseVoice` cancels pending speech immediately, but now waits for
  that Play call to unwind before disposing the native engine. A later
  preview waits on the serialized Stop/disposal barrier.
- Added regressions for Stop during a blocked native choice, absence
  of late synthesis, exactly-once model disposal, and consistency
  of sample text across twelve languages.
- All samples still require manual opt-in and verified local models.
  Experimental neural runtime remains **Windows only**; no Android
  model activation, automatic downloading, build or GitHub Actions.
  Tests authored but not run (Flutter/Dart SDK unavailable).

### M3 — Filter installed neural packs without hiding corrupt models (2026-10-30)

- Added a local language filter to the offline VITS/Piper model manager.
  It derives normalized primary languages only from inspected, verified
  pack manifests. All-language mode remains the default and refreshes
  invalidate stale filters when a pack is removed.
- Corrupt/incomplete models remain visible with their unavailable warning
  under **every** language filter; a filter never bypasses SHA verification,
  guesses a model language or enables an experimental engine.
- Added pure catalog filter tests and a Flutter widget test with two
  real locally installed manifests plus a damaged directory. None of
  these tests invokes an ONNX runtime, makes network requests or calls
  GitHub Actions. Flutter/Dart tests not executed in this environment.

### M3 — Verified offline model storage diagnostics (2026-10-30)

- Offline voice manager now reports each installed pack's verified
  model/tokens/manifest/phonemizer file bytes and the total across ready
  packs. No audio decoding, ONNX model load, network request or file
  content persistence is needed to display these local metrics.
- Sizes are collected **after** the existing SHA-256 checks and only
  for exact manifest-allowlisted files. If a pack changes or cannot be
  fully inspected, it remains unavailable with unknown size; corrupt
  directories and interrupted temporary staging are deliberately not
  counted as verified storage.
- The total updates after user-requested installation/removal and does
  not change when a language filter hides other healthy packs.
  A file-size sum is not promised as exact filesystem allocated blocks
  or free disk space.
- Added unit tests with real local files and a deliberately corrupt pack,
  deterministic byte-label tests, and widget assertions for displaying
  and clearing the summary after removal. Tests authored but not run
  (Flutter/Dart SDK unavailable). No builds or GitHub Actions started.

### M3 — Crash-safe recovery for curated neural download staging (2026-10-30)

- Paola installation now obtains an exclusive OS lease and writes an
  exact app-private stage marker **before** downloading/extracting.
  The normal finally block removes its own stage and releases the lease;
  a crash leaves a marked, unlocked stage recoverable after 24 hours.
- Added bounded, explicitly invoked recovery limited to the dedicated
  voice-downloads parent, matching Paola-only stage names, exact marker
  contents, age, no live in-process session and an exclusive OS lock.
  Refuses unknown top-level entries, links and excessive extraction trees;
  never touches installed ONNX packs, unrelated files or legacy unmarked
  folders. No background cleanup, network calls or auto-downloads.
- Added Dart tests for abandoned/live/recent stages, malformed markers,
  unknown files, symlinks and idempotent completion. Flutter/Dart tests
  are authored but not executed; native Windows locking still needs
  on-device acceptance. No builds or GitHub Actions.

### M3 — Explicit Windows cleanup command and stale-stage tests

- Added **Clean interrupted voice downloads** to the Windows offline
  voice manager. A confirmation dialog explains its exact private Paola
  staging scope, 24-hour minimum age and exclusion of installed models,
  active downloads and unmarked legacy content. The action reports
  only a count, never filesystem paths or archive data.
- Verified stale vs recent stage eligibility with real file timestamps,
  and strictly bounded cleanup of a nested extracted-model fixture.
  The cleanup is user-initiated, not run on book import or app startup.
- Test code added; Dart/Flutter and native Windows lock behavior not
  executable here. No builds or GitHub Actions initiated.

### M3 — Bounded repeated cleanup acceptance

- Added a deterministic 19-session fixture confirming that a single
  manual recovery invocation deletes at most the configured 16
  candidates; a second invocation handles the remaining 3. No unmarked
  files or installed voice assets are involved. This test is source-only
  and not yet executed under Dart/Flutter or Windows filesystem locks.

### M3 — Recoverable manual VITS/Piper staging (2026-10-30)

- Manual import now creates a privately marked, OS-leased `.install-*`
  parent and copies SHA-verified assets into `payload/`. Only the payload
  directory is atomically promoted to the verified installed voice ID;
  marker and lease metadata stay outside the installed model package.
- Added explicit in-app **Clean interrupted local model imports** with a
  confirmation dialog. Only aged (24h+), correctly marked, OS-unlocked,
  allowlisted, bounded abandoned work dirs are eligible. Unmarked legacy
  temp folders, installed model IDs, active imports, source voice folders
  and any suspicious/symlinked structures are preserved.
- Recovery scans up to 512 direct entries and attempts at most 16 stages
  per user action. Files are removed individually with a type recheck,
  nested folders only after emptied; no arbitrary recursive user-folder
  deletion. No network or model activation.
- Added pure crash/active/symlink/batch fixtures and a Flutter widget
  confirmation test; source reviewed, not run (Dart/Flutter unavailable).
  No Windows/Android builds or GitHub Actions started.


### ER-033 — Statistiche, tempo di lettura e obiettivo locale (2026-10-30)

- Aggiunto il pannello Reading stats con conteggi su tutti i libri (indipendente
  dai filtri attivi), grafico di completamento manuale, ultimi aperti e formati.
- Nuovo SQLite **v23**, preservando le migrazioni precedenti: aggregati di
  secondi per giorno locale/libro e modo visivo/TTS, più obiettivo personale
  0–240 minuti (20 predefinito). Nessun testo, log di eventi o telemetria cloud.
- Campionamento a tempo monotono, intervalli limitati a 30 s, precedenza audio
  per non contare due volte, inattività visiva oltre tre minuti ignorata,
  pausa/visibilità e Android MediaSession considerati.
- Dashboard di sette giorni e controllo obiettivo; backup SQLite contiene
  questi valori, ma il restore add-only non li importa. Accetta v17–v23.
- Test di migrazione, aggregazione, limiti, cascade e UI aggiunti ma **non
  eseguiti**. Nessuna compilazione Windows/Android né GitHub Actions.
- La stima precedente del piano è datata e non viene aumentata senza QA nativa.

### ER-033 — Classifica settimanale e dettaglio di ciascun libro

- Elenco dei dieci libri con maggiore attività negli ultimi sette giorni
  locali, ordinato per somma visuale+TTS; parità risolta in modo stabile.
  Toccare un libro mostra tempo totale storico, visuale/TTS separati e
  dettaglio degli ultimi sette giorni.
- Query parametrizzate, aggregazione SQL e limiti 1–50; nessuna scansione
  dei testi, cambio di consensi, nuova migrazione o rete.
- Test di separazione bookId, ordinamento, limiti, eliminazione/foreign key,
  durata inferiore al minuto e navigazione widget scritti, **non eseguiti**.
  Nessuna build o workflow Actions avviati. Percentuali milestone invariate
  senza prove native.

### ER-033 — Cancellazione dati aggregati e precisione inattività

- Comandi con dialoghi di conferma per eliminare il tempo di lettura/TTS
  dell'intera biblioteca oppure del singolo libro; l'obiettivo e i
  progressi di lettura rimangono invariati. Storico dei backup preesistenti
  escluso dalla cancellazione; non si tratta di un secure erase.
- Il timer visivo usa ora un budget d'inattività catturato all'inizio di
  ogni campione per non registrare l'intera coda del campione dopo i tre
  minuti dal gesto. I campioni TTS restano distinti.
- Test unitari SQLite, limite d'inattività e dialoghi UI preparati ma non
  eseguiti. Tracciamento di nuove sessioni ancora automatico.

### M3 — Read-only diagnostics for interrupted manual model imports (2026-10-30)

- Added an explicit **Inspect interrupted local imports** action in the
  offline neural voice manager. Its read-only summary separates potentially
  eligible aged workspaces, recent imports, active/locked operations, and
  unrecognized or suspicious folders. No private file paths, source names,
  book text, or model contents are displayed or stored.
- Eligibility requires exact app markers, age, exclusive lease availability,
  and allowlisted file structure. Inspection handles at most 512 direct
  entries and 16 candidate sessions, rotates candidates on repeated checks,
  and flags incomplete sampling instead of claiming exhaustive coverage.
- The independent destructive cleanup still requires explicit user consent;
  diagnostic status is a snapshot, not permission or a deletion guarantee.
- Added Dart and Flutter tests covering lifecycle categories, hard limits
  and absence of filesystem mutation. Source changes committed, but
  Flutter/Dart tests and Windows lock acceptance **not yet executed**.
  No builds or GitHub Actions.


### ER-033 — Opt-out persistente e blocco registrazioni (SQLite v24)

- Nella schermata statistiche aggiunto lo switch **Track reading and TTS
  time**. L'impostazione sopravvive a riavvii e migrazioni da SQLite v23.
  Per compatibilità con l'attuale comportamento, il valore iniziale è On.
- Con Off il reader non crea il timer locale delle statistiche; anche
  `LibraryStore.recordReadingActivity` verifica il flag e ignora scritture
  arrivate in ritardo. Nessun TTS viene fermato dall'impostazione.
- Conservati storico precedentemente registrato e obiettivo giornaliero.
  Riattivando, si registrano soltanto attività future. La cancellazione
  dello storico resta un comando distinto, con conferma.
- Preview backup accetta v17–v24; la copia SQLite privata include il flag,
  mentre il ripristino add-only non lo importa né modifica i consensi.
- Test di upgrade v23→v24, marker ripristinato, UI, restart e copia di
  backup predisposti ma non eseguiti. Nessuna compilazione o Actions.

### M3 — Diagnostica degli errori TTS offline (2026-10-30)

- Introduced `offline_voice_install_diagnostics.dart`, a pure, bounded
  error-to-guidance translator for local VITS/Piper model inspection,
  user-approved import, curated Paola download and model removal.
  Diagnoses include SHA-256/metadata mismatch, incomplete or unsafe
  packages, resource limits, tar extraction failures, download/network
  issues, disk-full, access-denied, and locked native model files.
- The voice manager now displays stable, actionable, localized-to-operation
  error advice instead of one overly generic failure string. Raw exception
  messages, OS paths, model URLs, source book data and stack traces are
  never concatenated into the user-facing message; unknown failures receive
  a conservative generic fallback. No automatic retry or cloud fallback.
- Added pure regressions for failure categories, Windows/Unix OS error
  codes and redaction of user/private paths, plus Flutter widget coverage
  for a tokens.txt checksum modified AFTER the import preview. The latter
  verifies that the source file remains intact and no model is installed.
- Tests are authored but **not run** (Flutter/Dart SDK not available).
  No Windows/Android packages or GitHub Actions were started.

### M3 — Incremental offline voice catalog reconciliation (2026-10-30)

- User-approved manual installation, curated Paola download and model
  removal now reconcile **only the affected voice ID** instead of
  SHA-256 rehashing all ONNX models after every operation. A targeted
  inspection reopens and verifies the changed model (including its exact
  manifest, tokens and phonemizer assets) and measures verified bytes.
  Absent models disappear; incomplete or damaged models remain visible
  as unavailable, even when the triggering mutation failed.
- The targeted result is merged into an immutable sorted catalog snapshot,
  preserving other models, total storage counts and language filtering.
  If the last voice for the selected language is removed, the filter
  returns to All; other entries do not undergo another expensive hash.
- The explicit **Refresh local voices** action continues performing
  comprehensive verification, including any external filesystem changes
  to unrelated models. No background scans, network, automatic model
  downloads, native synth initialization, cloud fallback or builds.
- Added pure Dart tests for targeted install, removal, damaged-model
  demotion, stable sorting, immutable snapshots and disk totals, plus
  Flutter widget verification that a second local voice appears without
  removing or hiding an existing one. Tests not executed without
  the Dart/Flutter SDK; no Windows/Android build or GitHub Actions.


### ER-034 — Ricerca avanzata offline nella biblioteca (2026-10-30)

- Nuovo parser `lib/domain/library_search_query.dart`: ricerca a più
  parole con AND, frasi tra virgolette, prefissi `title:`, `author:`,
  `series:` (senza distinzione maiuscole/minuscole). Preservate le
  vecchie ricerche per sottostringa e tutte le combinazioni con filtri
  formato, preferiti, stato e collezioni.
- Limiti intenzionali di 256 caratteri UTF-16 e 16 termini; query
  incomplete o malformate segnalate nella UI senza risultati ingannevoli.
  Icona Help con esempi e conferma che l'app non cerca né carica i testi
  integrali dei libri.
- Nessuna nuova tabella, network, spesa API o modifica di lettura/TTS.
  Il vero FTS5 offline sui contenuti rimane un incremento distinto,
  potenzialmente opt-in e da qualificare sulle risorse del dispositivo.
- Test di parsing, catalogo e UI scritti ma non eseguiti;
  nessuna build Windows/Android né GitHub Actions avviata.

### M3 — Session-only offline TTS preview performance diagnostics (2026-10-30)

- Free Windows neural-voice preview now captures monotonic, in-memory
  per-request timing for verified pack load/SHA-256, voice selection,
  speech duration (including full playback and WAV cleanup) and Stop
  through native engine disposal. Cancelled, failed and completed attempts
  are explicitly distinct. No persistent performance database or logs.
- Existing Sherpa VITS native diagnostics supply separate **synthesis**
  and **WAV decoder handoff** timings and a point-in-time **whole-process**
  RSS snapshot. These only appear when the engine reports real values,
  never for the generic/system TTS abstraction. None is claimed to be
  exact acoustic onset or memory attributable to the model alone.
- The model manager presents the latest demonstration results under their
  respective local voice cards (up to 12 recent voices in memory).
  A removed or damaged voice loses stale measurements; explicit full
  catalog refresh keeps independent SHA-256 verification semantics.
  Existing preview consent, cancellation and exclusive Stop/dispose remain.
- New deterministic fake-engine and widget tests cover full preview timing,
  the native diagnostics seam, Stop and disposed-model cancellation,
  failure status and private-path exclusion. Tests **not executed**:
  Dart/Flutter SDK is unavailable in this runtime. No Windows/Android
  packages, release or GitHub Actions started.


### ER-034 — Raccolte intelligenti dinamiche (2026-10-30)

- SQLite **v25** memorizza regole JSON validate in
  `smart_book_collections`. Nessuna tabella di membership materializzata:
  i libri sono filtrati dinamicamente a partire da metadati, preferiti,
  scaffale manuale, formato, query avanzata e apertura pregressa.
- Editor dalla gestione delle raccolte con creazione, modifica, conferma
  eliminazione, validazione del nome/criteri e integrazione nella tendina
  Collection. I filtri della raccolta sono combinati con i filtri
  temporanei già presenti nella biblioteca.
- Restano separate le collezioni manuali. Upgrade v24→v25 senza
  modifica ai progressi, al TTS o ai file locali. I backup SQLite
  conservano le regole, ma il restore portabile add-only non le importa
  senza un futuro formato manifest e consenso esplicito.
- Test di dominio, SQLite, interfaccia e copia di backup predisposti,
  **non eseguiti**. Nessuna build Windows/Android o GitHub Actions.

### M3 — Low-latency VITS startup and Stop, safe WAV housekeeping (2026-10-30)

- The first audible VITS utterance now opens its own OS-leased,
  app-marked WAV session **before** starting the bounded orphan-WAV
  recovery sweep. Previous synchronous recovery could stall first audio
  while Windows or a slow disk enumerated temporary files. Recovery
  now runs independently, still using strict ownership markers,
  link rejection, a bounded candidate scan, in-process live-session
  registry and exclusive OS lease. A recovery failure cannot cancel
  otherwise valid speech. No file paths are logged or uploaded.
- After native audio output has acknowledged **Stop**, bounded deletion
  retries for previously locked WAVs are no longer on the UI-facing
  Stop critical path. The existing `OfflineWavCleanup` serializer
  and `ensureCapacity()` barrier prevent a subsequent Play from
  bypassing the WAV cleanup capacity gate. Dispose continues to await
  pending cleanup as needed before releasing the private session lease.
  Native output is stopped **before** any cleanup is scheduled.
- Added fake slow-filesystem tests to prove first playback succeeds
  while orphan recovery is blocked, Stop can return while an old WAV
  cleanup is blocked, next Play waits on that cleanup, and actual
  background recovery can delete an abandoned marked session without
  touching the current OS-locked session. The same tests assert that
  housekeeping exceptions never block valid audio.
- Optimization is structural, **not** a measured Windows-device
  speedup. The benchmarks and native audio/Stop acceptance remain
  necessary before claiming latency improvements. Flutter/Dart SDK is
  unavailable here, so these tests were authored but not executed.
  No Windows/Android builds or GitHub Actions were started.

### M3 — Measured cold native ONNX initialization vs warm synthesis (2026-10-30)

- The native VITS isolate now reports a **worker-local** monotonic
  measurement of sherpa binding initialization plus ONNX model construction
  in its timed ready handshake. The main isolate separately measures
  **worker ready** wall time including isolate spawn and scheduling.
  This does not measure exact first audible sample.
- Existing injected / legacy workers that return only a SendPort remain
  compatible: their native initialization duration stays **unknown/null**,
  never inferred or reported as zero. Invalid negative timings are ignored.
- The engine records first successful readiness once per resident worker,
  not per synthesized phrase. Previous model measurements are cleared
  when a new model is constructed; the current three-minute idle timeout
  and immediate Stop model retirement are unchanged.
- Preview reports can display worker readiness, native ONNX init and
  synthesis as **three distinct, optional timings** alongside existing
  SHA, playback and Stop metrics. All are short-lived numeric statistics,
  with no book passages, paths, API keys or persistent telemetry.
- Synthetic worker, engine and diagnostic tests verify cold/warm reuse,
  restart after Stop, old worker compatibility, resets and UI formatting.
  Flutter/Dart tests not executed here (SDK unavailable). No Windows/
  Android builds or GitHub Actions started.

### M3 — Separate worker WAV generation from cold-load overhead (2026-10-30)

- The persistent VITS worker success response now carries the **actual
  worker-local generate + WAV-write duration**, measured after ONNX
  initialization. Older workers returning the original two-field reply
  are still supported; their native generation duration remains unknown.
  No private audio content, local path, book passage or error stack
  is sent as part of these timing messages.
- Cold-load reporting now separates **worker ready** (includes spawning
  and message scheduling), **native model init** (worker-local Sherpa
  bindings + ONNX loading) and **worker WAV generation** (no model
  initialization or audio playback). The pre-existing caller-side
  synthesis stopwatch necessarily overlaps with cold initialization;
  it is accurately labeled **Synthesis path incl. startup** rather
  than presented as an independently additive native synthesis number.
- Existing three-minute resident model idle timer, Stop cancellation,
  voice verification and bounded WAV cleanup remain unchanged.
- Added pure Dart regression cases for old and extended reply formats,
  cold and reused workers, reset of model metrics and preview formatting.
  Source updates only: no Dart/Flutter SDK available to execute tests,
  no Windows/Android build and no GitHub Actions.


### ER-034 — Primo indice full-text locale a consenso esplicito (SQLite v26)

- SQLite v26 aggiunge esclusivamente configurazione opt-in (default Off)
  e marcatori di lavorazione per libro. La tabella virtuale FTS5 contenente
  il testo **non viene creata prima del consenso**.
- La finestra `Search inside books` della biblioteca permette On/Off,
  scansione esplicita di 10 libri alla volta (massimo API 20), avanzamento,
  cancellazione cooperativa fra libri, reset e ricerca per termini Unicode
  letterali combinati con AND. Estratti limitati a 30 libri.
- Ricicla l'estrattore comune TXT/EPUB/PDF text layer; nessuna OCR. Limiti
  di 12 MiB per file, 2 Mi caratteri UTF-16 per libro e 64 MiB per
  contenuto complessivo indicizzato. Libri troppo grandi, assenti,
  PDF scannerizzati e fonti non leggibili vengono saltati.
- Disattivando si elimina la tabella FTS5 e i marcatori, ma non si
  garantisce cancellazione crittografica da WAL/file system o backup
  esportati. Il backup privato SQLite può contenere il testo indicizzato;
  ripristino portabile add-only non abilita un indice a destinazione.
- Nuovi test di regressione SQLite, migrazione v25→v26, batch,
  cancellazione e UI predisposti, **non eseguiti**. Nessuna build nativa
  o GitHub Actions. I risultati aprono per ora il libro alla posizione
  salvata: navigazione precisa al match, cancellazione intra-PDF
  e ottimizzazione di corpus grandi sono lavori successivi.

### M3 — Opt-in same-phrase cold/warm neural voice comparison (2026-10-30)

- Offline voice manager offers a separate **Compare cold/warm** action for
  installed, SHA-verified Windows neural models. An explicit confirmation
  warns that the SAME short public demonstration phrase is spoken **twice**
  (audibly), using the same local engine. No books, personal passages,
  cloud calls, model downloads or hidden/background prewarming are used.
- Only a completed two-phrase run produces a comparison, with first and
  second wall-clock times (both include playback), and separate optional
  native worker WAV-generation and synthesis-path times. Actual native
  model reuse is shown as confirmed only when the engine reports exactly
  two successive syntheses without another model load; worker restarts
  and missing native statistics never produce a false reuse claim.
- The explicit Stop button invalidates the session epoch and cancels
  the second phrase if the first is stopped; stopping during the second
  also discards the incomplete comparison. Existing serial native disposal,
  per-voice last-report LRU (12 entries), fixed demo text and memory-only
  reporting remain. Standard Play still speaks exactly once.
- The resident worker's 3-minute inactivity retirement and Stop
  cancellation policy were **not** changed: any automatic model warming
  would need an additional, separately approved design after measuring
  actual cold/warm latency and whole-process RAM on Windows.
- Added unit/controller tests for complete comparison, model reuse,
  unexpected reload, generic engines without native statistics, both
  Stop cancellation phases, and one-play backward compatibility, plus
  UI consent and two-audible-plays tests. Tests **not executed** here
  because Dart/Flutter SDK is unavailable. No platform builds or Actions.


### ER-034 — Navigazione FTS su offset verificato e refresh incrementale (2026-10-30)

- La ricerca nell'indice FTS5 produce una posizione UTF-16 candidata per
  una parola *intera*, derivata dal testo canonico indicizzato. Il reader
  confronta il testo del risultato con quello appena decodificato:
  posizionamento visuale su EPUB/TXT, modalità testo per PDF con text layer;
  se non coincide apre il checkpoint già salvato con messaggio esplicativo.
- La navigazione iniziale non salva un nuovo segnalibro e non avvia
  TTS. Per EPUB sono riutilizzati blocchi visivi, evidenziazione e
  checkpoint visivo temporaneo che protegge gli anchor dalle prime
  notifiche della lista. Le ricerche multi-termine sono ora risolte sul
  passaggio più ravvicinato (entro 320 caratteri UTF-16): scansione
  lineare alla selezione del singolo risultato, memoria O(numero termini),
  senza rileggere ogni libro a ogni carattere digitato. Se i termini
  risultano troppo distanti si usa la prima parola intera.
- Nuova azione manuale `Check changed books` dentro la finestra FTS.
  Usa solo dimensione e data di modifica dei file per invalidare l'indice
  di fonti alterate e reinserirle in coda. Le fonti immutate e le relative
  righe indicizzate non vengono riscritte. Nuovi import sono già pending.
  Lo scan è cancellabile tra libri; nessuna attività automatica o cloud.
- Aggiunta `library_fulltext_source_state` (solo stato locale fonte) in
  SQLite v26; la tabella non copia nuovi testi e viene cancellata allo
  spegnimento dell'indice. Compatibilità con database v26 attivati prima
  dell'aggiunta tramite creazione idempotente al prossimo comando FTS.
- Test dominio/store/UI per validazione dell'offset, rifiuto risultati
  obsoleti, cancellazione, aggiornamento selettivo e riavvio preparati,
  non eseguiti. Nessuna build Windows/Android né GitHub Actions.

### ER-034 — Pertinenza multi-termine e verifica del contesto (2026-10-30)

- Il salto full-text alla selezione identifica la finestra più corta
  contenente tutte le parole distinte entro 320 unità UTF-16, anche in
  ordine inverso; in parità vince la prima. Se non vi è una finestra
  sufficientemente vicina, resta il fallback prudente alla prima parola
  completa. La scansione usa memoria limitata al numero di parole (max 8).
- Insieme all'offset viene catturato **solo in memoria** un contesto
  limitato prima/dopo la parola (per i multi-termine include l'intero
  passaggio scelto). Il lettore confronta anche questo contesto sul testo
  nuovamente estratto; una parola invariata allo stesso offset non basta
  se il testo circostante è stato riscritto.
- Test di dominio per prossimità, ordine inverso, parità, emoji,
  duplicati, fallback distante e contesto modificato. Test di integrazione
  sul catalogo SQLite per selezione del passaggio, indici obsoleti e
  nessuna alterazione dello stato di lettura.
- Stato: modifiche committate; test Dart/Flutter e build native **non
  eseguiti**; nessuna GitHub Actions avviata.
