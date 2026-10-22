# EReader

**EReader** è un'app Flutter local-first per leggere ebook e ascoltarli con voci sintetiche, inizialmente su **Windows e Android**. Obiettivi a lungo termine: TTS offline/cloud intercambiabile e audiolibri multi-personaggio con analisi LLM e cast vocale controllabile dall'utente.

## Stato del codice

**Prototipo iniziale M0 in sviluppo**, non una release.

Sul branch `feature/m0-flutter-foundation` sono presenti:
- Modello libri e importazione/copia locale di TXT, EPUB e PDF (limite provvisorio 100 MB).
- Biblioteca SQLite 3.x con progressi persistenti e migrazione automatica del precedente indice JSON.
- Estrazione e lettura in forma testuale di TXT/EPUB; **il renderer EPUB completo e gli anchor stabili non sono ancora implementati**.
- Visualizzazione PDF tramite `pdfrx` e modalità sperimentale di lettura vocale per PDF con testo selezionabile (senza garanzia sull'ordine di colonne, note e tabelle).
- Lettura vocale con voci del sistema Windows/Android, selezione voce, lingua, pitch, rate, salta avanti/indietro e evidenziazione del *segmento* in lettura.
- Test unitari per modelli, segmentazione, queue player, database SQLite, migrazione JSON e decodifica TXT.
- Workflow GitHub Actions **solo manuale** per analisi, test e build, da lanciare dopo la prima verifica locale.

**Non ancora verificati:** compilazione, test/analisi effettivi, migrazione SQLite reale e funzionamento su dispositivi Windows/Android. Gli ambienti Flutter/Dart e i toolchain Windows/Android non erano disponibili nel contesto di sviluppo. Le cartelle native `android/` e `windows/` devono ancora essere generate e versionate dopo il bootstrap.

## Avvio su Windows

Prerequisiti: Flutter SDK (Dart >= 3.11), Android SDK per Android, Visual Studio con carico di lavoro **Desktop development with C++** per Windows, Developer Mode per `pdfrx`.

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

Priorità: M0 fondazione tecnica, M1 lettore completo, M2 TTS/read-along, M3 provider avanzati e cloud, M4 cast manuale, M5 LLM multi-personaggio, M6 release.

## Privacy e licenza

Tutto il prototipo usa dati locali; non ci sono richieste TTS/LLM cloud né API keys. I libri vengono copiati in una directory privata dell'app. EPUB DRM non supportati. Licenza del progetto [MIT](LICENSE); i modelli vocali e i pacchetti di terze parti mantengono licenze autonome.
