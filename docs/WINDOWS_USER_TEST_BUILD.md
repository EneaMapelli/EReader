# EReader — Windows portable build per test utente

Data: 26 ottobre 2026. Branch da provare: `feature/m0-flutter-foundation`.
La versione prodotta da questa procedura è **Release unsigned per test manuali**,
non un installer firmato, né una release pubblica collaudata.

## Download preferito: GitHub Releases (prerelease privata)

Le nuove build Windows riuscite vengono anche pubblicate come
**prerelease** privata, con un asset ZIP installazione-zero:
[Releases di EReader](https://github.com/EneaMapelli/EReader/releases).

Quando è presente la versione `windows-test-<sha>`, aprila e scarica
da **Assets** il file `EReader-Windows-x64-<sha>.zip`. Estrai il
contenuto una sola volta e avvia `ereader.exe`. Questa Release non
modifica il branch `main` né crea un installer MSI: è pensata per
test manuali. Se l'ultima compilazione fallisce, nessuna nuova
prerelease viene pubblicata; usa invece l'ultima versione riuscita
oppure consulta il log del workflow. La compilazione può anche
pubblicare l'artefatto Actions con scadenza di 14 giorni.

## Percorso semplice: scarica lo ZIP creato da GitHub Actions

1. Apri [EReader Windows portable user build](https://github.com/EneaMapelli/EReader/actions/workflows/windows-user-build.yml).
2. Apri l'ultima esecuzione **riuscita** relativa al branch
   `feature/m0-flutter-foundation`.
3. Nella parte **Artifacts** scarica `EReader-Windows-x64-portable`.
   GitHub richiede accesso al repository privato. L'artefatto scade
   dopo 14 giorni; lo ZIP incluso ha nome
   `EReader-Windows-x64-<commit>.zip`.
4. Il download di GitHub Actions è uno ZIP contenitore: estrailo.
   Al suo interno troverai `EReader-Windows-x64-<commit>.zip`.
   Estrai **anche questo secondo ZIP** completamente in una cartella
   scrivibile, ad esempio
   `C:\Users\<utente>\Downloads\EReader-Test\`.
5. Avvia `ereader.exe` oppure `Start-EReader.cmd`. Non spostare
   soltanto l'EXE: `data/`, `flutter_windows.dll`, eventuali DLL
   di plugin e altri file devono rimanere assieme.
6. Controlla `BUILD_INFO.txt` prima di segnalare un problema, per
   identificare il commit effettivamente compilato.

È stato aggiunto un workflow di **sola compilazione Windows**,
indipendente dai test/analyzer del precedente `manual-verify.yml`.
Si avvia su modifiche allo script di packaging/al workflow stesso
oppure manualmente tramite Actions, quando GitHub rende disponibile il
controllo `Run workflow`. Non vengono usate API key o libri privati.
Il job non va confuso con un test di funzionamento dell'app.

## Se preferisci compilare tu sul PC Windows

Prerequisiti: Windows 10/11 x64 compatibile con la versione Flutter,
Flutter SDK (versione CI di riferimento **3.47.7**), Visual Studio 2022
con **Desktop development with C++** e Windows SDK installato.
Per la preparazione di symlink di plugin potrebbe servire Developer Mode.

Apri PowerShell nella cartella del repository:

```powershell
git switch feature/m0-flutter-foundation
git pull --ff-only origin feature/m0-flutter-foundation
flutter doctor -v
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build-windows.ps1
```

Lo script genera automaticamente `windows/` se necessario, esegue
`flutter pub get` e `flutter build windows --release`, controlla
che l'EXE e gli asset esistano e crea una copia della directory Release
completa. Non esegue `flutter test`, `dart format`, `flutter analyze`,
non fa commit né push e non legge i libri in `example/`.

I risultati sono esclusivamente locali e ignorati da Git:

- Eseguibile di compilazione: `build/windows/x64/runner/Release/ereader.exe`
- Directory pronta per l'avvio:
  `.local-windows-build/staging/EReader-Windows-x64-<commit>/`
- ZIP da spostare su altri PC:
  `.local-windows-build/releases/EReader-Windows-x64-<commit>.zip`

L'EXE avviato su un secondo PC può richiedere il Microsoft Visual C++
Redistributable. Nessuna firma Authenticode o MSI/MSIX è inclusa.
Non aggirare avvisi di sicurezza se non sei certo di provenienza,
commit e integrità dei file.

## Primo test utente

Usa la [checklist dei test Windows](WINDOWS_USER_TEST_CHECKLIST.md):
apertura app, import EPUB/TXT/PDF, rendering di figure, note, tabelle,
salvataggio dei segnalibri, voce Windows gratuita, Pause/Play/Seek,
fine libro, chiusura e riapertura, crash recovery. Nella prima sessione
è preferibile **non** inserire API key o avviare servizi TTS a pagamento.

Il PDF scansionato senza testo selezionabile non ha ancora OCR. EPUB
interamente illustrati senza testo, XHTML/CSS complesso, DRM e alcune
funzioni audio native restano limitazioni di prodotto, non necessariamente
bug di packaging.

## Come segnalare un problema senza divulgare dati

Invia solo: commit da `BUILD_INFO.txt`, versione Windows, formato
del libro (non il libro stesso), percorso funzionale, risultato atteso
e comportamento osservato. Se il problema avviene all'avvio, segnala
eventuali nomi di DLL mancanti o testo dell'errore, **rimuovendo**
percorsi personali, nomi file riservati e token.

I file EPUB/PDF dell'utente, le API key, la libreria SQLite, la cache MP3
e i log integrali sono **dati privati** e non vanno caricati su GitHub
Actions o allegati a issue. `example/` resta ignorata da Git.

## Stato verifiche

**Prima Release x64 riuscita e verificata:**

- [GitHub Actions run #40382035244](https://github.com/EneaMapelli/EReader/actions/runs/40382035244):
  compilazione Flutter Windows Release **success**, upload artefatto **success**.
- Pacchetto: `EReader-Windows-x64-c1f783ca.zip`;
  commit sorgente `c1f783cabef22b2aa1be9fbe197208e8b0ebb966`.
  Artefatto GitHub: `EReader-Windows-x64-portable`, 14 giorni di retention
  (fino al 9 novembre 2026).
- Ispezione archivio: ZIP integro; `ereader.exe`,
  `flutter_windows.dll`, `data/flutter_assets/`,
  `sqlite3.dll`, `pdfium.dll`, `just_audio_windows_plugin.dll`,
  `onnxruntime.dll` e le altre librerie richieste sono presenti.
- La prima compilazione fallì per un problema di parsing PowerShell;
  la seconda individuò il metodo `PdfViewerController.dispose()` non
  disponibile in `pdfrx 2.4.8`. La terza individuò incompatibilità
  di `just_audio_windows` con MSVC 14.51. Corretto il Dart e fissato
  Windows Server 2022/Visual Studio 2022, la quarta è stata completata.
- Non sono stati eseguiti test automatici, avvio grafico su macchina
  utente, lettura TTS nativa o test di installazione. Il successo
  del compilatore non dimostra che tutte le funzionalità siano prive di bug.
