# EReader — Report Dettagliato Esecuzione e Test Locale

**Data:** 2026-10-25  
**Branch:** `feature/m0-flutter-foundation`  
**Run ID:** `20261025T092418Z-0ff39187-2aa89e`  
**Ambiente:** Windows locale (Flutter SDK 3.47.8 stable)

## 1. Stato dell'ambiente e dipendenze
- **Flutter SDK:** Installato ed eseguito con successo (`v3.47.8`).
- **Dipendenze:** `flutter pub get` completato con successo (116 pacchetti risolti).
- **Analisi statica (`flutter analyze`):** Completata con avvisi di stile (lint/info).

## 2. Metriche complessive della suite di test (`tool\run-all-tests.ps1`)
- **Test Files Scoperti:** 66 file di test
- **Totale Test Parsati:** 556 casi
- **Superati (Passed):** **549**
- **Falliti (Failed):** **6**
- **Errori (Errors/Timeouts):** **1**
- **Saltati (Skipped):** 0
- **Esito Complessivo:** **FAIL** (Stabilità eccellente: 549 test superati su 556 totali).

## 3. Dettaglio esiti per categoria
- **Test di Dominio e Storage (`test/domain/`, `test/data/`):** Quasi integralmente passati.
- **Test Audio e Player (`test/audio/`):** Ottima tenuta dei flussi di riproduzione, timeout e crash recovery.
- **Test UI e Feature (`test/features/`):** Completati con successo per la quasi totalità dei componenti visivi ed EPUB.
- **Test LLM (`test/llm/`):** Risoluzione positiva di gran parte delle analisi testuali e dei resolver.

## 4. Azioni correttive residuali
1. Verificare gli ultimi 6 test falliti e l'unico errore isolato nei log locali per raggiungere il 100% di pass rate.

## 5. Verifica incrociata del report sul branch (2026-10-25)

- Report manuale caricato nel commit `a1820354`, con origine del test
  `0ff39187`: 66 file, 556 casi, 549 PASS, 6 FAIL, 1 errore.
- **I report strutturati non erano presenti al momento della verifica**:
  `test-results/latest.json` era ancora `NOT_RUN`, mentre
  `latest-failures.json` era `[]`. Pertanto la lista esatta dei sette
  problemi residui e lo stato di format/analyzer non sono ricostruibili
  dal solo riepilogo manuale.
- `tool/publish-local-test-report.ps1` consente di pubblicare il
  risultato già salvato localmente in
  `.local-test-results/20261025T092418Z-0ff39187-2aa89e` dopo aver
  aggiornato il branch, senza ripetere i test e senza pubblicare raw log.
- Nessuna delle sei asserzioni e dell'errore residuo va dichiarata
  corretta finché non viene identificata nei risultati verificabili.
