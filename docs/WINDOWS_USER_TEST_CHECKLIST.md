# Checklist manuale — EReader Windows (prima beta portatile)

Questa checklist serve a PROVARE l'eseguibile compilato. Non viene
avviata come test automatico e non effettua telemetria. Compila solo
i risultati che vuoi condividere; **non allegare libri, token, database
o contenuti protetti da diritto d'autore**.

## Informazioni ambiente

- SHA della build (`BUILD_INFO.txt`):
- Windows 10/11, versione, x64:
- Versione app (se mostrata):
- Primo avvio o installazione già esistente:
- Cartella estrazione ZIP (nome generico, non indirizzo personale):
- Eventuale antivirus/blocco SmartScreen (senza disattivarlo automaticamente):

## Avvio e libreria

- [ ] Estrazione dello ZIP completo senza file mancanti
- [ ] Apertura `ereader.exe` e visualizzazione biblioteca
- [ ] Importazione di TXT UTF-8
- [ ] Importazione EPUB testuale
- [ ] Importazione PDF con testo selezionabile
- [ ] Riapertura dell'ultimo libro
- [ ] Rimozione libro senza blocchi/cancellazioni inattese
- [ ] Gestione percorso locale mancante o file importato corrotto

## EPUB visuale

- [ ] Indice capitoli e selezione di un capitolo
- [ ] Font grande/piccolo, scroll lungo, tema
- [ ] Grassetto/corsivo/titoli XHTML
- [ ] PNG/JPEG locali fra testo e didascalie
- [ ] Figure `figcaption` distinguibili
- [ ] Tabelle: anteprima espandibile nello stesso punto del testo
- [ ] Note e link interni, ritorno dalla nota
- [ ] Capitolo illustrato senza testo e segnalibro dedicato
- [ ] Chiusura e riapertura su capitolo illustrato

## PDF/TXT

- [ ] Zoom, cambio pagina PDF e memorizzazione della pagina
- [ ] PDF text-to-speech solo da contenuto selezionabile
- [ ] Pagina PDF senza testo: messaggio comprensibile
- [ ] Ricerca nel libro
- [ ] Segnalibri, posizione esatta alla riapertura

## Voce e sicurezza

- [ ] Selezione della voce di sistema Windows gratuita
- [ ] Play/Pausa/Stop e cambio di segmento
- [ ] Cambio velocità e pitch
- [ ] Stop durante lettura e ripresa del punto corretto
- [ ] Scorrimento visuale senza sintesi inattesa
- [ ] Fine libro: non rilegge da sola l'ultima frase
- [ ] Chiudere l'app mentre sta parlando, poi riaprirla
- [ ] Nessuna richiesta OpenAI o spesa cloud senza consenso esplicito
- [ ] Modalità offline senza chiavi/API, per prima sessione consigliata

## Problemi da annotare

Per ogni problema indicare:

| Campo | Da compilare |
|---|---|
| ID | WIN-001 |
| Build SHA | Da BUILD_INFO.txt |
| Priorità | Bloccante / Alta / Media / Bassa |
| Funzionalità | Es. EPUB / PDF / audio / biblioteca |
| Passi per riprodurre | 1. ... 2. ... 3. ... |
| Atteso | Cosa sarebbe dovuto succedere |
| Osservato | Che cosa è successo |
| Riproducibile | Sempre / Saltuario / Una volta |
| Tipo di libro | EPUB / PDF / TXT, nessun contenuto privato |

Per bug di avvio segnala il titolo/errore della DLL mancante o
l'avviso principale visualizzato, senza percorsi personali o log
contenenti chiavi. Se la build remota fallisce prima di produrre ZIP,
si deve leggere il job GitHub Actions, non considerare fallita
automaticamente la funzione del lettore.
