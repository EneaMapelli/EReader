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
| **M0 — Fondazione e POC** | **60%** | Flutter/Dart modulari, SQLite con migrazioni fino a v17, parser e adattatori, bootstrap Windows/Android, runner e CI manuale | Progetti nativi generati fuori da Git; POC realmente passati su Windows e Android, ABI/minSDK/licenze, corpus EPUB/PDF e voci sherpa-onnx native |
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
| ER-033 Statistiche/obiettivi | Non implementato |
| ER-034 Libreria massiva/collezioni/FTS | Parziale: filtri/ordinamento e ricerca metadati; niente raccolte smart/FTS dell'intera biblioteca |

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

