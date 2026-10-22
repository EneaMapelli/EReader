# EReader

**EReader** è un progetto di lettore di ebook per **Windows e Android**, con riproduzione **text-to-speech (TTS)** offline/gratuita e tramite provider cloud configurabili. L'obiettivo a lungo termine è una modalità opzionale di **audiolibro multi-personaggio**: analisi del romanzo tramite LLM, riconoscimento dei dialoghi, creazione di un cast di voci coerente e correzione manuale delle attribuzioni.

> **Stato del progetto (2026-10-22): pianificazione iniziale.** Non sono ancora presenti applicazioni eseguibili o funzionalità implementate.

## Obiettivi

- Lettura di **EPUB, PDF con testo estraibile e TXT** nella prima versione; estensione futura ad altri formati.
- Biblioteca locale, segnalibri, progressi, temi, ricerca, navigazione e sincronizzazione testo/audio.
- Voci del sistema Windows/Android, motori neurali offline opzionali e API cloud a consumo (BYOK).
- Configurazione indipendente di provider e modelli **TTS** e **LLM**, voci, pitch, velocità e stile *secondo le capacità effettive del provider*.
- **Cast assistito** con identificazione dei personaggi, speaker dei dialoghi e attribuzione revisionabile; fallback al narratore se il parlante è incerto.
- Privacy local-first, consenso prima dell'invio dei testi alle API, budget massimo e cache audio per segmento.
- Un'unica base Flutter per Windows e Android.

## Documentazione

1. [Piano di sviluppo completo](docs/DEVELOPMENT_PLAN.md) — visione, requisiti, supporto formati, milestones M0–M6, 16 attività iniziali, criteri di accettazione e rischi.
2. [Architettura tecnica](docs/TECHNICAL_ARCHITECTURE.md) — stack, contratti documenti/TTS/LLM, storage, pipeline audio, caching e sicurezza.
3. [Specifiche del casting vocale intelligente](docs/VOICE_CASTING_SPEC.md) — personaggi/alias, screening LLM, attribuzione battute, voce narrante, confidenza, schema e revisione umana.

## Roadmap sintetica

| Fase | Risultato |
|---|---|
| M0 | POC Windows/Android per EPUB, PDF, TTS gratuito e rendering |
| M1 | Lettore e biblioteca EPUB/PDF/TXT |
| M2 | Player TTS locale, sincronizzazione testo/audio, audio in background |
| M3 | TTS neurale offline, provider cloud, voci e budget |
| M4 | Cast vocale manuale multi-personaggio |
| M5 | Analisi LLM e riconoscimento/casting automatico revisionabile |
| M6 | Ottimizzazione, test, packaging e prima release |

**Nota provider:** per l'integrazione OpenAI, il piano prende in considerazione la dismissione dei modelli Speech legacy annunciata per il 6 gennaio 2027; è prevista la verifica della Realtime API come tecnologia futura, con alternative cloud.

## Licenza

Codice del progetto: [MIT](LICENSE). Modelli vocali e librerie di terze parti possono avere licenze autonome: verificarle prima di distribuirli.
