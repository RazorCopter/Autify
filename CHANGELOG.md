# Changelog

Tutte le modifiche significative a questo progetto saranno documentate in questo file.

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
