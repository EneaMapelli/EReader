# EReader — motori TTS gratuiti e selezione per libro

Data: 26 ottobre 2026
Branch: `feature/m0-flutter-foundation` (PR #1)

## Risposta alla domanda: il TTS attuale è il migliore?

No. EReader usa `flutter_tts` per sfruttare le voci disponibili nel
sistema operativo Windows/Android. È una base gratuita, locale e
leggera, ma non è una classifica di qualità rispetto a modelli
neurali moderni. Una voce installata su Windows può risultare meno
naturale di un modello offline; la qualità concreta e la latenza
dipendono da voce, macchina, lingua e punteggiatura.

## Alternative già selezionabili in EReader

| Scelta nell'app | Windows | Android | Costi | Stato |
| --- | --- | --- | --- | --- |
| Sistema — pause interpretate | Sì | Sì | Nessun costo per carattere | Operativo, comportamento nativo da validare su dispositivo |
| Sistema — punteggiatura nativa | Sì | Non esposto | Nessun costo per carattere | Operativo, stessa voce OS ma input diretto non suddiviso |
| Offline VITS / Piper | Sì | Non esposto | Nessun costo per carattere; solo hardware/dati locali | **Sperimentale esplicito**, solo con pack VITS già installato |
| OpenAI Audio Speech | Sì | Sì | A pagamento, API key e consenso per libro | Opzionale, separato dalle scelte gratis |

Nelle due modalità *Sistema* l'utente può scegliere singolarmente
le voci realmente installate, nell'elenco **Voice** del lettore.
La modalità "punteggiatura nativa" NON è un modello neurale aggiuntivo:
è un confronto A/B del trattamento dei segni per le stesse voci Windows.

La modalità VITS usa il provider `sherpa-vits` già presente nel
codice. La selezione è possibile soltanto se un pacchetto locale è
presente nella directory privata dell'applicazione, verificato SHA-256
per tutti i file, contiene `model.onnx`, `tokens.txt` e
`espeak-ng-data`, e l'utente conferma i rischi sperimentali.

**Importante:** per il motore VITS occorre un modello ONNX già
compatibile con `sherpa-onnx`. Un file `.onnx` Piper scaricato
direttamente potrebbe richiedere la conversione per esporre i metadati
corretti e generare `tokens.txt`; non basta rinominarlo. L'installazione
di file sul dispositivo verifica coerenza e integrità, non autentica
il publisher o la licenza. Nessun download è automatico; nessun
test native Windows/Android di questo provider è già stato superato.

Quando l'utente sceglie il pack locale, il modello viene caricato
solo dopo conferma esplicita; alla riapertura viene ricalcolato
SHA-256 prima di passare dati alla libreria ONNX. La lingua viene
allineata a quella del pack e il pitch riportato a 1.0 perché VITS
non supporta lo spostamento di pitch dopo la sintesi.

## Modelli gratuiti da valutare successivamente

- **Piper**: TTS leggero, offline, voci italiane come Paola e
  Riccardo. Un modello *convertito* alla famiglia VITS sherpa può
  essere provato mediante l'opzione locale sperimentale. Il progetto
  mantenuto OHF-Voice usa licenza GPLv3; i diritti sui checkpoint
  dei singoli speaker vanno verificati individualmente.
  [Catalogo lingue](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/VOICES.md),
  [conversione Piper → sherpa](https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/tts/piper.rst).
- **Kokoro 82M**: pesi Apache-2.0, offre voci italiane Sara e
  Nicola. Un percorso ONNX locale sarà preferibile a installare
  Python/PyTorch in EReader; servono verifica degli asset/modelli
  specifici, pronuncia, decodifica/cancel e benchmark Windows/Android.
  **Non selezionabile ancora**.
  [Modello](https://huggingface.co/hexgrad/Kokoro-82M),
  [voci](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).
- **Chatterbox Multilingual**: versione open-source MIT con italiano,
  maggiore dimensione/modellazione rispetto ai TTS locali leggeri e
  potenzialmente più adatta a dialoghi espressivi; un runtime pratico
  Windows/Android e consenso per eventuali voice cloning sono da
  implementare. **Non selezionabile ancora**.
  [Sorgente e lingue](https://github.com/resemble-ai/chatterbox).
- **Coqui XTTS-v2**: supporta italiano, ma i pesi usano CPML
  **non commerciale**: non redistribuire automaticamente in una app
  pubblica senza un'attenta revisione legale.
  [Licenza](https://huggingface.co/coqui/XTTS-v2/blob/main/LICENSE.txt).
- **Microsoft Edge online neural TTS**: varie librerie non ufficiali
  accedono a un servizio di rete. Non lo classifichiamo come
  **gratuito/offline affidabile e autorizzato per integrazione terza**;
  non viene attivato di nascosto né richiede l'invio del libro a
  endpoint non approvati.

## Come scegliere dall'app

1. Nel lettore, apri **Speech engines** (impostazioni voce).
2. Seleziona una delle modalità gratuite Sistema. Torna al libro
   e scegli nel menu **Voice** una delle voci realmente installate.
3. Su Windows, per confrontare punteggiatura native vs interpretata,
   salva `system-native` e riapri la lettura dello stesso estratto.
4. Per un modello VITS già scaricato e convertito:
   **Manage offline neural voices → Import local voice folder**;
   controlla provenienza/licenza e checksum prima dell'installazione.
   Riapri **Speech engines**, attendi la verifica dei pacchetti,
   scegli `Free local VITS / Piper — experimental` e la voce locale,
   e conferma esplicitamente il trial.
5. Se l'audio locale fallisce, ritorna a `system`: non è previsto
   alcun fallback automatico al cloud e non sono inviati estratti
   del libro.

## Criteri oggettivi per individuare la voce migliore

Manualmente, usando lo stesso brano italiano di 500–1000 caratteri:
comprensibilità, naturalezza delle pause, dialoghi, pronuncia di
apostrofi e nomi, voci uomo/donna, qualità in cuffia, tempo prima del
primo suono, real-time factor su CPU, memoria, Stop/Pausa/Seek,
ripresa da segnalibro. Nessuna voce è migliore in assoluto senza
ascolti e misure su hardware reale.

## Test di sicurezza da eseguire sul PC

- `test/audio/free_tts_selection_test.dart`: scelta della variante
  gratuita, ID modello, serializzazione preferenze e rifiuto di pack
  assente/incompatibile. Test scritti, **non eseguiti**.
- Reinstallare/riavviare con pack ONNX corrotto o locale errata deve
  produrre errore esplicito, non un crash nascosto o fallback cloud.
- Ripetere 20 volte Play/Pause/Stop/Seek in un lungo EPUB, mentre un
  motore neurale genera un WAV, e monitorare CPU/RAM/handle temporanei.
- Confrontare punteggiatura con le due modalità Windows e controllare
  sia lingua `it-IT` sia voci effettivamente installate.
- Verificare il nuovo ZIP di GitHub Actions prima di considerare
  disponibile questa versione per l'utente.

**Stato:** la scelta dei provider è stata integrata al codice, ma
l'audio VITS resta in fase **alpha, opt-in, non collaudato su dispositivo**.
Non si rivendicano benchmark o vantaggi non misurati.

## Anteprima audio VITS locale su Windows (28 ottobre 2026)

La voce neurale già **installata, pronta e dotata di dati eSpeak** mostra
`Preview voice` nella schermata dei modelli. Dopo conferma, EReader legge
solo un breve esempio dimostrativo incluso nell'app, in italiano o inglese;
non importa testo da EPUB/PDF né consuma crediti cloud. `Stop sample`
invalida anche la verifica del pack eventualmente ancora in corso.
L'anteprima è isolata dalle preferenze del libro e non attribuisce alcuna
nuova voce ai personaggi.

In questa sessione non sono stati eseguiti test Flutter, native build o
prove d'ascolto. `sherpa-vits` rimane **alpha Windows non collaudata**.
Vedi [OFFLINE_VOICE_PREVIEW.md](OFFLINE_VOICE_PREVIEW.md).
