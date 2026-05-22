# Changelog

Tutte le modifiche significative a questo progetto saranno documentate in questo file.

## [2.6.0] - 2026-05-22

### Modificato
- **Bonifica Semantica e Linguaggio Inclusivo**: Effettuata una revisione sistematica del linguaggio in tutta l'applicazione (UI frontends, API backend, generatori PDF, messaggi di log/errore, commenti e descrizioni) per sostituire la terminologia clinico-medica obsoleta con un vocabolario educativo e di monitoraggio multidimensionale inclusivo.
  - Sostituito `"Paziente/i"` con `"Utente/i"` nei testi, etichette e descrizioni della UI e dei PDF.
  - Sostituito `"Dati clinici"` / `"Note cliniche"` con `"Informazioni"` / `"Note generali"`.
  - Sostituito `"Quadro clinico"` / `"Classificazione clinica"` con `"Quadro dell'utente"` / `"Fascia di Supporto"`.
  - Sostituito `"Terapeutico"` / `"Terapia"` con `"di Supporto"` / `"Percorso"` / `"Intervento"`.
  - Sostituita la dicitura `"Report clinico"` con `"Report multidimensionale"`.
- **System Prompt Gemini AI**: Riprogettato il prompt di sistema di Gemini Service per agire come esperto e consulente di supporto per i percorsi sull'Autismo, istruendo l'IA a suggerire linee guida di supporto ed educative piuttosto che terapie cliniche, e a usare un linguaggio inclusivo e centrato sulla persona.
- **Web App Manifests**: Aggiornata la descrizione SEO in `index.html` e `manifest.json` modificando la dicitura da "valutazione clinica" a "valutazione multidimensionale".
- **Uniformità e Tracciabilità**: Allineata la versione del frontend (`kFrontendVersion`) e l'esportazione dei metadata del backend alla release `2.6.0`.

## [2.5.1] - 2026-05-22

### Risolto
- **Normalizzazione Scala San Martín**: Corretto il calcolo del valore massimo teorico per i domini della Scala San Martín nella modalità "Compara". Dato che le risposte della San Martín si basano su una scala Likert da 1 a 4 (mentre POS si basa su 1 a 3), il denominatore della percentuale è stato corretto a `numero domande × 4` (anziché `× 3`). Questo evita che le barre arancioni "sfondino" il limite del 100% (arrivando al 125%+).
- **Leggibilità del Grafico di Comparazione**: Sostituite le sigle dei domini (es. "SP", "RI") con i loro nomi completi (es. "Sviluppo Personale", "Relazioni Interpersonali") sull'asse X del grafico comparativo. Le etichette lunghe sono state ruotate a -0.4 radianti per prevenire sovrapposizioni e migliorare il design visivo.
- **Footer e Tooltip**: Aggiornato il testo esplicativo nel footer del grafico di comparazione e i dettagli del tooltip per riflettere accuratamente il calcolo del massimo teorico per entrambe le scale.
- **Pannelli di Dettaglio individuali**: Estesa la parametrizzazione del calcolo del massimo teorico anche ai grafici a barre dei singoli domini nel caso la scala San Martín debba essere visualizzata tramite barre in assenza di analisi psicometrica.

## [2.5.0] - 2026-05-22

### Aggiunto
- **Modalità Comparazione ("Compara")**: Introdotto un interruttore (Toggle) "Compara" nella scheda Overview dell'analisi utente. Quando abilitato, collassa le due schede POS e San Martín in un unico grafico comparativo unificato.
- **Logica di Normalizzazione (0-100%)**: Implementata la normalizzazione automatica dei punteggi assoluti di ciascun dominio in valori percentuali rispetto al punteggio massimo teorico (numero di domande × 3) per consentire un confronto omogeneo tra le scale.
- **Intersezione dei Domini**: Il grafico comparativo mostra esclusivamente i domini comuni (es. SP, BE, BF, BM, IS, RI) presenti in entrambe le scale.
- **Grafico a barre raggruppate (Grouped Bar Chart)**: Realizzato un grafico a barre raggruppate utilizzando `fl_chart`, con barre affiancate per ciascun dominio comune (Blu per POS, Arancione per San Martín), legenda e tooltip interattivo che mostra sia il valore assoluto originale che la percentuale normalizzata: `"$ValoreAssoluto / $PunteggioMassimo ($Percentuale%)"`.
- **Transizioni animate**: Integrato un `AnimatedSwitcher` combinato con `FadeTransition` e `SlideTransition` per garantire un'animazione fluida e premium nel passaggio dalla visualizzazione standard a quella comparativa.

## [2.4.1] - 2026-05-22

### Risolto
- **PDF - Rimozione Orari di Apertura**: Rimosso l'orario di servizio della Fondazione ("Orari: lun-ven dalle 9.00 alle 17.00") dalla sezione in alto a destra di tutte le intestazioni dei PDF generati.
- **PDF - Aggiornamento Logo Ufficiale**: Sostituito il vecchio logo ad alto contrasto/scuro nell'angolo in alto a sinistra di tutti i PDF generati con il nuovo logo ufficiale su sfondo bianco fornito dall'utente.

