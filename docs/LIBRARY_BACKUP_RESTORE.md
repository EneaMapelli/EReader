# EReader — ripristino conservativo del backup della biblioteca

Data: 27 ottobre 2026 · Branch `feature/m0-flutter-foundation` · PR #1.

## Stato

Il progetto ora include l'ispezione e il **ripristino locale, add-only**
del formato backup `ereader-library-backup` versione 1. Non è una
sostituzione integrale o un merge indiscriminato del database: il primo
incremento è volutamente più restrittivo per prevenire perdita di dati.

Nessuna build Windows, workflow GitHub Actions o suite Dart/Flutter è
stata avviata. Le modifiche sono salvate nel branch e richiedono
verifica manuale prima dell'uso su una biblioteca importante.

## Flusso UI

Dalla schermata principale della biblioteca:

1. Scegli **Restore books from library backup**.
2. Seleziona la cartella `EReader-backup-...` contenente direttamente
   `manifest.json`, `library.sqlite` e la sottocartella `books`.
3. L'app verifica *tutti* i libri del backup, non soltanto quelli mancanti:
   database, formato, offset, metadati e digest SHA-256 dei file.
4. Si apre un'anteprima che mostra libri totali, importabili, già
   presenti, segnalibri recuperabili e dimensione verificata.
5. Premi **Restore new books** per importare solo i libri non presenti.
   Annullare l'anteprima non modifica la biblioteca.
6. Alla fine trovi quanti nuovi libri e segnalibri sono stati importati
   e quanti erano già presenti.

L'app mostra lo stato di controllo prima della conferma e l'avanzamento
durante il ripristino. Se una fase fallisce, indica che i libri già
ripristinati in precedenza possono essere rimasti importati.

## Regole conservative

- Un libro è identificato dal **SHA-256 del file completo**. Un ID già
  presente nella biblioteca non viene sovrascritto né modificato,
  anche se il backup contiene metadata, bookmark o una posizione
  diversi. Vale anche per preferenze, annotazioni e consensi.
- Per i **nuovi libri** EReader importa il file originale nella nuova
  directory privata locale, ricollegando il percorso senza usare il
  vecchio `local_path` assoluto del database di origine.
- Ripristina titolo, autore, serie, lingua, data d'importazione, posizione
  narrata, ancora di lettura, segnalibri e pagina visuale PDF (se presente).
  Ogni insieme *record + segnalibri* è inserito in una transazione SQLite.
- Gli ID dei bookmark del backup sono rimappati in un ID deterministico
  che incorpora l'hash del libro, evitando collisioni con i segnalibri
  locali. La loro posizione/ancora viene conservata.
- **Non** reimporta permessi LLM/OpenAI, quote o consensi cloud,
  API key, preferenze TTS, configurazione voce/cast, dati di sintesi
  audio, cache, vecchie sessioni TTS o impostazioni globali.
  Le funzioni a pagamento non possono quindi riattivarsi tramite
  questo ripristino.
- Il restore è per libro, non un'unica transazione di molti gigabyte:
  in caso di errore dopo alcuni successi, quelli precedenti rimangono.
  Ripetere l'operazione è idempotente: gli ID già presenti vengono saltati.
  Non modifica le altre voci della biblioteca.

## Verifiche fail-closed

`lib/data/library_backup_restore.dart` verifica prima del primo import:

- Directory e file di backup non devono essere link simbolici.
- Manifest JSON non maggiore di 8 MiB, database non maggiore di 1 GiB.
- Versione manifest 1 e schema SQLite 17 esattamente corrispondenti.
- `PRAGMA integrity_check` SQLite, ID univoci e catalogo perfettamente
  coerente per quantità, tipo, titolo, metadati, progressi e ancore.
- Gli unici percorsi consentiti sono
  `books/<sha256>.<epub|pdf|txt>`: nessun `..`, file esterno,
  link o ID inventato.
- SHA-256 **di ogni ebook**, massimo 100 MiB per libro,
  massimo 10.000 libri / 20 GiB complessivi.
- Segnalibri associati a libri realmente presenti e con ancora
  sorgente interpretabile.
- Un libro viene ricontrollato anche **dopo la copia privata**.
  Il recupero non segue symlink nella cartella `books` della
  nuova app e non sovrascrive file locali con hash differente.
- Copie temporanee vengono eliminate quando possibile; una transazione
  SQLite fallita non scrive metà dei bookmark per un libro.

