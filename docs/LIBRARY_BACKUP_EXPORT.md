# EReader — esportazione privata della biblioteca (M6 incrementale)

**Data:** 27 ottobre 2026 · Branch: `feature/m0-flutter-foundation`, PR #1.

## Richiesta sul consumo GitHub Actions

Il proprietario del repository ha chiesto di non compilare più automaticamente
l'app Windows. Il workflow `.github/workflows/windows-user-build.yml`
è stato modificato in **solo `workflow_dispatch`**. Non contiene più
`push` né altri eventi automatici. Anche `manual-verify.yml` resta
manuale. Nessun test, runner o build è stato avviato in questo incremento.
L'aggiunta dei commit non deve richiedere minuti Actions.

## Funzione introdotta

Dalla biblioteca di EReader, premi **Export private library backup**,
leggi e conferma l'avvertenza privacy e scegli una directory esistente.

L'esportazione crea una nuova sottocartella
`EReader-backup-<identificativo casuale>` con:

- `library.sqlite`: snapshot SQLite consistente tramite `VACUUM INTO`,
  indipendente dai file WAL in uso nell'app. Conserva anche progressi, ancore
  di lettura, segnalibri, metadati manuali, preferenze, cast e annotazioni,
  oltre ai consensi archiviati nel DB.
- `books/<sha256>.<epub|pdf|txt>`: copia esatta di tutti i libri privati
  gestiti dall'app, verificati ricomputando l'hash SHA-256 completo.
- `manifest.json`: versione del formato, conteggi, data, nomi relativi dei
  libri, metadati della biblioteca e progresso. Non include percorsi assoluti
  nel manifest.

Nella UI compaiono un contatore di avanzamento e una conferma finale con
numero di libri, dimensione copiata e percorso selezionabile del backup.

## Integrità e comportamento in caso di errore

- Nessun libro può puntare fuori da `appHome/books/` o essere un symlink.
- L'identità del libro è il suo digest SHA-256, verificato anche dopo la
  copia. Mancanti, file corrotti, duplicati e limiti di dimensione errati
  bloccano il completamento.
- Il database esportato viene riaperto e controllato con
  `PRAGMA integrity_check`; gli ID del DB devono corrispondere esattamente
  a quelli dei libri da esportare.
- I file sono creati in una directory temporanea privata del luogo di
  destinazione. La cartella finale viene **pubblicata solo al termine**
  con un rename: un errore non produce un backup apparentemente valido.
- Nessun backup esistente viene sovrascritto.
- Fino a 10.000 libri / 20 GiB totali; il limite originale dei singoli
  ebook resta 100 MiB. Il backup è locale, senza upload automatici.
- Gli errori SQLite/I/O restano privati e non vengono mostrati in chiaro
  come stack trace o percorsi.

## Sicurezza e limiti

**ATTENZIONE:** questo backup **non è cifrato**. Include libri, cronologia,
cast e possibili annotazioni private. Usare un supporto affidabile e
possibilmente una cartella/volume cifrato. Non condividere
`library.sqlite` né il manifest pubblicamente.

I segreti native vault/DPAPI/Android Keystore, i file temporanei TTS,
i modelli vocali, le cache derivabili e le chiavi API gestite dallo
storage sicuro OS non vengono copiati.

**Ora è disponibile un primo ripristino manuale e conservativo**:
dopo la verifica completa e l'anteprima, importa soltanto i libri assenti,
con i relativi metadati, posizioni e segnalibri. Ricostruisce i nuovi
percorsi locali senza usare quelli del database di origine. Non importa
cloud/LLM consent, voce, cast o chiavi API; i libri già presenti non
vengono modificati. Non è un restore integrale del database e non va
mai copiato manualmente sopra quello live.
[Guida al restore](LIBRARY_BACKUP_RESTORE.md).

## Test scritti (NON eseguiti)

`test/data/library_backup_test.dart` verifica:

1. Copia esatta dei libri e manifest con dati/offset persistenti.
2. Snapshot SQLite standalone con integrità e metadati salvati.
3. Esclusione di file segreti collocati nell'area privata dell'app.
4. Rifiuto di ebook manomessi e di file non più disponibili.
5. Blocco delle destinazioni dentro la cartella attiva dell'app.
6. Eliminazione dello staging dopo un database non valido.
7. Limiti di capacità e assenza di overwrite di un precedente backup.

Da verificare a mano su Windows/Android, quando richiesto:
selezione cartella, spazio su disco, file bloccati da antivirus,
backup di biblioteca vuota e molto grande, integrità file dopo copia
su disco esterno e tempi di esecuzione. Non è stata eseguita alcuna
compilazione Windows e **non esiste una nuova Release** per questa modifica.

## Prossimi sviluppi suggeriti

Il primo restore con anteprima e ricollegamento percorsi dei libri
assenti è implementato. Rimangono: import selettivo del cast,
gestione esplicita dei conflitti per i libri già presenti,
maggiori schemi legacy e opzione di archivio cifrato. Sono attività da sviluppare, non funzioni già disponibili.

## 2026-10-29 — Physical PDF page bookmarks in standalone snapshots

Current exports use SQLite schema **v19**. The WAL-free SQLite
snapshot includes a dedicated `pdf_visual_bookmarks` table, so a
book's separately named page markers are not silently lost on transfer.
The portable restore supports older v17/v18 backups in addition to
v19, validates each physical bookmark before import, and restores
only missing books. Existing book data, speech consent, passwords and
TTS configuration are never replaced. This remains a local,
unencrypted backup: keep it in a private location.
