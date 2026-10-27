# M1 Windows/Android — importazione multipla della biblioteca

Data: 27 ottobre 2026. Branch: `feature/m0-flutter-foundation`, PR #1.

## Funzione aggiunta

Nella biblioteca, usa **Import** o l'icona di caricamento e seleziona uno
o più EPUB, PDF o TXT nel file picker nativo. Il plugin `file_picker`
versione 13 supporta direttamente `pickFiles()`, che restituisce la lista
di file. Se si seleziona **un solo libro**, EReader mantiene il vecchio
comportamento e apre il libro importato. Con **più libri**, non apre
automaticamente la lettura e mostra un resoconto:

- Libri aggiunti
- Libri già nella biblioteca, riconosciuti dallo SHA-256 del contenuto
- Importazioni fallite o non disponibili
- File rimasti da elaborare dopo un'interruzione volontaria

Durante l'importazione compare una barra di avanzamento con contatore e
**Cancel remaining**. L'annullamento viene applicato solo **tra un
file e il successivo**: non uccide una transazione SQLite a metà né
cancella un import già completato.

## Correttezza e privacy

- Importazione **sequenziale**, mai decine di PDF da 100 MB in RAM
  simultaneamente. Ogni elemento utilizza la convalida, la deduplica,
  l'archiviazione privata e le transazioni SQLite già presenti in
  `LibraryStore.importFile`.
- Compatibilità con Android SAF e file cloud: selezioni senza un percorso
  filesystem possono essere lette dallo stream e temporaneamente
  inserite in una directory privata limitata a **100 MB per libro**.
  Le directory di staging vengono sempre eliminate.
- Non viene rieseguito il TTS durante l'importazione e non vengono
  effettuate chiamate a OpenAI o servizi cloud per l'analisi dei libri.
  Come in precedenza il picker stesso può accedere ai provider di
  file cloud già configurati sul dispositivo su esplicita richiesta.
- Un file invalido o non leggibile non interrompe i file successivi.
  Nessuna eccezione grezza, percorso assoluto o contenuto del libro
  viene salvato o mostrato nel messaggio di errore.
- I titoli mostrati nel riepilogo sono ricavati solo dai nomi visuali
  dei file selezionati, con rimozione di separatori/percorso e
  caratteri di controllo; il riepilogo mostra al massimo dieci
  errori individuali.
- Un libro già presente non perde segnalibri, metadati manuali,
  posizione di lettura o consensi. I duplicati all'interno della
  stessa selezione sono riconosciuti senza duplicare la libreria.
- Per evitare una selezione eccessiva sono ammessi fino a **50 libri
  per batch**. Il limite per libro resta quello originale di 100 MB.

## Test scritti, non eseguiti automaticamente

`test/data/batch_book_import_test.dart` contiene casi su:

- importazioni seriali da stream senza percorso, in ordine;
- un EPUB errato in mezzo a libri validi e successivo import regolare;
- deduplica preesistente e nella stessa selezione;
- condivisione Android SAF non disponibile;
- annullamento fra file e preservazione delle copie completate;
- rifiuto di oltre 50 selezioni prima della lettura;
- errori imprevisti senza propagare percorsi privati;
- selezione vuota.

I test rimangono manualmente lanciabili tramite
`tool/run-all-tests.ps1`. La build Windows Release separata verifica
la compilazione, non equivale all'esecuzione di queste asserzioni.

## Checklist Windows

1. Scarica la nuova build compilata dal
   [workflow Windows](https://github.com/EneaMapelli/EReader/actions/workflows/windows-user-build.yml),
   oppure dalla corrispondente GitHub prerelease se pubblicata.
2. In **Import**, seleziona insieme 3 EPUB, 2 PDF e 1 TXT: atteso
   un riepilogo con sei libri aggiunti e nessun avvio del TTS.
3. Riprova gli stessi libri: attesi sei duplicati senza resettare
   progressi e metadata; apri uno di essi per confermare il bookmark.
4. Seleziona anche un file corrotto e un PDF valido: l'ultimo deve
   comunque importarsi. I nomi personali/percorsi non devono comparire
   in stack trace a schermo.
5. Seleziona molti file e premi **Cancel remaining** mentre lavora:
   la barra non deve bloccarsi, e i libri già importati devono
   comparire correttamente.
6. Su Android importa un file offerto da un Document Provider/SAF,
   poi verifica che possa riaprirsi senza mantenere il provider aperto.
7. Apri un libro nuovo e verifica che ricerca, metadati, copertina,
   progressi, EPUB/PDF visuale e voci TTS funzionino come prima.

## Limiti aperti

Drag & drop diretto da Esplora risorse Windows, import ricorsivo di una
cartella, OPDS/Calibre, collezioni e ricerca full-text della biblioteca
restano sviluppi successivi. Il test della build e lo smoke test Windows
sono distinti: una compilazione riuscita non garantisce che tutti i
file reali siano importabili.

## Primo pacchetto Windows compilato

- [Build Windows Release riuscita — GitHub Actions #40465285992](https://github.com/EneaMapelli/EReader/actions/runs/40465285992)
- [Prerilascio scaricabile windows-test-45a013cf](https://github.com/EneaMapelli/EReader/releases/tag/windows-test-45a013cf):
  asset `EReader-Windows-x64-45a013cf.zip`.
- La compilazione e pubblicazione del pacchetto sono riuscite.
  **Non** sono stati eseguiti i test Dart automatici né le prove
  manuali su libri reali e Android. Nessuna stabilità runtime è promessa.

## Estensione: trascinamento da Esplora file Windows (2026-10-27)

L'importazione multipla è ora accessibile anche tramite **drag & drop**
nella biblioteca Windows. Un nuovo `DropTarget` riceve file EPUB,
PDF o TXT da Esplora file e li passa alla pipeline `importPickedBooks`
già presente, preservando duplicati, progressi, protezioni 100 MB
e cancellazione dei file in coda. Anche file virtuali vengono letti
con lo stream valido solo durante la callback del plugin. Una
schermata mostra il riepilogo dei file non supportati; nessuna
cartella o URL viene importato. Android resta sul picker originale.

L'aggiornamento non è stato compilato né testato su Windows in questa
sessione. La Release precedente non lo include. Test solo scritti.
[Dettagli, sicurezza e test manuali](LIBRARY_DESKTOP_DRAG_DROP.md).
