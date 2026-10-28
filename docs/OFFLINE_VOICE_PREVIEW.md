# M3 — Anteprima ascoltabile delle voci neurali offline

**Data:** 28 ottobre 2026. **Branch:** `feature/m0-flutter-foundation`.

## Nuova funzionalità

Nel pannello **Speech engines → Manage offline neural voices** un pacchetto
VITS/Piper già installato, verificato e corredato di risorse eSpeak può
essere ascoltato con il comando **Preview voice** (Windows alpha).
L'utente deve confermare **Play sample**, quindi può premere **Stop sample**
senza modificare la voce scelta per alcun libro.

La prova usa esclusivamente una breve frase pubblica incorporata in EReader,
in italiano o inglese secondo la lingua del modello. Non sintetizza brani
dei libri, non modifica segnalibri, posizione di lettura, voci dei personaggi,
consensi cloud, credenziali o cache OpenAI. Non effettua chiamate HTTP.
Nessun download del modello è implicito nella prova.

## Verifiche e lifecycle

- Prima di costruire l'engine, `loadInstalledOfflineVoicePack` rilegge e
  ricontrolla manifest, file, path e SHA-256 del modello e dei dati eSpeak.
  Il checksum **non** certifica l'identità dell'editore o i diritti d'uso.
- Un modello non pronto, senza eSpeak o senza un testo dimostrativo per
  la lingua dichiarata **non** mostra l'azione Preview.
- Al massimo un sample alla volta; Stop invalida immediatamente le richieste
  pendenti, anche durante la verifica dei file. Nessuna sintesi tardiva
  può iniziare dopo l'annullamento.
- Stop e Dispose sono eseguiti sul motore dedicato; prima di un nuovo sample
  si attende la fine del precedente Stop. Non sono promessi Stop/Dispose
  istantanei in presenza di blocchi FFI; un errore rimane visibile.
- Le eccezioni native e filesystem non sono stampate a video: possono
  includere percorsi locali. La schermata offre solo un messaggio generico.
- L'utente deve **fermare la narrazione del libro** prima della prova:
  la gestione esclusiva dell'audio fra due screen è ancora da validare.

## Limiti e prove

Il codice e i test sono stati scritti, ma **non è stata eseguita** alcuna
compilazione o riproduzione audio Windows/Android in questa sessione.
L'anteprima non rende Android VITS disponibile e non certifica la qualità
del modello Paola né un avvio audio privo di interruzioni.

Test:
- `test/audio/offline_voice_audition_test.dart`: campione locale fisso,
  modelli incompleti, lingua errata, blocco preview simultanee,
  annullamento durante hashing, Stop durante audio, Dispose.
- `test/features/offline_voice_audition_widget_test.dart`: UI, conferma,
  pulsante Stop, pacchetti senza eSpeak; motore finto senza FFI/audio.
  
Verificare manualmente con modello realmente installato su Windows:
Play/Stop ripetuti, finestra chiusa durante hashing e WAV, modello corrotto,
pacchetti italiani/inglesi, CPU/RAM e integrità dei WAV temporanei. Non
lanciare GitHub Actions o nuove build senza richiesta dell'utente.
