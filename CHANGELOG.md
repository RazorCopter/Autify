# Changelog

Tutte le modifiche significative a questo progetto saranno documentate in questo file.
## [2.15.1] - 2026-05-27

### Aggiunto
- **Widget Personalizzati Premium per la Scala SIS**:
  - Sviluppato `Sis3DItemCard` (`sis_3d_item_card.dart`): Card premium in Material 3 e Bento style per i 57 item tridimensionali, con layout responsivi adattivi, tooltips operativi, gestione disabilitazione e feedback leggende in tempo reale.
  - Sviluppato `SisMedicalList` (`sis_medical_list.dart`): Lista semantica per Sezione 3 medica e comportamentale con pulsanti a colori semantici ad alto impatto visivo [0, 1, 2] e banner di Warning animato integrato in real-time.
  - Sviluppato `SisRankingWidget` (`sis_ranking_widget.dart`): Componente asincrono per l'estrazione automatica dei Top 4 bisogni di Protezione (Sezione 2) e riordinamento interattivo tramite trascinamento drag & drop (`ReorderableListView`).
- **Allineamento Versioni**: Incrementata la versione della suite a `2.15.1` in `app_version.dart`, `pubspec.yaml` (admin), `pubspec.yaml` (client a `2.7.3`) e `main.py` (FastAPI backend).

