# Changelog

Tutte le modifiche significative a questo progetto saranno documentate in questo file.

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
