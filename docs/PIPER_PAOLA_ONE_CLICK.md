# Installazione guidata di Piper Paola (Windows)

Data: 27 ottobre 2026. Branch: `feature/m0-flutter-foundation`, PR #1.

## Che cosa è stato implementato

Dal lettore apri **Speech engines → Manage offline neural voices → Install Paola — Italian neural voice (free)**.

1. EReader mostra una conferma esplicita con dimensioni, provenienza, licenze e avvertenze.
2. Dopo consenso scarica soltanto un archivio convertito ufficialmente per sherpa-onnx: **vits-piper-it_IT-paola-medium.tar.bz2**, dalla release `tts-models` di `k2-fsa/sherpa-onnx`.
3. Il download HTTP(S) è trasmesso direttamente su disco in un'area privata, con limite di **85 MiB compressi**, timeout e indicatore di avanzamento. Non vengono caricati libri, API key o dati personali.
4. PRIMA di invocare l'estrazione con il `tar.exe` di Windows controlla il **SHA-256 esatto** fornito dai metadati GitHub dell'asset:

   `7541f75778afa164e44e34baaef63befad7698595df26a95ca944b63ef1a16b4`

5. Il pacchetto preconvertito contiene `it_IT-paola-medium.onnx`, `tokens.txt` e `espeak-ng-data`; non richiede Python, ambienti virtuali o eseguire un convertitore sul PC dell'utente.
6. EReader rifiuta percorsi sospetti/link, dimensioni fuori budget, risorse mancanti o checksum non corrispondenti. Genera i checksum dei singoli file del modello e li installa nella cartella privata con l'importatore atomico già esistente; un fallimento elimina l'area temporanea.
7. L'installazione **non attiva** automaticamente la voce: torna in **Speech engines**, seleziona **Free local VITS / Piper — experimental**, scegli Paola e conferma la prova.
8. Dopo l'installazione e durante la lettura, il modello lavora offline e non produce costi API.

## Autori, licenze e affidabilità

- Fonte del modello convertito: [sherpa-onnx, catalogo Paola italiano](https://k2-fsa.github.io/sherpa/onnx/tts/all/Italian/vits-piper-it_IT-paola-medium.html).
- Modello originario: [rhasspy/piper-voices, Paola medium](https://huggingface.co/rhasspy/piper-voices/tree/main/it/it_IT/paola/medium), repository dichiarato MIT.
- Il [dataset della voce](https://huggingface.co/datasets/paolapersico1/Voice-Dataset-Italian) dichiara CC0-1.0.
- I file del phonemizer eSpeak hanno proprie informazioni di provenienza e licenza. La verifica SHA-256 dimostra l'identità dell'archivio atteso, non la sicurezza assoluta del modello o la titolarità dei diritti.
- EReader **non** aggiunge il modello (circa 67 MB) al proprio ZIP Windows; il download è opzionale. Non scarica alcun eseguibile arbitrario: la generazione audio continua a utilizzare `sherpa_onnx` già incluso nell'app.

## Limiti

- **Solo Windows** per il download guidato. Android non è ancora supportato da questo flusso.
- Occorre Windows con `tar.exe`, connessione Internet al momento dell'installazione e spazio libero aggiuntivo per download, estrazione e copia privata. Dopo è tutto offline.
- La voce neurale è una **versione sperimentale**, non ancora convalidata dal vivo: interruzioni Stop/Pausa, tempistiche, consumo CPU/RAM e pronuncia devono essere verificati sul PC.
- Non sono previsti download silenziosi, fallback al cloud, invio automatico di testo o selezione forzata al posto della voce di sistema.

## Verifiche preparate, non eseguite

- `test/data/piper_paola_installer_test.dart`: archivio fissato a URL e digest, percorsi eSpeak, rifiuto archivi corrotti/sovradimensionati.
- Installazione reale **da verificare manualmente** sul PC: conferma, download, integrità, estrazione, installazione, selezione di Paola, Play/Stop/Seek, riapertura e disinstallazione.
- Primo ascolto suggerito: un paragrafo italiano con dialoghi, numeri, virgole e domande, confrontandolo con le voci native Windows.
- Non considerare superato il test TTS soltanto perché la compilazione Windows è riuscita.

## Download della build

La procedura di compilazione `windows-user-build.yml` genera uno ZIP con EXE e runtime completo su GitHub Actions, indipendentemente dai test automatici. Quando i permessi di questo repository privato impediscono la creazione di una GitHub prerelease, l'artefatto Actions rimane la fonte attendibile dello ZIP (retention 14 giorni).

[Apri le build Windows](https://github.com/EneaMapelli/EReader/actions/workflows/windows-user-build.yml).

## Prima build Windows verificata dal compilatore

- GitHub Actions: [run 40462287757](https://github.com/EneaMapelli/EReader/actions/runs/40462287757) — compilazione Windows Release, caricamento ZIP e pubblicazione della prerelease **riusciti**.
- [Scarica la prerelease Windows `windows-test-960cfb5d`](https://github.com/EneaMapelli/EReader/releases/tag/windows-test-960cfb5d), file `EReader-Windows-x64-960cfb5d.zip` nella sezione **Assets**.
- La versione di codice compilata contiene già il pulsante **Install Paola** e il percorso di download/verifica SHA-256.
- Il successo del compilatore non dimostra ancora che il **download da GUI**, l'estrazione del modello, l'avvio della voce e il sistema audio siano corretti su PC reale. Questi passaggi restano nel checklist manuale.