## [2.15.0] - 2026-05-27
- **Integrazione completa del nuovo protocollo "Supports Intensity Scale (SIS)" (Frontend & Backend)**:
  - **Motore di calcolo Backend**: Implementato in `analytics.py` il motore psicometrico tridimensionale (Frequenza, Durata, Tipo di sostegno: range 0-4) con tabelle `SIS_DOMAIN_RANGES`, `SIS_INDEX_TABLE`, gestione eccezione item A3 (F_max=3), estrazione Top 4 bisogni di protezione (Sezione 2) ed alert medici/comportamentali (Sezione 3).
  - **Modelli Dati Flessibili**: Aggiornato `AnswerModel` in `models.py` (backend) e nei modelli del frontend (`evaluation_model.dart` per Admin e `models.dart` per Client) per consentire al campo `punteggio` di accettare dinamici `Map<String, int>` (payload tridimensionali `{"F": x, "D": y, "T": z}`) senza provocare conflitti di compilazione.
  - **Interfaccia Grafica Tridimensionale nel Wizard**: Rilevazione automatica delle sezioni SIS tridimensionali nel wizard (`wizard_screen.dart` sia nell'Admin che nel Client) per sostituire la visualizzazione classica con tre eleganti selettori reattivi e animati in stile premium (Frequenza, Durata e Tipo di sostegno) comprensivi di badge e descrizioni testuali dinamiche delle leggende in tempo reale.
  - **Validità dei Dati**: La navigazione tra le domande richiede obbligatoriamente il completamento di tutte e tre le dimensioni di risposta prima di poter cliccare su "Avanti" o salvare.
  - **Test Suite**: Realizzata la suite `test_sis.py` per validare asincronamente tutti i test del backend superando 10/10 test con successo.
- **Aggiornamento Versione**: Incrementata la versione globale della suite a `2.15.0` in `app_version.dart`, `pubspec.yaml` (admin) e `main.py` (FastAPI backend).

## [2.14.3] - 2026-05-26

### Ottimizzato
- **Razionalizzazione Testi Storico IA**: Spostata la descrizione estesa dell'iniezione del contesto nello storico direttamente all'interno del banner verde premium di informazioni (tooltip) e rimossa la precedente etichetta descrittiva duplicata per eliminare ridondanze visive e rendere il layout più compatto ed elegante.

## [2.14.2] - 2026-05-26

### Aggiunto
- **Miglioramento dell'Usabilità dello Storico Report IA**: Inserito un banner informativo premium sopra la checklist dello storico per spiegare chiaramente lo scopo dei checkbox di selezione ("Seleziona per utilizzare questo report nella nuova analisi IA").
- **Ottimizzazione Schermata Impostazioni**: Modificata l'apertura di default dei pannelli di espansione ("Gestione Accessi e Sicurezza" e "Configurazione AI (Gemini)"), ora impostati come chiusi all'avvio della pagina per una consultazione più ordinata e pulita.

## [2.14.1] - 2026-05-26

### Corretto
- Risolto un errore di compilazione sul client Flutter admin in `multidimensional_dashboard_screen.dart` correlato alla nullabilità dell'attributo `sesso` dell'utente (`String?`), che impediva il corretto completamento della build Docker nel container di produzione.

## [2.14.0] - 2026-05-26

### Aggiunto
- **Archiviazione Utenti e Filtri di Stato nell'Anagrafica**:
  - Aggiunto l'attributo booleano `attivo` al modello backend `Patient` in `models.py` (con default `True`).
  - Creata una migrazione asincrona e silenziosa nel database MongoDB all'interno del metodo `get_patients` in `routes.py`, per popolare tutti i vecchi documenti sprovvisti di `attivo` impostandoli a `True`.
  - Aggiornato il modello client `PatientModel` in `patient_model.dart` per supportare la deserializzazione e la serializzazione del campo `attivo`.
  - Ristrutturata la schermata `AnagraficaScreen` in `anagrafica_screen.dart` aggiungendo un dropdown di selezione filtri ("Solo Attivi", "Archiviati", "Tutti gli utenti") a fianco della barra di ricerca, con filtraggio istantaneo lato client.
  - Integrato un `StatefulBuilder` e un widget `SwitchListTile` nel dialog di modifica dell'anagrafica utente per consentire l'archiviazione (disattivazione) o il ripristino istantaneo dello stato dell'utente.
- **Aggiornamento Versione**: Incrementata la versione globale della suite a `2.14.0` in `app_version.dart` e `pubspec.yaml` (admin).

## [2.13.0] - 2026-05-26

### Aggiunto
- **Ridenominazione Note / Label delle Relazioni IA**:
  - Aggiunto l'endpoint `PUT /patients/ai-analyses/{id_analysis}` nel backend FastAPI in `routes.py` per aggiornare le note (etichette) delle relazioni salvate.
  - Implementato il metodo client `updateAiAnalysisLabel` in `api_service.dart`.
  - Integrata l'azione di ridenominazione tramite una dialog interattiva di inserimento (`_renameSavedAnalysisLabel`) nel tab AI del frontend admin, con aggiornamento dinamico immediato dello storico.
- **Aggiornamento Versione**: Incrementata la versione globale della suite a `2.13.0` in `app_version.dart` e `pubspec.yaml` (admin).

## [2.12.0] - 2026-05-26

### Aggiunto
- **Storico Relazioni Multidimensionali e Iniezione Contesto**:
  - Creata la nuova collezione MongoDB `ai_analyses` e definiti i relativi endpoint API REST (`GET`, `POST`, `DELETE`) asincroni e protetti da RBAC nel backend.
  - Implementati i corrispondenti metodi del client HTTP del frontend in `api_service.dart`.
  - Integrata in `GeminiService` la capacità di ricevere ed iniettare lo storico selezionato delle relazioni precedenti all'interno del prompt di Gemini, per un'analisi evolutiva longitudinale.
  - Aggiunta l'opzione grafica "Salva in Storico" a fianco dei comandi del report generato con indicatori reattivi di caricamento.
  - Inserito il pannello premium *"Storico Relazioni IA e Iniezione Contesto"* con checklist di selezione, pulsante per leggere al volo qualsiasi relazione precedente nel `DocumentReaderScreen` e comandi di eliminazione sicura con modal di conferma.
  - Eseguita una bonifica meticolosa e sistematica del vocabolario, sostituendo i riferimenti clinici con termini inclusivi di supporto ed educativi (es. `"andamento educativo e di supporto nel tempo"` al posto di `"evoluzione clinico-funzionale"`).
- **Allineamento Versioni**: Incrementata la versione globale della suite a `2.12.0` in `app_version.dart` e `pubspec.yaml` (admin).

## [2.11.0] - 2026-05-26

### Aggiunto
- **Document Reader Clinico Virtuale (Fogli A4)**:
  - Sviluppata la nuova schermata `DocumentReaderScreen` per la visualizzazione immersiva delle relazioni AI.
  - Impaginazione ad alta fedeltà con fogli A4 virtuali, testata clinica personalizzata, margini reali e piè di pagina con numerazione automatica ("Pagina X di Y").
  - Supporto alle interruzioni di pagina fisiche tramite il tag markdown standard `---`.
  - Controlli premium nella toolbar: regolazione della dimensione del font, zoom dei fogli, copia testo rapida ed esportazione PDF integrata.
  - Switch interattivo tra tre temi colore: *Clinical* (bianco/slate), *Warm* (avorio/crema) e *Dark* (antracite/scuro).
  - Collegamento diretto in `MultidimensionalDashboardScreen` tramite pulsante "Modalità Lettura" e pulsante rapido "Schermo Intero / Lettura A4" all'interno della Card di sintesi clinica.
- **Allineamento Versioni**: Incrementata la versione globale della suite a `2.11.0` in `app_version.dart` e `pubspec.yaml` (admin).

## [2.7.2] - 2026-05-23

### Modificato
- **Ottimizzazione Layout "Analisi Utente"**:
  - Equalizzate dinamicamente le altezze dei box "POS Eterovalutativo" e "San Martín" sopra i grafici utilizzando flexbox con allineamento stretched (`crossAxisAlignment: CrossAxisAlignment.stretch`) nella visualizzazione desktop, garantendo una perfetta simmetria visiva e l'assenza di spazi vuoti asimmetrici.
  - Introdotto un sotto-box interno dedicato alla **Legenda dei Domini** all'interno del card POS, con scorrimento verticale personalizzato (`Scrollbar` + `SingleChildScrollView`), mostrando il mapping dinamico `[Sigla] = [Nome Esteso]: [Valore]` basato sui punteggi del paziente per massimizzare la leggibilità ed evitare di occupare spazio extra.
  - Aggiornate le etichette delle colonne in accordo con la terminologia clinico-educativa inclusiva: POS rinominato in `"POS Eterovalutativo"` con sottotitolo `"Valutazione degli esiti personali e della QQdV percepita"`, e San Martín con sottotitolo `"Valutazione osservativa della qualità di vita"`.
- **Evoluzione Data Visualization (Radar Chart)**:
  - Esteso il grafico radar (`RadarChart` di `fl_chart`) per la scala San Martín incorporando due dataset di riferimento stabili:
    - **Media normativa** (punteggio costante a 10.0) con linea tratteggiata rossa e riempimento rosso semi-trasparente ultra-soft.
    - **Range medio** (punteggio costante a 12.0) con linea e riempimento verde semi-trasparente per identificare immediatamente il posizionamento clinico del paziente rispetto ai parametri standard.
  - Sviluppato un custom painter premium (`_RadarLabelsPainter`) sovrapposto al grafico che disegna badge numerici eleganti e ad alto contrasto (sfondo arancione soft, bordo arancione e testo scuro) posizionati in modo intelligente sopra i punti dati del paziente, fornendo la lettura immediata ed esatta dei valori per ciascun dominio.
- **Gestione Sicura e Caricamento On-Demand delle Credenziali AI**:
  - Risolto il problema del caricamento della chiave API di Gemini mascherata (`***-HIDDEN`) modificando l'endpoint `/settings` del backend per supportare un parametro query sicuro `raw=true` (riservato al ruolo Admin). L'interfaccia esegue ora il caricamento della chiave in chiaro in background solo all'effettivo tocco sul pulsante d'analisi.
- **Raddoppio Dimensioni Caratteri della Legenda POS**:
  - Raddoppiato il font delle scritte in legenda a `23.0` per una lettura ottimale e potenziata la spaziatura del `Wrap` (`spacing: 24`, `runSpacing: 12`).
- **Migrazione Modelli Gemini Deprecati (Google AI Studio 2026)**:
  - Disattivati i riferimenti predefiniti ai vecchi modelli dismessi `gemini-1.5-pro` e `gemini-1.5-flash` (che causavano errori 404/Not Found). Configurato come nuovo modello predefinito globale il capostipite stabile **`gemini-2.5-pro`**.
  - Integrato nel menu a discesa delle impostazioni le opzioni attive di ultima generazione: `gemini-2.5-pro` (Consigliato), `gemini-2.5-flash` (Veloce) e `gemini-3.5-flash` (Frontiera), comprensive di migrazione e sanificazione automatica e reattiva dei dati legacy per evitare crash di layout nel frontend.
- **Allineamento Versioni**: Incrementata la versione globale della suite a `2.7.2` in `app_version.dart`, `pubspec.yaml` (admin e client), `main.py` e `routes.py` (metadata backup).

## [2.7.1] - 2026-05-23

### Aggiunto
- **Cancellazione Singolo Record Storico Valutazione**:
  - Implementata la possibilità di eliminare definitivamente una specifica valutazione storica direttamente dalla schermata di dettaglio ([evaluation_detail_screen.dart](file:///home/gianvito/progetti/AutAnalysis/frontend_admin/lib/screens/evaluation_detail_screen.dart)).
  - **Integrazione RBAC & Safety UX**: L'opzione di cancellazione non viene renderizzata nel DOM per il ruolo Viewer. Per l'utente Admin, il pulsante (icona a forma di "X" circolare) compare ed è cliccabile solo se la modalità di modifica ("Edit Mode") è attiva.
  - **Safety UX (Modal di Conferma)**: Introdotto un dialog premium di conferma eliminazione con avviso di irreversibilità dell'operazione.
  - **Aggiornamento Reattivo dello Stato**: Alla rimozione asincrona del record, la lista dello storico locale `_history` viene aggiornata istantaneamente senza provocare il ricaricamento dell'intera schermata.
- **Protezione API Backend**:
  - Sviluppato l'endpoint `DELETE /evaluations/{evaluation_id}` in [routes.py](file:///home/gianvito/progetti/AutAnalysis/backend/app/routes.py), protetto dal middleware di autenticazione asimmetrico `verify_admin_auth` (bloccando le chiamate non autorizzate con `403 Forbidden`).
- **Allineamento Versioni**: Incrementata la versione della suite a `2.7.1` in `app_version.dart`, `pubspec.yaml` (admin e client), `main.py` e `routes.py` (metadata backup).

## [2.7.0] - 2026-05-23

### Aggiunto
- **Controllo degli Accessi Basato sui Ruoli (RBAC)**: Evoluto il sistema di autenticazione introducendo la gestione differenziata delle autorizzazioni per due profili utente distinti:
  - **Admin (Profilo 1)**: Mantiene l'accesso completo e illimitato a tutte le operazioni CRUD (Create, Read, Update, Delete) sia nel backend che nei frontend.
  - **Viewer (Profilo 2 - Sola Lettura)**: Profilo protetto e limitato alla sola consultazione ed esplorazione delle informazioni, dei protocolli e dei report multidimensionali.
- **Sicurezza e Protezione Backend**:
  - Implementata la verifica del ruolo nel middleware di sicurezza (`verify_admin_auth` in `routes.py`) per intercettare e bloccare sul nascere tutte le richieste di scrittura (POST, PUT, DELETE) associate alle credenziali del ruolo Viewer, restituendo un errore standardizzato `403 Forbidden`.
  - Riorganizzato il sistema di credenziali per supportare due password distinte (`ADMIN_PASSWORD` e `VIEWER_PASSWORD`).
- **Restrizioni Dinamiche dell'Interfaccia Utente (Frontend Admin)**:
  - **Gestione Sessioni e Badge di Stato (`login_screen.dart` / `main.dart`)**: Introdotto il salvataggio sicuro del ruolo attivo in locale. Mostrato un badge grafico elegante nell'interfaccia principale per visualizzare chiaramente il livello di accesso corrente ("Amministratore" vs "Visualizzatore - Sola Lettura").
  - **Impostazioni di Sistema (`settings_screen.dart`)**: Disabilitati in modalità Viewer i cursori per la regolazione dei parametri di validità delle scale, i pulsanti per l'esportazione e l'importazione del database, la chiave API e il modello di Gemini.
  - **Anagrafica Utenti (`anagrafica_screen.dart`)**: Disabilitati i comandi di creazione di nuovi utenti e le azioni di modifica ed eliminazione sia all'interno delle schede individuali che nell'elenco tabellare.
  - **Protocolli di Supporto (`protocols_screen.dart`)**: Disabilitati e colorati in tonalità grigia premium i comandi per rinominare ed eliminare le scale di valutazione.
  - **Dettaglio Valutazione (`evaluation_detail_screen.dart`)**: Nascosti completamente i pulsanti "Edit" e "Salva modifiche" nell'AppBar per l'utente Viewer, impedendo qualsiasi modifica retroattiva alle valutazioni salvate.
  - **Selezione Valutazione (`selection_screen.dart`)**: Disabilitato il pulsante per avviare una nuova valutazione, con aggiornamento dinamico della label in "Sola Lettura - Compilazione Disabilitata".
  - **Wizard di Compilazione (`wizard_screen.dart`)**: Inserita una guardia logica di controllo nel metodo di salvataggio `_saveEvaluation()` per intercettare e respingere a livello client qualsiasi tentativo anomalo di sottomissione dati da parte del Viewer.
- **Allineamento Versioni**: Incrementata la versione dell'intera suite a `2.7.0` in `app_version.dart`, in entrambi i file `pubspec.yaml` (admin e client), ed esportata nei metadati dei backup del database in `routes.py` e `main.py`.

## [2.6.2] - 2026-05-22

### Aggiunto
- **Gestione Dinamica e Reattiva della Validità delle Scale**: Implementato un sistema client-side reattivo completo per regolare i parametri di scadenza delle scale di valutazione (POS e San Martín).
  - Aggiunta una sezione "Parametri di Validità Scale" nelle Impostazioni con tre Slider per regolare:
    - Mesi di validità per la scala POS (1-24 mesi).
    - Mesi di validità per la scala San Martín (1-24 mesi).
    - Giorni di preavviso per l'alert di scadenza (0-60 giorni).
  - Persistenza locale dei parametri tramite `shared_preferences`.
  - Propagazione globale e in tempo reale dello stato reattivo tramite il pacchetto `provider` (`SettingsNotifier`).
  - Aggiornamento dinamico istantaneo degli indicatori di stato ("POS", "SM") nella lista utenti (`anagrafica_screen.dart`), ricalcolati in base alle nuove soglie tramite la classe helper `ValidityCalculator`.
  - Tooltip informativi arricchiti con il dettaglio dei mesi di validità attuali per una trasparenza ottimale.
- **Miglioramento dell'Usabilità**: Avvolta la schermata Impostazioni in un contenitore a scorrimento verticale (`SingleChildScrollView`) per prevenire overflow dell'interfaccia su schermi con risoluzione verticale ridotta.

### Modificato
- **Allineamento Versioni**: Incrementata la versione dell'intera suite a `2.6.2` in `app_version.dart`, in entrambi i file `pubspec.yaml` (admin e client), ed esportata nei metadati dei backup del database in `routes.py`.

## [2.6.1] - 2026-05-22

### Aggiunto
- **Tooltip Dettagliato Card KPI Dashboard**: Aggiunto un tooltip interattivo e animato con stile premium (sfondo scuro semi-trasparente, bordi arrotondati, testo formattato) alla card "DA VALUTARE / SCADUTI" sulla Dashboard per visualizzare l'esatto conteggio delle scale mancanti/scadute separate per tipologia (POS e San Martín). Supporta sia l'hover su desktop che il tap su dispositivi mobili/tablet.

### Modificato
- **Logica Card KPI Dashboard (Conteggio Individuale Scale)**: Modificata la logica di calcolo delle card KPI "Valutazioni Attive" e "Da Valutare / Scaduti" nella Dashboard. Ora i contatori mostrano la somma totale dei singoli test/scale (POS + San Martín) validi o mancanti anziché il conteggio univoco degli utenti, calcolando la percentuale di copertura rispetto al massimo teorico delle scale somministrabili (2 per utente).
- **Allineamento Versioni**: Incrementata la versione dell'intera suite a `2.6.1` in `app_version.dart`, in entrambi i file `pubspec.yaml` (admin e client), ed esportata nei metadati dei backup del database in `routes.py`.

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
