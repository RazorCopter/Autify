# Changelog

## [2.19.8] - 2026-06-02
- **Correzioni Pixel-Perfect Area Chart Dashboard**:
  - Risolto il problema di sovrapposizione dell'asse X (Timeline) nel grafico "Attività Redazione Documentazione" tramite l'inserimento di un intervallo discreto basato sulla dimensione dei dati (`interval`) e formattando le etichette per visualizzare solo la sigla del mese abbreviata a 3 lettere (es. "Gen", "Feb"), escludendo l'anno.
  - Riposizionato il badge indicante il trend ("+N / -N vs mese prec.") in alto a sinistra della card, inserendolo all'interno di un layout flessibile `Wrap` immediatamente a fianco del titolo principale per garantire una gerarchia visiva coerente ed ottimizzata.
  - Eseguito il check dei lints e l'analisi statica prima del deploy.

## [2.19.7] - 2026-06-02
- **Redesign UI/UX Dashboard - Fase 2 (Enterprise SaaS 2025)**:
  - Introdotta la nuova `AlertBar` orizzontale reattiva con filtri cliccabili direttamente integrata sotto le card KPI.
  - Sostituito il grafico a ciambella (Donut Chart) di Copertura con il nuovo layout lineare `_buildDocumentCoverageCard` con percentuale gigante, progress bar e statistiche numeriche delle documentazioni valide vs mancanti.
  - Ottimizzato il grafico temporale `_buildLineChartCard` pulendo l'asse X con i soli mesi, e introducendo un badge di trend dinamico e confronto con il mese precedente (es. `+N vs mese prec.`).
  - Potenziato l'Alert Center con ordinamento automatico per gravità di ritardo decrescente, badge di priorità semantici e azioni rapide (link diretto) per gestire l'utente interessato.
  - Modificata la `Sidebar` di navigazione in `main.dart` inserendo tooltip descrittivi al passaggio del mouse su ciascuna voce e ottimizzando lo stato di hover e l'indicatore a capsula Material 3.
  - Compattato il pannello socio-demografico `_buildDemographicsCard` ad altezza 220px, introducendo una progress bar di genere orizzontale a due colori (uomini/donne) e un layout a griglia per le fasce d'età.
  - Integrata la logica di ricerca personalizzata per i tag `scaduti`, `in scadenza`, `incompleti` e `mai valutati` all'interno dell'anagrafica utenti per l'azione diretta dagli alert.

## [2.19.6] - 2026-06-02
- **Redesign UI/UX Dashboard (SaaS 2025)**:
  - Ridotta l'opacità del watermark di sfondo (`kSlothWatermarkOpacity`) all'1.5% in `main.dart` per massimizzare la leggibilità del testo.
  - Riprogettata la barra laterale (sidebar) con sezioni attive evidenziate da una capsula a pillola Material 3 dietro le icone ed effetti hover moderni.
  - Ridisegnate le card KPI (Bento KPI Cards) con sfondo bianco, bordi ardesia sottili, badge pastello arrotondati per le icone e indicatore di trend/variazione.
  - Aggiornato il grafico "Attività di Redazione" sostituendo il grafico a barre con un grafico a linee curve (spline line) con gradiente sfumato sottostante.
  - Riprogettato il centro di controllo delle "Azioni Richieste Urgenti" (Alert Center) con badge di gravità semantica basati sulla scadenza temporale.
  - Ottimizzata la "Distribuzione Documentazione" ordinando gli elementi in base alla criticità di copertura e applicando colori semantici dinamici (rosso <30%, ambra <70%, verde >=70%) per un totale fisso di 6 elementi.

## [2.19.5] - 2026-06-02
- **Miglioramento Layout Dashboard**:
  - Aumentata l'altezza delle card "Azioni Richieste Urgenti" (Alert List) e "Distribuzione Documentazione" da `360` a `420` pixel.
  - Questo incremento previene lo scorrimento (vertical scrolling) all'interno del pannello "Distribuzione Documentazione" quando vengono mostrati tutti i 6 elementi fissi previsti a sistema.

