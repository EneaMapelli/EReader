# M1 — Import Android da «Condividi»

Data: 28 ottobre 2026. Branch: `feature/m0-flutter-foundation`.

Una app Android può inviare un singolo documento EPUB/PDF/TXT con
`ACTION_SEND` oppure più documenti con `ACTION_SEND_MULTIPLE`.
EReader espone un'Activity locale che **estende AudioServiceActivity**
e non sostituisce il supporto Android MediaSession già implementato.

## Pipeline e protezioni

- Lo share native riceve `content://` URI, mantenuti **solo in memoria**
  e non esposti a Dart, SQLite, notifiche, log o servizi cloud.
- I file arrivano a Flutter attraverso handle casuali e richieste di
  massimo 64 KiB per blocco, senza caricare tutto l'ebook in memoria.
- Si riusa `importPickedBooks`, sequenziale, con validazione, checksum,
  deduplica, transazione SQLite, staging temporaneo e **100 MiB per libro**.
  Massimo 50 documenti alla volta. La cancellazione non lascia file privati.
- Gli handle vengono rilasciati anche in caso di errore o import parziale.
  Nessun permesso ampio `READ_EXTERNAL_STORAGE` è richiesto.
- L'importazione non apre il reader, non avvia TTS e non modifica i consensi.
  Anche i singoli libri ricevuti restano nella biblioteca per apertura manuale.
- La lettura dal provider può fallire se revoca i permessi. La perdita del
  processo Android richiede un nuovo share; non esiste persistenza dei grant.
  Un provider senza filename può usare un nome generico dal MIME dichiarato.

## Configurazione Android

`tool/android/AndroidManifest.xml` dichiara i filtri per SEND e
SEND_MULTIPLE. `tool/android/MainActivity.kt` estende l'Activity del
media-service e gestisce il canale `com.example.ereader/share_import`.
`tool/bootstrap.sh`, `tool/bootstrap.ps1` e il workflow **solo manuale**
copiano entrambi nella directory generata da Flutter:
`android/app/src/main/kotlin/com/example/ereader/ereader/MainActivity.kt`.

## Limiti e test

Codice scritto e pubblicato, **non compilato né eseguito su Android**.
Restano da verificare compilazione Kotlin, manifest merger, condivisione
da Files/Drive/altro provider, import batch, file malformati, revoca URI,
share a caldo, lettura con screen lock e media buttons. Non si garantisce
sopravvivenza a process death né compatibilità con qualunque provider.
Test nuovi: `android_shared_book_inbox_test.dart`,
`android_shared_book_widget_test.dart` e
`android_share_receiver_contract_test.dart`. Non eseguire nuove Actions
o compilazioni Windows senza richiesta.