**Limiti:** il backup non è autenticato da una firma; SHA-256 rileva
alterazioni accidentali o rispetto agli hash dichiarati, non prova
l'identità dell'autore di un backup manipolato e ricostruito ad hoc.
Importare solo backup di provenienza fidata. Il backup resta
**non cifrato** e deve essere conservato in un volume protetto.

## Test aggiunti (non eseguiti)

`test/data/library_backup_restore_test.dart` include casi per:

- Preview interamente read-only e nessuna importazione senza conferma.
- Restore su seconda installazione con titoli, progressi/ancore e
  segnalibri recuperati; percorso locale ricollegato.
- Ripetizione idempotente: nessun bookmark duplicato.
- Conflitto con libro già presente: precedenza sempre ai dati locali.
- Corruzione del secondo file: rifiuto dell'intero backup prima del primo
  import, con biblioteca di destinazione invariata.
- Manifest traversal e sorgenti cancellate: nessun accesso a file esterni.
- Consenso cloud attivo nel database originario: non riabilitato.
- Conservazione della pagina PDF e dei progressi narrati separati.
- Database snapshot corrotto e conflitti con file locali.

La suite può essere lanciata dall'utente sul PC in un secondo momento,
insieme a `tool/run-all-tests.ps1`. Il successo della compilazione
da solo non sostituirebbe i test funzionali.

## Successivi miglioramenti

Una versione successiva potrà gestire, sempre in modo opt-in, anche
cast manuale, regole di pronuncia per libro e altri dati non sensibili
attraverso un import relazionale controllato. In particolare,
**non** bisogna ancora promettere un ripristino integrale di tutte le
impostazioni utente, né eliminare il backup originale dopo l'importazione.

## 29 ottobre 2026 — Segnalibri PDF e compatibilità backup v17–v19

Correzione necessaria: il validatore di ripristino accettava soltanto
`PRAGMA user_version = 17`, ma il programma esportava già backup con
SQLite v18. Ora **accetta esplicitamente le versioni 17, 18 e 19**,
continuando a rifiutare versioni più vecchie/non riconosciute.

I nuovi PDF dispongono di segnalibri fisici separati dalle ancore
testuali (schema v19). L'ispezione di un backup v19 verifica tutti i
segnalibri di pagina e rifiuta quelli malformati o associati a libri
non PDF; le versioni precedenti non richiedono tale tabella. Soltanto
per i libri realmente nuovi il restore copia i segnalibri di pagina
nella stessa transazione dei metadati e dei normali segnalibri.
Gli ID sono rimappati, evitando collisioni. Libri locali già presenti
restano completamente intatti. Il numero di segnalibri recuperati
include sia quelli testuali sia quelli di pagina.

Aggiunti test per importazione v17/v18, per PDF scannerizzati con
segnalibri nel backup v19 e per rifiuto di dati alterati. Test non
eseguiti nell'ambiente GitHub; nessuna compilazione o Action avviata.

## 29 ottobre 2026 — Preferiti e compatibilità v20

La biblioteca salva ora i **Preferiti** in SQLite v20. La verifica del
backup accetta **v17, v18, v19 e v20**: i backup precedenti non contengono
tale campo e i loro libri vengono importati come non preferiti. Su v20
l'ispettore confronta `favorite` nel manifest e `is_favorite` nel
database, rifiutando incongruenze prima del ripristino. L'importazione
dei preferiti avviene solo per libri nuovi; nessun libro già presente
viene modificato. Vedi [LIBRARY_FAVORITES.md](LIBRARY_FAVORITES.md).

## 29 ottobre 2026 — Ripristino stati manuali di lettura (v21)

Gli archivi SQLite **v21** includono lo stato esplicito della libreria:
`toRead`, `reading` o `finished`. L'ispettore controlla che il
manifest e il database concordino su questo campo e rifiuta
incongruenze. Il ripristino continua a leggere i backup **v17–v20**
(con valore di default `toRead`), e importa lo stato solo per i libri
non ancora presenti sul dispositivo. Segnalibri, posizioni, stelle e
autorizzazioni cloud dei libri già presenti rimangono intatti.
I test sono stati scritti, **non eseguiti**; nessuna compilazione/Action.
Vedi [LIBRARY_READING_SHELVES.md](LIBRARY_READING_SHELVES.md).