## [2.4.0] - 2026-05-22

### Risolto
- **Rilevamento Scala San Martín (Accenti/Etichette)**: Risolto definitivamente il bug in cui la colonna San Martín continuava a mostrare "POS" e a nascondere il grafo radar. La causa era il carattere accentato "í" (i acuta) nel nome "Scala San Martín", che ora viene normalizzato in "i" durante la decodifica.
- **Icone presenza scale (San Martín grigia)**: Risolto il bug per cui le icone di compilazione della scala San Martín restavano grigie nelle schede/badge degli utenti pur essendo presenti nel database. Il backend ora arricchisce correttamente la mappa delle scale supportando sia gli ID testuali che gli ID MongoDB (ObjectId), e normalizza gli accenti.
- **Titolo PDF San Martín**: Aggiornato il titolo della scala San Martín nei PDF esportati da "Report Valutativo" a "SCALA SAN MARTÍN", uniformandolo con il corrispettivo "POS ETEROVALUTATIVA".
- **Safety Net Storico**: Aggiunto un ordinamento esplicito lato client nella Dashboard Multidimensionale per garantire che venga prelevata la valutazione più recente in presenza di duplicati o cronologia multipla.

## [2.3.5] - 2026-05-22

### Risolto
- **Dashboard - Distribuzione Documentazione**: La percentuale di completamento per scala veniva ricevuta dal backend con un denominatore errato (somma di tutte le valutazioni anziché numero di pazienti). Il frontend ora calcola la percentuale **lato client** da `count / totalPatients × 100`, garantendo che POS 18/18 → 100% e San Martín 14/18 → 77.8% indipendentemente dal valore restituito dal backend.

## [2.3.4] - 2026-05-22

### Risolto
- **Analisi Utente - Etichetta San Martín**: La colonna San Martín mostrava erroneamente "POS" come titolo. La funzione di rilevamento `_isSanMartinScale` ora controlla sia l'ID che il nome della scala (con normalizzazione accenti/spazi/trattini).
- **Analisi Utente - Grafici sovrapposti**: Il grafico a barre POS aveva `maxY` hardcoded a 20, causando barre schiaccianti per punteggi superiori. Ora il valore massimo dell'asse Y è calcolato dinamicamente dai dati reali (+10% di margine).
- **Analisi Utente - Radar Chart San Martín mancante**: Poiché il rilevamento San Martín falliva, il radar chart non veniva mai renderizzato. Con la correzione dell'identificazione, il grafo radar appare correttamente nella colonna San Martín.

## [2.3.3] - 2026-05-22

### Risolto
- **Allineamento versione UI**: Aggiornata la costante hardcoded `kFrontendVersion` e i file di configurazione (`routes.py`, `pubspec.yaml`) per allineare la versione mostrata in basso a sinistra della dashboard e nei dump del database alla release corretta `2.3.3`.

## [2.3.2] - 2026-05-22

### Risolto
- **Build Flutter Web**: Corretti alcuni errori di tipizzazione di Dart (es. assegnazioni scorrette di tipi di dato ai Map del body per la rotta API, uso di un getter errato per `DomainScore`) che causavano il fallimento silente del compilatore `dart2js` con `exit code 1` durante il deploy su Docker.

## [2.3.1] - 2026-05-22

### Modificato/Risolto
- **Dashboard Multidimensionale**: Corretto il rendering dei grafici a barre in modo che il punteggio effettivo si sovrapponga correttamente alla barra del punteggio massimo, risolvendo l'invisibilità delle barre.
- **Dashboard Principale**: Risolto il calcolo della percentuale di completamento dei documenti per contare il numero di "pazienti unici" invece del totale delle compilazioni storiche.
- **Docker**: Abbassato il livello di ottimizzazione della build di Flutter Web da `-O 4` a `-O 2` per prevenire errori "Out of Memory" (`exit code 1`) durante il deploy tramite Docker Desktop.

## [2.3.0] - 2026-05-22

### Aggiunto
- Modalità "Edit" nella schermata di dettaglio valutazione, per consentire la modifica controllata di metadata (Operatore, Intervistato/a) e risposte.
- Carta intestata formattata (logo + dati fondazione) per tutti i PDF generati (POS e San Martín).
- Titolo dinamico per i PDF ("POS ETEROVALUTATIVA" per la scala POS).

### Modificato
- Refactoring completo della `MultidimensionalDashboardScreen` in stile "Bento Grid" per migliorare l'UX.
- Normalizzazione degli identificatori (rimozione accenti) nel backend per la risoluzione corretta dell'ultima compilazione San Martín.
- Modifica al servizio Gemini per utilizzare system prompt personalizzati sull'expertise ASD.

## [2.2.0] - Precedenti iterazioni
- Creazione dei frontend Flutter (Admin e Client) e backend FastAPI.
- Gestione base delle scale San Martín e POS.
- Setup iniziale del sistema di valutazione multidimensionale.
