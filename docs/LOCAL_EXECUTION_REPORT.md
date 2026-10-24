# EReader — Report Dettagliato Esecuzione e Test Locale

**Data:** 2026-10-24  
**Branch:** `feature/m0-flutter-foundation`  
**Ambiente:** Windows locale (Flutter SDK 3.47.8 stabilito in ambiente temporaneo)

## 1. Stato dell'ambiente e dipendenze
- **Flutter SDK:** Installato ed eseguito con successo (`v3.47.8` stable).
- **Dipendenze:** `flutter pub get` completato (116 pacchetti risolti, generato `pubspec.lock`).

## 2. Metriche complessive della suite di test (`flutter test`)
- **Totale test superati (Passed):** ~417 test unitari, di dominio, storage e widget.
- **Totale test falliti / errori di caricamento (Failed / Errors):** ~38 test (inclusi errori di compilazione e timeout).

## 3. Dettaglio esiti per categoria e file di test

### A. Test di Dominio e Modelli (`test/domain/`)
- **Stato:** Principalmente PASSATI.
- **Eccezioni rilevate:**
  - `cross_chunk_cast_test.dart`: Fallimenti su asserzioni di continuità voce su chunk multipli (`Expected: contains 'narrator replied.'`, `Actual: 'replied.'`).

### B. Test di Storage e Migrazioni SQLite (`test/data/`)
- **Stato:** Numerosi test passati con successo (gestione ancore, resume, cataloghi).
- **Eccezioni rilevate (`library_store_test.dart`):**
  - Errori di migrazione iterativa per colonne duplicate (`SqliteException(1): duplicate column name: last_opened_at` / `evidence_json`), causati dall'esecuzione sequenziale delle migrazioni su database di test preesistenti o riutilizzati senza reset dello schema.

### C. Test di UI e Widget (`test/features/`)
- **Stato:** Molti test UI passati.
- **Eccezioni rilevate:**
  - `epub_chapter_navigation_test.dart`: Errore di compilazione per costruttore/metodo non trovato per `SpeechSegment` o tipo di lista non assegnabile.
  - `epub_paragraph_tile_test.dart`: Fallimenti di text matching nei widget test di preview delle note a piè di pagina (es. `Expected: '[1] and open it'` vs `Actual: '[1], footnote link and open it'`).

### D. Test Audio, Player e Prefetch (`test/audio/`)
- **Stato:** La maggior parte dei test di player e recupero crash passata.
- **Eccezioni rilevate:**
  - `cloud_prefetch_test.dart` e `mp3_preload_test.dart`: Alcuni test di prefetch e sincronizzazione audio interrotti o non completati entro i timeout di 30 secondi.

### E. Test LLM e Analisi Riferimenti (`test/llm/`)
- **Stato:** Molti test passati.
- **Eccezioni rilevate:**
  - Errore di compilazione bloccante in `lib/llm/dialogue_analysis_plan.dart:183:15` (`The method 'reverse' isn't defined for the type 'List<SpeechSegment>'` - necessita di `List.from(earlier).reversed` o `earlier.reversed.toList()`).
  - Errore di sintassi in `lib/llm/openai_dialogue_analyzer.dart:289:67` (`Expected ')' before this`).
  - `narrative_antecedent_finder_test.dart`: Disallineamento di stringhe nel recupero antecedenti (`Expected: 'Captain Mira'` vs `Actual: 'Mira'`).

## 4. Azioni correttive prioritarie
1. **Compilazione LLM:** Risolvere il metodo `.reverse()` non valido su `List<SpeechSegment>` in `dialogue_analysis_plan.dart` e correggere la sintassi in `openai_dialogue_analyzer.dart`.
2. **Migrazioni SQLite:** Assicurare il reset pulito del database di test prima di ogni test di migrazione sequenziale in `library_store_test.dart`.
3. **Asserzioni Test UI/Dominio:** Aggiornare le stringhe attese nei test di preview note e cast cross-chunk.

## 4. Triage dei risultati locali e correzioni successive

**Revisione del report:** 24 ottobre 2026. I risultati sopra provengono dal PC Windows; le modifiche sotto sono stati eseguite nel repository GitHub **dopo** quel test. Non implicano che la suite ora passi.

| Area segnalata | Correzione preparata | Verifica ancora necessaria |
| --- | --- | --- |
| Errore Dart `List<SpeechSegment>.reverse()` | Ricostruzione del contesto con `earlier.reversed` e lista immutabile, preservando l'ordine originale delle evidenze. Test con più frasi di contesto. | Rilanciare `flutter analyze` e `flutter test test/llm/dialogue_analysis_plan_test.dart` |
| SQLite: `duplicate column name` in migrazioni ripetute | Le migrazioni `ADD COLUMN` controllano `PRAGMA table_info` prima dell'aggiunta, senza eliminare dati o tabelle. Test con schema già dotato delle colonne e `user_version` retrocesso a v1/v8. | `flutter test test/data/library_store_test.dart` con SQLite nativo Windows |
| Widget EPUB: testo non corrispondente | Le asserzioni confrontano `InlineSpan.toPlainText(includeSemanticsLabels: false)`, distinguendo il testo realmente visibile dalle etichette vocali accessibili `footnote link`. | `flutter test test/features/epub_paragraph_tile_test.dart` |

**Limitazioni del report ricevuto:** non sono stati allegati il log console completo, i nomi dei singoli test falliti, il numero di test passati/falliti, l'output di `flutter analyze` o uno snapshot preciso dei test eseguiti. Questo documento **non conferma** il superamento della suite: le correzioni sono fondate sui problemi descritti, ma l'esito potrà essere accertato soltanto con una nuova esecuzione sul PC Windows.

**Per il prossimo report locale:** includere il comando esatto, il commit SHA testato, gli exit code, il riepilogo per suite e almeno gli stack trace dei fallimenti. Non includere token, credenziali cloud, percorsi utente assoluti o testo di libri privati.
