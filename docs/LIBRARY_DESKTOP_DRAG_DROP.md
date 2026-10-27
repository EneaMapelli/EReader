# M1 — Trascinamento libri nella biblioteca Windows

Data: 27 ottobre 2026 · Branch `feature/m0-flutter-foundation`, PR #1.

## Funzione implementata

Su Windows la schermata principale di EReader ora accetta i file trascinati
direttamente da Esplora file. Quando un file entra sulla finestra, la
biblioteca mostra un overlay ad alto contrasto **Drop EPUB, PDF or TXT books
here**. Il rilascio importa i libri senza aprire automaticamente la lettura.

- Accetta fino a **50 file** per trascinamento.
- Filtra esplicitamente **EPUB, PDF e TXT**, indipendentemente dal
  maiuscolo/minuscolo nell'estensione.
- Mostra un riepilogo con libri aggiunti, duplicati già in biblioteca,
  errori e fino a cinque file ignorati perché in formato non supportato.
- Usa lo stesso `importPickedBooks` del picker: importazione seriale,
  verifica delle firme tramite `LibraryStore.importFile`, limite di
  100 MB per libro, hash SHA-256 per deduplica, dati SQLite e posizioni
  esistenti sempre preservati.
- Durante l'importazione mostra contatore, avanzamento e
  **Cancel remaining** (l'annullamento vale tra un libro e il successivo).
- Il drag & drop è disabilitato mentre è attiva un'altra operazione di
  biblioteca: non ci sono importazioni concorrenti o passaggi TTS.
- Un trascinamento contenente soltanto elementi non validi mostra un
  messaggio non tecnico; non scarica URL o file remoti.

## Come funziona

Dipendenza esplicita `desktop_drop: 0.9.2`, fissata alla versione con
correzione per Windows e API `onDrop / onEnter / onLeave` introdotte
nella serie 0.9. Richiede Flutter **3.47.7**, già la versione usata
nei workflow manuali di EReader.

Documentazione del plugin:
https://pub.dev/packages/desktop_drop

`DropTarget` è montato **solo su Windows**; Android continua a usare
il picker SAF senza modifiche. Il target accetta il tipo file e filtra
ulteriormente gli elementi `DropFileItem`. URL, testo trascinato e
cartelle non vengono né aperti né esplorati ricorsivamente.

Il nome del file viene ridotto al basename e ripulito dai caratteri
di controllo prima di usarlo nel riepilogo/importer. Nessun percorso
Windows proveniente dal drop viene considerato attendibile:
il contenuto viene letto da `XFile.openRead()` durante la callback
async `onDrop`, mantenendo valido anche l'accesso ai file virtuali
che Windows potrebbe esporre temporaneamente.

**Importante:** il plugin rilascia le risorse dell'origine al termine
della callback `onDrop`. Tutta l'importazione è attesa prima di
ritornare; il popup di riepilogo viene aperto soltanto in un frame
successivo, per non trattenere file/provider durante l'interazione UI.

## Test scritti, non eseguiti

`test/data/desktop_book_drop_test.dart` copre i seguenti casi:

- selezione multipla e formati ammessi, in ordine;
- nomi senza percorsi assoluti, estensioni maiuscole e controlli input;
- esclusione di `.exe`, `.zip`, URL e altri elementi non supportati;
- zero letture di file durante il filtro preliminare;
- rifiuto totale dei drop con oltre 50 file, prima di aprire uno stream;
- trascinamento vuoto e non supportato;
- passaggio al batch importer esistente usando stream privati di staging.

Da provare manualmente su Windows, **solo quando il proprietario chiederà
una nuova compilazione**:

1. Apri EReader con biblioteca vuota; trascina insieme 3 EPUB, un PDF e
   un TXT da Esplora file. Verifica overlay e importazione.
2. Trascina gli stessi file una seconda volta. Devono essere segnalati
   come duplicati senza alterare bookmark, progressi e metadati.
3. Trascina un EPUB valido e un `.jpg` o `.exe`: il secondo deve
   essere ignorato e dichiarato nel riepilogo.
4. Trascina un'intera cartella, un URL o testo: nessuna scansione
   ricorsiva o download.
5. Trascina 51 file: tutto il batch è rifiutato prima della lettura.
6. Prova file da OneDrive/Esplora file e da una cartella di rete: il
   contenuto deve essere copiato in storage privato mentre l'accesso
   provider è disponibile.
7. Durante un batch, usa **Cancel remaining**; controlla che i libri
   già importati rimangano. Verifica che un secondo drop non avvii
   una seconda importazione simultanea.
8. Riapri un libro importato e controlla lettura, TTS, indice e
   segnalibri. Nessuna richiesta cloud deve partire durante il drop.

## Limiti

La funzione non importa cartelle intere, non estrae archivi ZIP,
non importa PDF con DRM, non elimina o sposta i file originali,
non legge URL remoti e non bypassa i limiti dei 100 MB per ebook.
Eventuali comportamenti di file virtuali e antivirus richiedono
verifica su Windows reale.

**Stato build:** nessuna nuova Release creata e nessuna GitHub Action
avviata. Entrambi i workflow di compilazione/test restano
`workflow_dispatch` manuale, come richiesto.
