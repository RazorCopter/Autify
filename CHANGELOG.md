# Changelog

## [2.18.27] - 2026-05-30
- **UI Anagrafica**: Rinominata l'intestazione della schermata da "Utenza" a "Utenti" per maggiore chiarezza e allineamento terminologico.
- **UI Anagrafica**: Modificato il colore dell'indicatore della presenza di una relazione IA nella scheda utente:
  - **Viola** (`Colors.purple.shade700` / `Colors.purple.shade50`) se presente e recente (compilata negli ultimi 6 mesi).
  - **Arancio** (`Colors.orange.shade800` / `Colors.orange.shade50`) se presente ma datata (più vecchia di 6 mesi).
  - **Grigio** (`Colors.grey.shade400` / `Colors.grey.shade100`) se non presente.

## [2.18.22] - 2026-05-30
- **Bugfix PDF Generator**: Risolto errore 500 (`Internal Server Error`) che si verificava all'esportazione del report IA come PDF dal DocumentReader. Il problema era causato da un conflitto di registrazione nel singleton globale `getSampleStyleSheet()` di ReportLab al secondo tentativo di aggiunta dei medesimi stili (`CustomTitle`, `PatientInfo`). Definiti ora localmente ed in sicurezza.

## [2.18.21] - 2026-05-30
- **Bugfix Pydantic**: Aggiunto il campo `ultima_analisi_ia` all'interno della definizione del modello Pydantic `Patient` in `backend/app/models.py`. Questo previene che FastAPI filtri via il campo durante la serializzazione JSON delle risposte in `GET /patients`.
- **UI Anagrafica**: Spostato l'indicatore dell'analisi IA in alto a destra delle card utente per una visualizzazione ottimizzata e un posizionamento preminente.

## [2.18.20] - 2026-05-30
- **Bugfix**: Risolto errore nella query per il recupero dell'ultima analisi IA degli utenti. Il database utilizza la chiave `id_paziente` e non `patient_id`. Ora il badge dell'analisi IA sulle schede utente in anagrafica rileva correttamente la presenza delle relazioni.

## [2.18.19] - 2026-05-30
- **Indicatore Analisi IA nelle schede utente**: Aggiunta icona `psychology_outlined` (la stessa del tab "Analisi IA") nelle card, list view e table view dell'anagrafica per segnalare la presenza di analisi IA. Colore verde se l'ultima analisi è recente (< 6 mesi), giallo/ambra se datata (6-12 mesi), grigio se assente o obsoleta (> 12 mesi). Tooltip con data e stato dettagliato.
- **Backend**: L'endpoint `GET /api/admin/patients` ora include il campo `ultima_analisi_ia` con la data dell'ultima analisi IA recuperata dalla collezione `ai_analyses`.
- **Modello**: Aggiunto campo `ultimaAnalisiIa` al `PatientModel` e aggiornati `fromJson`/`toJson` con `ultima_analisi_ia`.

## [2.18.18] - 2026-05-30
- **Riorganizzazione completa del Tab Analisi IA**: Unificate le tre card separate (Profilo Utente, Seleziona Dati, Dati Aggiuntivi) in un'unica card premium "Configurazione & Avvio Analisi" con 4 sezioni logiche divise da divider: Profilo Utente, Scale da Includere, Contesto Aggiuntivo, Dati Aggiuntivi. Pulsante Avvia Analisi integrato in fondo alla card con gradient e ombra potenziati.
- **Overlay di elaborazione potenziato**: Sfocatura dello sfondo intensificata (blur 20px, opacità 55%), card loader più grande (maxWidth 600) con gradiente elegante.
- **Animazione di elaborazione con logo bradipo**: Il loader puzzle `_SlothPuzzleLoader` ora mostra l'immagine `avatar_bradipo_hd..png` a 280px (prima 180px), contenitore aumentato a 420×420px, testo di caricamento più grande (16px). L'animazione dei pezzi che si ricompongono ed esplodono rimane invariata ma molto più visibile e d'impatto.

