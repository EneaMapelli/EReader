# EReader — Architettura tecnica e contratti

**Versione:** 1.0 · 2026-10-22 · [Piano generale](DEVELOPMENT_PLAN.md)

## 1. Scelta architetturale

**Modular monolith local-first in Flutter/Dart**, con adapter per OS, parsers, TTS, LLM e storage. Un unico dominio indipendente da Flutter renderizza il contenuto in blocchi semantici con riferimenti all'origine. Evitare la dipendenza diretta tra widget, provider esterni e parser.

    UI (Flutter)
      Library / Reader / Player / Voices / Book Analysis / Settings
                |
      Application use-cases / State
       Import | Navigate | Segment | Cast | Synthesize | Play
                |
      Domain contracts and immutable models
        Book, SourceAnchor, TextSegment, Character, VoiceProfile
          /            |              |             \
    DocumentAdapters  TTSEngines     LLMAdapters     DataRepositories
     EPUB/PDF/TXT    system/ONNX/     local/cloud    SQLite/files/secure
                      cloud

**Code organization candidate:**

    lib/
      app/                      app shell, navigation, DI, state
      features/library/
      features/reader/
      features/player/
      features/voices/
      features/analysis/
      features/settings/
      core/domain/              value objects, use cases, errors
      core/documents/           BookImporter, EPUB/PDF/TXT adapters
      core/segmentation/        deterministic splitter + anchors
      core/tts/                 engine interface, queue, cache
      core/llm/                 extraction interface and validators
      core/audio/               playback, media session
      core/storage/             database, migrations, files, secrets
    assets/
    test/
    integration_test/
    test/fixtures/
    docs/
    scripts/

