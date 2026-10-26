# Windows system TTS — punctuation treated as pauses

26 ottobre 2026 · Branch `feature/m0-flutter-foundation`

## Problema

Alcune voci di sistema su Windows pronunciano il nome dei segni di
punteggiatura (ad es. "virgola", "punto", "virgolette") invece di
usarli per modulare la lettura. Per una prima esperienza utente questo
rende la narrazione innaturale.

## Nuovo comportamento

- Il motore **SystemSpeechEngine**, solo per le voci native **Windows**,
  usa `WindowsSpeechPunctuation.plan` prima di chiamare `flutter_tts`.
- I segni di frase normalmente pronunciati a voce (virgola, punto,
  punto e virgola, due punti, esclamativo, interrogativo, puntini
  di sospensione e trattini di inciso) delimitano brevi frasi
  pronunciate senza inviare al sintetizzatore il nome del simbolo.
- Le pause sono semantiche, non parole aggiunte: **140 ms** dopo
  virgole, **260 ms** dopo punto e virgola/due punti/incisi e interruzioni
  di riga, **360 ms** dopo punti e puntini, **420 ms** dopo domande
  ed esclamazioni. Una pausa finale non viene aggiunta artificialmente
  quando il segmento è terminato.
- Virgolette, parentesi e simboli di elenco decorativi vengono
  ignorati o convertiti in separazione fra parole.
- Sono **mantenuti**: apostrofi in parola (`l'amico`, `dell’uomo`),
  trattini in parole composte (`porta-a-porta`), segni negativi
  e separatori di cifre (`3,14`, `1.000`, `12:30`),
  simboli con significato (`%`, `€`, `+`) e Unicode.
- La lettura per frammenti avviene all'interno della **stessa clip
  logica** di ReaderPlayer: nessun nuovo offset, segmento, segnalibro
  o identificativo di voce. Le regole del dizionario di pronuncia
  continuano a funzionare prima dell'interpretazione della punteggiatura.
- Stop/Pausa/cambio voce/navigazione invalidano subito le restanti
  frasi della clip e interrompono anche la pausa temporizzata: non
  possono causare la riproduzione di una frase ormai superata.

## Compatibilità e limiti

- I motori TTS Android, OpenAI e Sherpa non sono stati modificati:
  usano già i propri parser di punteggiatura e prosodia.
- Separare le frasi evita la pronuncia letterale della punteggiatura,
  ma **non garantisce** da solo una perfetta intonazione crescente
  nelle domande, perché l'informazione del punto interrogativo non è
  una parola consegnata alla voce. La qualità dipende anche dalla
  specifica voce Windows. Questo resta un tema per i test utente.
- All'interno di paragrafi tecnici (formule, URL, codici) la
  segmentazione è volutamente conservativa per le sequenze numeriche.
  Se serve leggere letteralmente simboli matematici è opportuno
  un futuro profilo separato per formule/codice.
- La trasformazione non interessa né i file EPUB/PDF/TXT né l'indice
  di ricerca o il database. Il cloud non riceve testo diverso e non
  aumenta le richieste a pagamento.

## Verifiche

Aggiunto `test/audio/windows_speech_punctuation_test.dart` con casi
su dialoghi italiani, pause, numeri e orari, apostrofi Unicode,
sintassi narrativa, testo senza punteggiatura ed input soli simboli.

I test sono **scritti ma non eseguiti automaticamente**. È stata
richiesta una nuova **Windows x64 Release** da GitHub Actions tramite
il workflow `windows-user-build.yml`, che compila senza l'intera
suite Flutter; un'eventuale disponibilità ZIP vale solo dopo un
`success` della relativa esecuzione.

## Collaudo utente suggerito

1. Scarica l'ultima esecuzione riuscita del workflow
   [Windows portable build](https://github.com/EneaMapelli/EReader/actions/workflows/windows-user-build.yml).
2. Apri un breve romanzo italiano usando una **voce di sistema Windows**
   (non OpenAI) e prova, per esempio:
   `«Ciao, Marco!» disse Anna. «Tutto bene?»`.
3. Non dovresti sentire le parole "virgola", "virgolette", "punto
   esclamativo"; dovresti percepire una separazione fra le clausole.
4. Verifica `3,14`, `1.000`, `12:30`, `l'amico`,
   `dell’uomo` e `porta-a-porta` per prevenire regressioni.
5. Premendo Pausa nel mezzo di una frase, poi Play, controlla che
   non si sovrappongano due voci e che l'offset sorgente sia
   ancora quello originale. Testa anche il cambio voce.
6. Segnala modello/nome della voce, versione Windows, commit della
   build e un breve esempio di punteggiatura letto male (non allegare
   il libro né API key).

**Nessuna validazione audio dal dispositivo è stata ancora eseguita.**