## [2.18.16] - 2026-05-30
- **IA e Contesto**: Aggiunto il pannello di selezione dei dati ("Seleziona Dati da Inviare all'IA") nell'interfaccia dell'Analisi IA dell'utente. Ora l'educatore può decidere quali scale includere (POS, San Martín, SIS), se inviare l'intero storico temporale delle compilazioni e se includere i report pregressi selezionati nello storico, mantenendo sempre l'invio delle note testuali e dell'allegato documentale. Tutti i filtri sono selezionati di default per garantire continuità.

## [2.18.15] - 2026-05-30
- **Tracciabilità ed Audit**: Aggiornato il testo dei log di tracciabilità educativa (audit logs) per allinearlo alla regola `[operatore] + [azione] + [dove/chi]`. Ora, all'inserimento di una nuova scala e alla cancellazione di un utente, viene recuperata e mostrata la denominazione in chiaro dell'utente coinvolto (es. *Elena Pisi - Compilata nuova scala: sis_supports_intensity_scale per l'utente [Cognome] [Nome]*).

## [2.18.14] - 2026-05-30
- **UI/Anagrafica**: Rinominato il bottone delle schede utente da "Analisi Multidimensionale" a un più semplice e pulito "Analisi".

## [2.18.13] - 2026-05-30
- **Bugfix**: Risolto errore di compilazione web causato dall'uso dell'API deprecata/assente `html.window.eval`. Ora viene usato `dart:js` (`js.context.callMethod`) per l'esecuzione sicura di script JS interop su Flutter Web.

## [2.18.12] - 2026-05-30
- **Logout e Cache**: Centralizzato il flusso di logout. Oltre all'eliminazione dei token locali, ora il sistema pulisce programmaticamente la cache del browser (`Cache Storage`) e deregistra i `Service Workers` della PWA, forzando poi un ricaricamento completo della pagina per garantire il caricamento dell'ultima versione rilasciata del software senza dover premere manualmente F5.

## [2.18.11] - 2026-05-30
- **Anagrafica**: Rimossa l'altezza dell'utente dalla scheda anagrafica (form di inserimento/modifica, card di riepilogo e vista in tabella) e dal dettaglio delle valutazioni. Aggiornata di conseguenza la suite di test automatizzati.

## [2.18.10] - 2026-05-30
- **Dashboard**: Aggiunti dati socio-demografici (distribuzione per genere e fasce d'età).
- **Anagrafica**: Nuovo layout per le card pazienti e list view, con bottone dedicato e preminente per l'Analisi Multidimensionale.

## [2.18.9] - 2026-05-30
- **Scale**: Aggiunta la validazione rigorosa in fase di salvataggio per tutte le scale: ora è obbligatorio rispondere a tutti gli item prima di poter salvare una valutazione.
- **SIS Wizard**: Il campo "Operatore" non viene più precompilato forzatamente, ma usa un placeholder (hint), permettendo l'inserimento manuale rapido.
- **UI**: Aggiornata la favicon con il nuovo logo dark.

## [2.18.8] - 2026-05-30
- **Bugfix**: Risolto errore 500 su endpoint `/api/admin/audit_logs` causato dalla validazione ObjectId di MongoDB.
- **Export**: Aggiunta la collezione `audit_logs` all'export JSON del database.

## [2.18.7] - 2026-05-30
- **Dashboard**: Aggiornato il calcolo del numero di utenti totali vs utenti attivi nella dashboard.
- **Frontend**: Aggiunto indicatore visivo in tempo reale (`connectivity_plus`) dello stato di connessione offline/online per la PWA.

## [2.18.6] - 2026-05-30
- **Bugfix**: Corretto il calcolo del parsing delle date per la copertura in dashboard.
- **Export**: Aggiunta esportazione CSV per l'anagrafica pazienti.
- **Sincronizzazione e Cache Busting**: Incrementata versione globale a 2.18.6.

## [2.18.5] - 2026-05-30
### Fixed
- Bugfix calcolo validità temporale delle scale valutative (dashboard) tramite parsing date europee DD/MM/YYYY
- Rimossa Dark Mode dal file main.dart (tema fisso Light)

Tutte le modifiche significative a questo progetto saranno documentate in questo file.

## [2.18.4] - 2026-05-29

### Aggiunto / Modificato
- **Dashboard Globale (Statistiche Aggregate)**: Sostituito il placeholder con i dati reali. Aggiunto l'endpoint `/api/admin/stats` al backend per calcolare utenti totali, numero di valutazioni, coverage demografico (sesso, età) e medie per dominio. Aggiornato `api_service.dart` per chiamare la rotta.
- **Timeline Utente (Confronto Storico)**: Aggiunta la possibilità di visualizzare un grafico a linee temporali (trend) nell'analisi multidimensionale per confrontare i punteggi storici (es. POS, San Martín) nel corso del tempo, normalizzati a 100%. Aggiunto il pulsante "Storico" per attivare la visualizzazione modale.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.4`.

## [2.18.3] - 2026-05-29

### Aggiunto / Modificato
- **Revisione Profonda ARCHITECTURE_MAP.md**: Ristrutturazione completa della Single Source of Truth del progetto.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.3`.

## [2.18.2] - 2026-05-29

### Aggiunto / Modificato
- **Integrazione Report IA in Backup/Ripristino del Database**: Inserita la collezione `ai_analyses` all'interno dei processi di export (`/export-db`) ed import (`/import-db`) del database.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.2`.

## [2.18.1] - 2026-05-29

### Aggiunto / Modificato
- **Favicon & Icone PWA ad Alta Definizione**: Aggiornate la favicon principale e le icone PWA con la nuova risorsa premium.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.1`.

## [2.18.0] - 2026-05-29

### Aggiunto / Modificato
- **Mobile Responsiveness (Phase 1)**: Riprogettata l'interfaccia utente del `frontend_admin` per renderla completamente accessibile e navigabile da smartphone.

### Rimozioni e Pulizia
- **Rimozione Client Legacy**: Eliminati completamente dal repository i progetti obsoleti `frontend_client` e `frontend_legacy`.

## [2.17.6] - 2026-05-28
- **Razionalizzazione Spazi Dati Socio-Demografici (Wizard SIS)**: Ottimizzato il layout del grid delle condizioni cliniche.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale a `2.17.6`.

## [2.17.5] - 2026-05-28
- **Modulo Info Legali e About**: Aggiunta nuova finestra di dialogo per condizioni d'uso e privacy policy.
- **Miglioramenti UI e Rebranding Logo**.

## [2.17.4] - 2026-05-28
- **Risoluzione Problema Caching Build Docker su Portainer**.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale a `2.17.4`.

## [2.17.3] - 2026-05-28
- **Transizione Domini di Produzione** al nuovo dominio ufficiale **`tiglio.autify.it`**.

## [2.17.2] - 2026-05-28
- **Risoluzione Encoding e Tastiera Dati Socio-Demografici (San Martín)**.

## [2.17.1] - 2026-05-28
- **Ridenominazione Brand del Progetto in "Autify"**.

## [2.17.0] - 2026-05-28
- **Nuovo Sistema Multi-Utente, Hashing bcrypt e Sessioni JWT (Auth & RBAC)**.

## [2.16.17] - 2026-05-28
- **Nuovo Logo / Avatar Bradipo HD**.

## [2.16.16] - 2026-05-28
- **Sfondo Watermark Bradipo HD post-login**.

## [2.16.15] - 2026-05-28
- **Visibilità Watermark "Light Neural" post-login**: Risolto posizionamento.

## [2.16.14] - 2026-05-28
- **Flusso di Modifica ed Edit UX (Dettaglio Valutazione)**.

## [2.16.13] - 2026-05-28
- **Salvataggio Dati Socio-Demografici nel Dettaglio Valutazione**: Risolto bug.

## [2.16.12] - 2026-05-28
- **Gestione Dati Socio-Demografici**: Risolto errore `TypeError`.

## [2.16.9] - 2026-05-28
- **Integrazione Dati SIS nell'Analisi IA (Gemini)**.

## [2.16.8] - 2026-05-28
- **Comparazione Multidimensionale**: Esclusa scala SIS dal confronto POS/SM.

## [2.16.7] - 2026-05-28
- **User Experience (UX) Sottoscale SIS**: Scroll reset al cambio tab.

## [2.16.6] - 2026-05-28
- **Stato di Validazione e Pulsante di Conferma per i Bisogni Eccezionali**.

## [2.16.5] - 2026-05-28
- **Bug Rendering Sottoscala C nel Wizard SIS**: Risolto.

## [2.16.4] - 2026-05-28
- **Esportazione PDF Premium per la Scala SIS**.

## [2.16.3] - 2026-05-28
- **Gestione e validazione Bisogni Eccezionali**: Fix inizializzazione.

## [2.16.2] - 2026-05-27
- **Bug visualizzazione SIS**: Fix titolo, legenda, layout.

## [2.16.1] - 2026-05-27
- **Bug calcolo direct scores risposte tridimensionali SIS**.

## [2.16.0] - 2026-05-27
- **Wizard Clinico Orchestratore SIS**.

## [2.15.2] - 2026-05-27
- **Gestione Globale Hotkeys via HardwareKeyboard**.

## [2.15.1] - 2026-05-27
- **Widget Personalizzati Premium per la Scala SIS**.

## [2.15.0] - 2026-05-27
- **Integrazione completa del protocollo SIS**.

## [2.14.3] - 2026-05-26
- **Razionalizzazione Testi Storico IA**.

## [2.14.2] - 2026-05-26
- **Miglioramento Usabilità Storico Report IA**.

## [2.14.1] - 2026-05-26
- Fix nullabilità `sesso`.

## [2.14.0] - 2026-05-26
- **Archiviazione Utenti e Filtri di Stato nell'Anagrafica**.

## [2.13.0] - 2026-05-26
- **Ridenominazione Note / Label delle Relazioni IA**.

## [2.12.0] - 2026-05-26
- **Storico Relazioni Multidimensionali e Iniezione Contesto**.

## [2.11.0] - 2026-05-26
- **Document Reader Clinico Virtuale (Fogli A4)**.

## [2.7.2] - 2026-05-23
- **Ottimizzazione Layout "Analisi Utente"**.
- **Evoluzione Data Visualization (Radar Chart)**.
- **Migrazione Modelli Gemini Deprecati**.

## [2.7.1] - 2026-05-23
- **Cancellazione Singolo Record Storico Valutazione**.

## [2.7.0] - 2026-05-23
- **Controllo degli Accessi Basato sui Ruoli (RBAC)**.

## [2.6.2] - 2026-05-22
- **Gestione Dinamica Validità delle Scale**.

## [2.6.1] - 2026-05-22
- **Tooltip Dettagliato Card KPI Dashboard**.

## [2.6.0] - 2026-05-22
- **Bonifica Semantica e Linguaggio Inclusivo**.

## [2.5.1] - 2026-05-22
- **Normalizzazione Scala San Martín**: Fix calcolo massimo teorico.

## [2.5.0] - 2026-05-22
- **Modalità Comparazione ("Compara")**.

## [2.4.1] - 2026-05-22
- **PDF - Rimozione Orari di Apertura, aggiornamento Logo**.

## [2.4.0] - 2026-05-22
- **Rilevamento Scala San Martín**: Fix accenti.

## [2.3.5] - 2026-05-22
- **Dashboard - Distribuzione Documentazione**: Fix percentuale.

## [2.3.4] - 2026-05-22
- **Analisi Utente**: Fix etichetta San Martín, grafici.

## [2.3.3] - 2026-05-22
- **Allineamento versione UI**.

## [2.3.2] - 2026-05-22
- **Build Flutter Web**: Fix errori tipizzazione.

## [2.3.1] - 2026-05-22
- **Dashboard Multidimensionale**: Fix rendering barre.
- **Docker**: Ottimizzazione build.

## [2.3.0] - 2026-05-22
- Modalità "Edit" dettaglio valutazione.
- Carta intestata PDF.

## [2.2.0] - Precedenti iterazioni
- Creazione frontend Flutter e backend FastAPI.