Nessun \`flutter_tts\`, \`sherpa_onnx\`, HTTP SDK o libreria PDF deve comparire nelle interfacce di dominio: tenerli negli adapter concreti.

## 2. Contratto documentale

Un \`DocumentAdapter\` espone:

- \`canOpen(magicBytes, extension, mime)\` → compatibilità verificata.
- \`open(bookUri)\` → \`DocumentHandle\`, metadati, indice e risorse.
- \`listChapters()\`, \`extractText(chapterId)\` → \`TextBlock[]\` con struttura preservata.
- \`resolveAnchor(SourceAnchor)\` → posizione nel viewer; \`anchorForSelection(...)\`.
- \`render(chapter/page)\` → view model/rendering isolato dall'estrazione testuale.
- \`close()\` per file handle/resource cleanup.

\`SourceAnchor\` è una unione tipizzata:

- EPUB: \`spineItemId\`, \`epubCfi?\`, \`blockId\`, \`textStart\`, \`textEnd\`;
- PDF: \`pageNumber\`, \`textStart\`, \`textEnd\`, \`rects?\`;
- TXT: \`byteOffset?\`, \`codepointOffset\`, \`length\`.

Usare **offset Unicode ben definiti** (scelta da fissare nei serializer: codepoint vs UTF-16) e test per emoji/combining marks. Memorizzare anche \`contentHash\`, \`extractionVersion\`, \`normalizationVersion\` e range originali: per evitare che una migrazione o un nuovo parser sposti le annotazioni.

**Import sicurezza:** analisi magic bytes, limite file/decompression ratio, path traversal ZIP, riferimenti a risorse esterne, file X(HT)ML sanitizzati, script e remote fonts disabilitati, nessuna esecuzione di codice da ebook. OCR e trasformazioni restano adapter indipendenti.

**EPUB renderer:** valutare viewer XHTML sandbox con WebView sicura vs renderer Flutter. Testare CSS, TOC, note, immagini, posizione dopo cambio font, WebView Windows e Android; scegliere l'implementazione tramite POC M0. Non assumere che il parser \`epubx\` fornisca un renderer completo.

**PDF:** \`pdfrx\` per visualizzazione, con POC esplicito per testo, mapping selezione/range e ordine reale di lettura. Per PDF problematici fornire cambio ordine/manual reflow o segnalazione. Non sintetizzare un PDF scansito senza OCR.

## 3. Segmentazione e sincronizzazione

Pipeline invariabile:

    original document → ordered text blocks → canonical text
       → sentences/dialogue spans → atomic TextSegments
       → speaker assignment → synthesis request → audio chunk
       → playback position → viewer highlight by SourceAnchor

\`TextSegment\` include \`id\`, \`bookId\`, \`chapterId\`, \`range\`, \`textVerbatim\`, \`speakerId?\`, \`language\`, \`normalizationVersion\`. L'eventuale normalizzazione per TTS (es. numeri, abbreviazioni) deve essere **reversibile/tracciata**, non modificare il testo mostrato e non cambiare i speaker span.

Diverse virgolette, trattini di dialogo e dialoghi inline nello stesso paragrafo richiedono split senza perdita di caratteri. Gli spazi e i separatori non letti sono anch'essi tracciati, così che \`join(segments)\` ricostruisca il testo previsto. Le porzioni non pronunciabili (immagini/formule) vanno marcate e non semplicemente perse in silenzio.

Timeline di playback: \`segmentId, audioStartMs, audioEndMs, wordMarks?\` e mapping verso SourceAnchor. Sui provider senza timestamps, evidenziare per segmento; non inventare sincronizzazione parola-per-parola. Il caching deve conservare versione del mapping e dei marks.

## 4. Contratti TTS

Interfaccia orientativa (pseudo-Dart):

    abstract interface class SpeechProvider {
      String get providerId;
      Future<SpeechCapabilities> capabilities();
      Future<List<SpeechVoice>> listVoices(String locale);
      Future<SpeechResult> synthesize(SpeechRequest request, CancellationToken cancel);
      Future<void> validateConfiguration();
    }

\`SpeechCapabilities\`: \`languages, voices, supportsPitch, supportsRate, supportsStyle, supportsEmotion, supportsSsml, supportsStreaming, supportsFileSynthesis, supportsWordMarks, supportsPause, limits, pricingUnit\`. Popolare capabilities a runtime/versione; nessuna UI abilita un'opzione non supportata.

\`SpeechRequest\`: \`sourceSegmentId\`, \`verbatimText\`, \`effectiveSpeechText\`, \`language\`, \`modelId\`, \`voiceId\`, \`rate\`, \`pitch?\`, \`volume?\`, \`style?\`, \`instructions?\`, \`outputFormat\`, \`deadline\`, \`providerOptions\`, \`idempotencyKey\`.

\`SpeechResult\`: stream audio oppure file/cache reference, \`audioDuration?\`, \`wordMarks?\`, \`usage?\`, \`billingEstimate\`, errori tipizzati e metadata di versione. Gli engine OS spesso sono *live TTS*, non generano file su tutte le piattaforme: gestire un risultato \`NativePlaybackHandle\` alternativo senza fingere che sia un audio file.

**Separare AudioPlayback:** enum stato \`idle | buffering | playing | paused | seeking | completed | error\` con transizioni e cancellazione; queue manager unica; rate limiter e prefetch; supporto audio focus e media session del sistema operativo.

### 4.1 Adapter previsti

- **SystemTtsAdapter:** \`flutter_tts\`; Android e Windows. Capabilities e comportamento delle voci differiscono, così come accuratezza pause/offset.
- **OnnxSpeechAdapter:** \`sherpa_onnx\`; supporto Windows/Android; ModelManager verifica checksum, spazio libero e licenza dei modelli, e permette la rimozione.
- **OpenAiRealtimeAdapter:** protocollo/sessione Realtime, text-only input e audio output verificati in POC. *Non* usare il vecchio Speech REST per il target 2027.
- **AzureSpeechAdapter:** SSML per voice, pitch, rate e stile quando supportato.
- **ElevenLabsSpeechAdapter:** voice/model ID con capabilities proprie; licensing e credits.
- **CustomHttpSpeechAdapter:** adapter opzionale con preset endpoint e schema dichiarato, **non eseguire** codice/plugin sconosciuto dentro l'app.

**Importante:** un modello che produce dialoghi conversazionali non è automaticamente un TTS fedele al libro. Valutare la corrispondenza verbatim; se non la garantisce, restringere la lunghezza, correggere prompting o usare il fornitore appropriato.

### 4.2 Config a livelli

Precedenza: \`appDefaults < userDefaults < bookSettings < characterVoiceProfile < perSegmentStyle\`; gli ultimi possono modificare **solo** campi consentiti. Preset e override persistiti come JSON versionato in DB.

Esempio illustrativo:

    tts:
      providerId: sherpa_onnx
      modelId: it-example-model
      voiceId: voice-0
      locale: it-IT
      rate: 1.0
      pitch: 0.0
    llm:
      providerId: local
      modelId: optional-model
      allowRemoteBookText: false
    cloud:
      requirePerBookConsent: true
      perBookBudgetEur: 3.00
      monthlyBudgetEur: 10.00

Valori \`modelId\` e \`voiceId\` sono **placeholder**, non modelli reali. La disponibilità e il costo sono recuperati al runtime o verificati nel catalogo.

### 4.3 Cache audio e invalidazione

Chiave \`SHA-256(sourceTextHash | normalizerVersion | providerId | apiVersion | modelId | voiceId | sortedParams | outputFormat | profileRevision)\`, eventualmente con separate \`anchorId\` per il mapping. **Non** includere credenziali. Cache per segmento con LRU, limiti totali e per libro, pulizia e export soltanto se consentito.

Quando cambia speaker, profilo o sintesi: invalidate **solo** i segmenti dipendenti; quando cambia normalizzazione/estrazione: invalidare o rimappare in modo esplicito. Se la lettura viene interrotta, cancellare la richiesta quando possibile e non avviare nuove operazioni fatturabili oltre il cap.

## 5. Contratti LLM e sicurezza dell'analisi

\`BookAnalysisProvider.analyze(chapterFragments, existingCast, constraints)\` restituisce **soltanto annotazioni JSON** rigorosamente validate, niente testo riscritto.

- Batch delimitati per token e confini di capitolo, con guardrail su citazioni e contenuto delle opere.
- Identificazione entità e alias, speaker spans e \`confidence\` con \`evidenceAnchors\`.
- Controlli contro hallucination: character non esistente, range oltre testo, parlante introdotto dopo scena, mismatch di citazione.
- LLM output considerato **non attendibile** (anche contro prompt injection presente nel libro); mai interpretare testo del libro come istruzioni operative dell'app, mai consentire filesystem/network/actions da prompt.
- Provider cloud opt-in per *analisi* separato dall'opt-in per *TTS cloud*, con stima testo/tokens.
- Re-analisi incrementale; analisi full-book eseguita solo su scelta consapevole. Manual override prevale sempre sul modello.

Vedi [specifica cast](VOICE_CASTING_SPEC.md) per struttura e invarianti.

## 6. Data model (bozza da affinare con migrations)

| Tabella | Chiavi e contenuti | Note |
|---|---|---|
| \`books\` | id, file_hash, path, format, title, author, language, import_at | duplicati/versioni |
| \`chapters\` | id, book_id, order_index, title, source_ref | TOC |
| \`text_blocks\` | id, chapter_id, source_anchor_json, text, hash, extraction_version | source of truth |
| \`text_segments\` | id, block_id, char_start, char_end, type, speaker_id, normalization_version | range contigui |
| \`reading_progress\` | book_id, source_anchor_json, audio_position_ms, updated_at | un record per libro |
| \`bookmarks\` / \`highlights\` | book_id, anchors, color/notes | indipendenti da TTS |
| \`tts_providers\` | id, kind, public_settings_json | no secrets |
| \`voice_profiles\` | id, book_id, character_id?, provider_id, voice_id, params_json, revision | narrator profile distinto |
| \`characters\` | id, book_id, display_name, attributes_json, status, provenance_json | canonical identity |
| \`character_aliases\` | character_id, alias, first_seen_anchor | lookup |
| \`speaker_assignments\` | segment_id, character_id?, confidence, origin, evidence, revision | unknown e override |
| \`analysis_runs\` | id, book_id, scope, model, state, estimated_cost, actual_cost, schema_version | cancellazione/ripresa |
| \`audio_cache\` | cache_key, segment_id, file_ref, duration, timestamps_json, bytes, last_used_at | LRU |
| \`cloud_usage\` | run_id, provider, units, currency, estimated, billed_if_available, created_at | budget |

Migrations versionate. Foreign keys attive, transazioni per import e riconciliazione personaggi. Non serializzare API keys negli export/backup.

## 7. Privacy, sicurezza e distribuzione

- Default **offline**; telemetria non necessaria e disattivata, richieste esterne per libro solo dopo conferma.
- Android storage picker/SAF, niente permessi di accesso indiscriminato senza necessità; protezione file/cache locali; Windows file association opzionale.
- OS secure storage per credenziali. In Android verificare backup/restore credenziali e device key rotation; in Windows usare la soluzione OS adeguata.
- Secret redaction nei log, HTTP TLS, retry sicuri, niente body completo di opere in crash log.
- Richieste esterne a budget, informazioni su cloud locale/regione, disconnettibilità e cancellazione cache.
- Pubblicazione Windows MSI/MSIX e Android APK/AAB; modelli ONNX grandi distribuiti on-demand.
- Licenza applicazione MIT del repository non implica licenza commerciale di tutti i pesi, voci, dipendenze e testi: predisporre inventario SBOM/NOTICE.

## 8. Test e CI

- Unit: parsers semantici (senza UI), split non distruttivo, threshold speaker, cache key deterministica, precedence config, cost ceiling.
- Contract: fake TTS/LLM, rate limit, timeout, result con/ senza word marks, fallback su unknown, parametri non supportati.
- Integration: import EPUB/PDF, SQLite migration, adapter system/ONNX su Windows e Android reali, cancellazione analisi, background player Android.
- Security/fuzz: archive bombs, XML/entity attacks, malformazioni EPUB/PDF/HTML, prompt injection nel libro, invalid JSON, codepoint offset.
- Performance: benchmark su hardware desktop medio e Android low/midrange, test con documenti 1–10–50 MB e libri lunghi.
- CI repository: workflow lint/unit/build test solo **manuale inizialmente** per non incorrere in run superflui; valutare CI schedulata/automatica dopo baseline. L'automazione di CI non sostituisce test su dispositivi fisici.

## 9. Gates decisionali M0

1. Render PDF+EPUB su Windows e Android con gli stessi \`SourceAnchor\`.
2. TTS locale con voce it-IT identificabile su entrambi; provare ONNX con misure RAM/latency.
3. Background playback Android e interoperabilità tra streaming/provider e player.
4. Tutte le dipendenze compatibili con licenza MIT e policy distribuzione.
5. POC OpenAI Realtime con lettura precisa e controllo sessione. Se non idoneo per audiolibri lunghi, privilegiare Azure/ElevenLabs e tenere adapter OpenAI opzionale finché non soddisfa la fidelity suite.
