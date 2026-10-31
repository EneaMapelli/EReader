# EReader — Local Test Report

* Result: **FAIL** (18 test case falliti, 35 errori di compilazione/timeout in isolamento, 1 saltato)
* Source: fadcf16 (feature/m0-flutter-foundation)
* Run: 20261031T202302Z-ec6f0643-fec7b0

## Summary
- flutter pub get: PASS
- flutter analyze: PASS (nessun errore bloccante, solo info/warnings di stile)
- flutter version / dart version: PASS
- flutter test (suite combinata): TIMEOUT dopo 301s → fallback su test individuali
- flutter test (160 file individuali): 1321 passati, 18 falliti, 35 errori, 1 saltato

## Per-Test Results
160 test file eseguiti individualmente. Per ogni test sono salvati:
- `individual-NNNN.cmd` — comando esatto eseguito
- `individual-NNNN.exit-code` — codice di uscita (0 = successo, 1 = errore, 124 = timeout)
- `individual-NNNN.stdout.log` — output JSON di Flutter test
- `individual-NNNN.stderr.log` — stderr di Flutter test

Tutti i log sono in `test-results/runs/20261031T202302Z-ec6f0643-fec7b0/` (645 file).

## Sintesi per categoria
- **test/audio/**: 30 file, mix di pass/falliti (alcuni con PathAccessException su temp file Windows)
- **test/config/**: 6 file, alcuni falliti (file_picker.platform, desktop_drop API)
- **test/data/**: 40 file, mix di pass/falliti
- **test/domain/**: 31 file, quasi tutti passati
- **test/features/**: 39 file, mix di pass/falliti (alcuni con timeout o widget binding)
- **test/llm/**: 8 file, tutti passati

## Script fix
`tool/run-all-tests.ps1` modificato:
- Aggiunto `-SkipCombinedRun` per saltare il `flutter test` combinato che si blocca su Windows (file-lock su `offline_voice_manager_widget_test.dart`)
- Default `$TestTimeoutMinutes` da 20 a 5 (per-test)
- Ogni test gira in processo isolato con timeout proprio: un test bloccato non ferma l'intera suite

## Perché i log erano mancanti prima
Eseguire `flutter test` direttamente stampa a terminale ma non salva file di log. I log dettagliati vengono generati solo con `--reporter json` + redirect su file, oppure tramite `tool/run-all-tests.ps1` che salva stdout/stderr per ogni test file.