## [2.19.4] - 2026-06-02
- **Dashboard Globale Dinamica**:
  - Collegato l'endpoint `/api/admin/stats` del backend al database MongoDB per estrarre dati reali.
  - Implementato il calcolo dinamico dei dati demografici di contesto (genere e fasce d'età degli utenti).
  - Introdotto il calcolo delle scadenze e copertura basato su una validità temporale di 365 giorni, ordinando gli alert per gravità (utenti mai valutati o scaduti da più giorni).
  - Ottimizzato il trend storico delle somministrazioni degli ultimi 6 mesi e la distribuzione delle scale, forzata a contenere esattamente 6 elementi fissi (SIS, POS, San Martín, OGVA, SABS, OSO) per garantire consistenza visiva.

## [2.19.3] - 2026-06-02
- **Riepilogo per Dominio Transposto in Caso di Molti Domini**: Nelle schermate di dettaglio delle scale di valutazione, la tabella "Riepilogo per Dominio" viene ora automaticamente trasposta se la scala contiene più di 5 domini (es. ODFLAB con 16 domini, POS, SIS). In questo layout verticale ogni dominio corrisponde a una riga della tabella (con wrapping del testo per evitare overflow), e le metriche a colonne, ottimizzando lo spazio ed evitando tagli o scorrimenti orizzontali complessi a qualsiasi risoluzione.

## [2.19.2] - 2026-06-02
- **Layout a Colonne Desktop in "Qualità della Vita"**: Implementata la visualizzazione a 3 colonne affiancate verticalmente ed espanse di default su dispositivi desktop per le tre scale di qualità della vita (POS, San Martín e SIS). Su dispositivi mobili rimane la visualizzazione a singola colonna con accordion.

## [2.19.1] - 2026-06-02
- **Gestione Scadenza Sessione (Re-routing a Login)**: Implementata la gestione globale degli errori `401 Unauthorized` in `ApiService`. Qualsiasi chiamata HTTP al backend che fallisca con stato `401` a causa del token JWT scaduto pulisce ora programmaticamente il `localStorage`/`sessionStorage` ed esegue un ricaricamento forzato (`window.location.reload`) bypassando la cache, reindirizzando automaticamente e in modo sicuro l'utente alla schermata di login.

## [2.19.0] - 2026-06-01
- **Ristrutturazione UI "Analisi Utente" — Navigazione a Tab + Accordion Premium**:
  - Sostituita la precedente unica vista a scorrimento verticale con una navigazione a **3 tab**: "Qualità della Vita", "Comportamento Adattivo" e "Analisi IA".
  - **Tab 1 — Qualità della Vita**: contiene POS, San Martín e SIS (tutte le scale utilizzate nell'interrogazione IA), con compare toggle POS/SM mantenuto.
  - **Tab 2 — Comportamento Adattivo**: contiene ODFLAB, SABS e qualsiasi futura scala comportamentale, con header utente dedicato (gradiente viola).
  - **Tab 3 — Analisi IA**: invariato rispetto alla versione precedente.
  - Introdotto nuovo widget `ExpandableScaleCard` (accordion): ogni scala è mostrata **chiusa di default** con header colorato a gradiente, icona scala e summary chips (indici, percentili, punteggi); cliccando si espande fluidamente con `AnimatedSize` rivelando tutti i grafici e gli indicatori.
  - Introdotto `ScaleSummaryChip`: chip di riepilogo visibili nel collasso della card (Indice QV, Percentile, Totale, Media, Data).
  - Il pulsante "Storico" e "Dettaglio" sono stati integrati come azioni compatte nell'header dell'accordion.
  - Aggiornata la `TabBar` con stile premium (peso font differenziato, `indicatorWeight: 3`, separatore sottile).

## [2.18.38] - 2026-06-01
- **Indicatori di Presenza per Nuove Scale (OGVA, SABS, OSO)**:
  - Aggiunti i badge degli indicatori di completamento per le scale OGVA, SABS e OSO sopra a quelli preesistenti (POS, SM, SIS) in tutte le visualizzazioni degli utenti (griglia card, visualizzazione mobile e tabella desktop nella sezione Utenza).
  - Estesa la logica di scansione dinamica delle compilazioni nel backend (FastAPI) per recuperare le date degli ultimi test OGVA, SABS e OSO.
- **Correzione ed Arricchimento Esportazione CSV**:
  - Incluse le colonne "Ultimo OGVA", "Ultimo SABS" e "Ultimo OSO" all'interno del file CSV generato dall'esportazione degli utenti.
  - Risolto il bug nell'esportazione CSV che impediva la scrittura dei dati corretti a causa di una discrepanza tra le chiavi camelCase utilizzate e quelle snake_case persistite nel DB MongoDB (e.g. data_nascita, ultimo_pos_compilato, etc.).

## [2.18.37] - 2026-06-01
- **Fondo Scala Dinamico dei Grafici a Barre**:
  - Implementato il calcolo del fondo scala dinamico (`maxY` / `dynamicMaxY`) in base ai punteggi reali ottenuti (`max(punteggi) + 5`) sia nella pagina di dettaglio della valutazione che nei pannelli della dashboard multidimensionale. Questo evita che i grafici appaiano schiacciati sul fondo per scale con punteggi massimi teorici molto elevati (come la scala SIS).
  - Corretta l'altezza della barra di sfondo ghost (`backYValue`) sui grafici a pannello per adeguarla al fondo scala dinamico.
  - Ottimizzato l'intervallo degli assi Y (`interval`) nel frontend per variare dinamicamente in base al valore massimo, prevenendo tick sovrapposte.
- **Risoluzione Anomalie PDF ODFLAB**:
  - Risolto il problema del grafico a barre troncato e dei numeri "volanti" sovrapposti nel PDF per scale con punteggi elevati (como ODFLAB), calcolando dinamicamente il fondoscala (`score_max = max(punteggi) + 5`, minimo 15) all'interno del modulo `pdf_generator.py`.
  - Abilitata la rotazione a 45 gradi delle etichette dell'asse X nel PDF per scale con più di 10 domini (usando anche i codici abbreviati) per prevenire le sovrapposizioni di testo.
  - Corretto l'allineamento della tabella "Riepilogo per Dominio" nel PDF: incapsulate le celle in elementi `Paragraph` per consentire l'auto-wrapping ed allargate le colonne (codice a `2.2 * cm`) per ospitare i codici più lunghi (es. `REG_COMP`) senza alcuna sovrapposizione di testi.

## [2.18.36] - 2026-06-01
- **Miglioramento Data Visualization per Scale Complesse (ODFLAB)**: 
  - Risolto l'overflow e la sovrapposizione delle etichette dei domini nella scala ODFLAB (16 domini) ruotando i codici dei domini verticalmente a 90° e aumentando lo spazio riservato.
  - Rimossa la dipendenza fragile dal type check statico del generic list runtime per correggere il rendering dei nomi abbreviati dei domini nel dettaglio delle scale senza tabelle di scoring.
- **Rimozione Dati Demografici Inutilizzati**:
  - Rimossa completamente l'area "Dati Socio-Demografici di Contesto" nel dettaglio delle valutazioni per tutte le scale categorizzate come "Comportamento Adattivo" (come ODFLAB e SABS) in quanto non verranno mai popolati per queste tipologie di scala.

## [2.18.35] - 2026-05-31
- **Fix Esportazione PDF SABS**: Risolto il problema dell'esportazione PDF per la scala SABS che risultava con nome errato ("POS ETEROVALUTATIVA") e senza valori:
  - Aggiornata la chiamata `compute_direct_scores` nell'endpoint di generazione PDF in `routes.py` inserendo il parametro `scale_doc`, in modo da attivare la mappatura dinamica degli item per le scale custom invece del fallimentare prefix-matching.
  - Sostituito il titolo fisso "POS ETEROVALUTATIVA" con il nome reale dinamico (`scala_nome.upper()`) nel report PDF.
  - Impostato il fondoscala (`score_max`) dinamico a 49 se la scala esportata nel PDF è di tipo SABS, configurando correttamente anche la griglia.

## [2.18.34] - 2026-05-31
- **Fix Overflow Grafici Istogrammi**: Risolto il problema di overflow in cui le barre di sfondo (`backDrawRodData`) dei grafici ad istogramma nel cruscotto della dashboard uscivano dal loro spazio di visualizzazione disegnandosi sopra gli indicatori blu. Introdotto il `ClipRect` di sicurezza e impostata l'altezza massima del fondoscala di sfondo vincolata al `dynamicMaxY` per la scala SABS.

## [2.18.33] - 2026-05-31
- **Fondoscala Grafici SABS**: Impostato il fondoscala massimo (valore y) a 49.0 nei grafici ad istogramma (dettaglio e dashboard) per la scala SABS.
- **Nomi Scale Dinamici**: Sostituito il titolo statico "POS Eterovalutativo" con il nome dinamico reale della scala (`scale.nome`) nella sezione "Comportamento Adattivo" della dashboard di analisi utente.

## [2.18.32] - 2026-05-31
- **Calcolo Punteggi Dinamico**: Il calcolo dei punteggi diretti per le scale personalizzate ora mappa dinamicamente domande a sezioni (domini) in `analytics.py`.
- **Comportamento Adattivo**: Aggiornata la categorizzazione UI nella dashboard e aggiunti nomi dinamici per ogni singola scala.

## [2.18.31] - 2026-05-31
- **Fix Scale Rendering**: Corretti i nomi e titoli hardcoded per le scale esterne nella UI.

## [2.18.30] - 2026-05-31
- **Supporto Domande Composite**: Implementato il supporto per domande 'composite' con sottodomande a checklist (es. per scale comportamentali). La UI riconosce il tipo 'composito' e calcola dinamicamente la somma dei comportamenti selezionati.
- **Dashboard Comportamenti Specifici**: Creata la sottosezione dedicata ai comportamenti specifici all'interno della Dashboard Multidimensionale, separandoli dal Progetto di Vita.

## [2.18.29] - 2026-05-30
- **Tracciabilità ed Audit Log IA**: Implementata la scrittura automatica degli audit log educativi (registro) legati alle operazioni sulle relazioni di intelligenza artificiale:
  - `GENERAZIONE_REPORT_IA`: `{operatore} ha generato la Relazione IA per {cognome} {nome}`.
  - `CANCELLAZIONE_REPORT_IA`: `{operatore} ha eliminato la Relazione IA per {cognome} {nome}`.
  - `MODIFICA_REPORT_IA`: `{operatore} ha modificato la nota della Relazione IA per {cognome} {nome} in: {nota_nuova}`.
  Tutti i log estraggono programmaticamente il nome reale del soggetto dal database per conformarsi al formato stabilito.
- **Sincronizzazione Versioni**: Eseguito lo script globale `bump_version.py` per sincronizzare la versione corrente `2.18.29` in tutti i moduli (FastAPI backend, Flutter frontend `pubspec.yaml`, `app_version.dart`, `docker-compose.yml` e `ARCHITECTURE_MAP.md`), garantendo che il numero di versione visualizzato nel menu dell'applicazione sia allineato e coerente.

## [2.18.28] - 2026-05-30
- **Parsing Error Gemini**: Implementato il parsing degli errori di Gemini API sia a livello di parsing JSON che a livello di eccezioni di runtime. Tradotti in messaggi chiari, espliciti e di supporto in lingua italiana, in particolar modo per l'errore di sforamento del limite di spesa mensile (Monthly Spending Cap su Google AI Studio - Errore 429 `RESOURCE_EXHAUSTED`), per il superamento della quota di richieste, chiavi API non valide e modelli obsoleti.
- **UI Dashboard**: Pulita la visualizzazione dell'errore rimuovendo il prefisso tecnico `Exception: ` ed estesa la comparsa del tasto "Vai a Impostazioni" in presenza di qualsiasi errore relativo alle credenziali API.

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
