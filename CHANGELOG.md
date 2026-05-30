# Changelog

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
- **Dashboard Globale (Statistiche Aggregate)**: Sostituito il placeholder con i dati reali. Aggiunto l'endpoint `/api/admin/stats` al backend per calcolare utenti totali, numero di valutazioni, coverage demografico (sesso, etÃ ) e medie per dominio. Aggiornato `api_service.dart` per chiamare la rotta.
- **Timeline Utente (Confronto Storico)**: Aggiunta la possibilitÃ  di visualizzare un grafico a linee temporali (trend) nell'analisi multidimensionale per confrontare i punteggi storici (es. POS, San MartÃ­n) nel corso del tempo, normalizzati a 100%. Aggiunto il pulsante "Storico" per attivare la visualizzazione modale.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.4`.


## [2.18.3] - 2026-05-29

### Aggiunto / Modificato
- **Revisione Profonda ARCHITECTURE_MAP.md**: Ristrutturazione completa della Single Source of Truth del progetto.
  - **Regole di Ingaggio spostate in testa (Â§0)**: Il protocollo operativo obbligatorio per l'IA Ã¨ ora la prima sezione del documento, con diagramma di flusso Mermaid del workflow a 8 step, tabella dei file di versione da sincronizzare e vincoli codificati.
  - **Diagrammi Mermaid**: Sostituiti tutti i diagrammi ASCII art con diagrammi Mermaid renderizzabili (architettura, autenticazione JWT, 4 flussi dati).
  - **Indice navigabile (Table of Contents)**: Aggiunta tabella-indice con link interni per navigazione rapida.
  - **Correzioni fattuali**: Fix link ai file (da percorsi Linux errati a percorsi corretti), aggiunta scala SIS nella documentazione, aggiunta collezione `ai_analyses` in Â§4 Database, aggiornamento tree frontend con directory mancanti (`widgets/`, `utils/`, `theme/`), rimozione riferimenti al vecchio sistema di autenticazione legacy.
  - **Nuova sezione Infrastruttura & Deploy (Â§3.3)**: Documentazione di `docker-compose.yml`, servizi, porte, volumi e script di deploy.
  - **Nuova sezione Database (Â§4)**: Tabella completa delle 6 collezioni MongoDB con indicazione del perimetro di backup.
  - **Miglioramenti visivi**: Uso di GitHub Alerts, tabelle compatte, emoji tematiche per sezione, layout professionale.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.3`.

## [2.18.2] - 2026-05-29

### Aggiunto / Modificato
- **Integrazione Report IA in Backup/Ripristino del Database**: Inserita la collezione `ai_analyses` all'interno dei processi di export (`/export-db`) ed import (`/import-db`) del database, garantendo la conservazione e l'allineamento dei report generati con l'Intelligenza Artificiale nelle procedure di migrazione o installazioni pulite.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.2` (frontend admin `pubspec.yaml`, `app_version.dart`, FastAPI backend `main.py` e `docker-compose.yml` per l'aggiornamento cache dei container).

## [2.18.1] - 2026-05-29

### Aggiunto / Modificato
- **Favicon & Icone PWA ad Alta Definizione**: Aggiornate la favicon principale e le icone PWA (`Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`) con la nuova risorsa premium quadrata a 512x512 pixel.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale della suite a `2.18.1` (frontend admin `pubspec.yaml`, `app_version.dart`, FastAPI backend `main.py` e `docker-compose.yml` per l'aggiornamento cache dei container).

## [2.18.0] - 2026-05-29

### Aggiunto / Modificato
- **Mobile Responsiveness (Phase 1)**: Riprogettata l'interfaccia utente del `frontend_admin` per renderla completamente accessibile e navigabile da smartphone (Portrait-locked).
  - **Infrastruttura**: Aggiunto `<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">` e forzato il blocco orientamento in portrait in `index.html`. Creato l'utility `ResponsiveHelper` per gestire i breakpoint logici (Mobile, Tablet, Desktop) in modo centralizzato.
  - **Layout Principale (main.dart)**: Sostituita la sidebar statica con un sistema adattivo. Su schermi desktop rimane la Sidebar classica, su mobile viene visualizzata una `BottomNavigationBar` sul fondo con menu Hamburger e `Drawer` per loghi, azioni secondarie (about, logout) e badge di ruolo.
  - **Watermark e Backgrounds**: Ottimizzato il posizionamento del watermark decorativo (sovrapposto con `IgnorePointer`) e ridotta l'opacitÃ  su mobile per massimizzare la leggibilitÃ .
  - **Login Screen**: Rimossa la limitazione della larghezza fissa (400px), il form ora utilizza un `ConstrainedBox` e adatta automaticamente il padding e le dimensioni del logo.
  - **Dashboard Analitica**: Ristrutturato l'header per passare da una disposizione in riga a una in colonna sui display piÃ¹ stretti, ridimensionando automaticamente i font dei titoli.
  - **Anagrafica Utenti**: Reso responsivo il layout con `_buildResponsiveHeader` e `_buildResponsiveSearchBar`. I pulsanti d'azione, la casella di ricerca e i filtri di stato si impilano verticalmente su schermi piccoli. La griglia delle card adotta dinamicamente le larghezze per le colonne.
  - **Selezione Valutazione & Protocolli**: Adattati i titoli degli header e allineate dinamicamente le griglie delle schede.
  - **Impostazioni di Sistema**: Il widget degli slider per la configurazione (`_buildSliderRow`) ora si impila su due righe per evitare sfocature o out-of-bounds nei valori su display stretti. Diminuiti i padding laterali negli `ExpansionTile` su schermi mobile.

### Rimozioni e Pulizia
- **Rimozione Client Legacy**: Eliminati completamente dal repository i progetti obsoleti `frontend_client` e `frontend_legacy` e ripulito il file `docker-compose.yml` e la mappa architetturale dai servizi e container non piÃ¹ utilizzati, riducendo l'impronta complessiva del progetto.


## [2.17.6] - 2026-05-28

### Ottimizzato
- **Razionalizzazione Spazi Dati Socio-Demografici (Wizard SIS)**: Ottimizzato il layout del grid delle condizioni cliniche associate all'interno dello step di Intake della scala SIS sia per `frontend_admin` che per `frontend_client`. Sostituito il precedente `GridView.count` (che introduceva enormi spazi vuoti verticali su schermi desktop/tablet a causa del `childAspectRatio` fisso) con un `GridView` flessibile guidato da `SliverGridDelegateWithFixedCrossAxisCount` ed un `mainAxisExtent` bloccato a `36`. Questo garantisce una corretta spaziatura e dimensioni stabili di 36px per riga a prescindere dalla larghezza dello schermo, eliminando tutti gli enormi spazi vuoti tra le righe di checkbox.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale a `2.17.6` e configurato `CACHE_BUST=2.17.6` per tutti i moduli.

## [2.17.5] - 2026-05-28

### Aggiunto
- **Modulo Info Legali e About**: Aggiunta una nuova finestra di dialogo (AboutTermsDialog) integrata nella sidebar sotto la versione dell'app per visualizzare in modo pulito e scrollabile le condizioni d'uso e la privacy policy di Autify.

### Modificato
- **Miglioramenti UI e Rebranding Logo**: 
  - Sostituito il logo nella schermata di login con il nuovo `logoAutifyDark.png` (+20% grandezza per maggiore leggibilitÃ ).
  - Rimossa la scritta testuale "Autify" in basso dalla sidebar principale e ingrandito il logo ufficiale nativo `logo_autify_int.png` rimuovendo le maschere e i bordi circolari obsoleti, integrando cosÃ¬ l'immagine direttamente come parte nativa della navigation bar.
  - Sostituiti tutti gli avatar circolari obsoleti (es. loading dashboard e sidebar) con il logo aggiornato.

### Sicurezza (Corretto)
- **Patch Critica Gestione Sessione di Logout**: Risolta una gravissima vulnerabilitÃ  di sicurezza (Zero-Day Logico). In precedenza, alla pressione del tasto di disconnessione, l'applicazione non provvedeva a distruggere il token crittografico `jwt_token` persistente dal database locale (`localStorage`). Questo consentiva ad un utente scollegato di premere "F5" per aggiornare la pagina e rientrare indebitamente bypassando la schermata di Login, con un fallback automatico al ruolo in sola lettura (`viewer`). Da questa versione il logout distrugge interamente l'ambiente di sessione JWT e disconnette forzatamente ogni stato attivo.

## [2.17.4] - 2026-05-28
- **Risoluzione Problema Caching Build Docker su Portainer**: Sostituiti gli URL Git di GitHub all'interno del parametro `context` di `docker-compose.yml` con percorsi relativi locali (`./backend`, `./frontend_admin`, `./frontend_client`). Questo impedisce a Docker di riutilizzare check-out obsoleti memorizzati nella cache interna e lo costringe ad utilizzare direttamente i file fisici aggiornati da Portainer sul disco dell'host.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale a `2.17.4` e configurato `CACHE_BUST=2.17.4` su tutti i moduli per forzare la ricompilazione completa ed escludere qualsiasi persistenza di cache obsoleta.

## [2.17.3] - 2026-05-28

### Modificato
- **Transizione Domini di Produzione**: Aggiornati tutti gli endpoint API e URL di produzione all'interno di `frontend_admin`, `frontend_client` e `frontend_legacy` dal vecchio dominio `aut.ghome.it` al nuovo dominio ufficiale **`tiglio.autify.it`**.
- **Aggiornamento CORS**: Aggiornata la configurazione e la documentazione CORS nel backend FastAPI (`main.py`) e in `ARCHITECTURE_MAP.md` per allinearsi al nuovo dominio ufficiale.
- **Sincronizzazione e Cache Busting**: Incrementata la versione globale a `2.17.3` e configurato `CACHE_BUST=2.17.3` in `docker-compose.yml` per forzare la compilazione pulita dei moduli Flutter Web sul server di produzione Portainer.

## [2.17.2] - 2026-05-28

### Corretto
- **Risoluzione Encoding e Tastiera Dati Socio-Demografici (San MartÃ­n)**:
  - Risolti gli errori di codifica dei caratteri accentati ("Ã ", "Ã­") all'interno della scheda dei dati socio-demografici del frontend admin.
  - Disabilitato il listener globale dei tasti numerici rapidi (da 1 a 4) durante la compilazione della scheda dei dati socio-demografici sia per il client che per l'admin, impedendo che i tasti venissero intercettati a livello globale e ripristinando la normale digitazione numerica.
- **Sincronizzazione Versioni**:
  - Incrementata la versione globale della suite a `2.17.2` (backend API, frontend_admin, frontend_client).

## [2.17.1] - 2026-05-28

### Modificato
- **Ridenominazione Brand del Progetto in "Autify"**:
  - Transizione nominale completa dell'intero sistema multi-frontend e dell'infrastruttura di rete (servizi e container Docker, proxy Nginx, MaterialApp title, intestazioni e scritte grafiche) da **AutAnalysis** al nuovo brand **Autify**.
  - **Decisione Architetturale (Opzione B)**: Mantenuto il nome del database MongoDB esistente a `autanalysis` per prevenire regressioni strutturali ed evitare la perdita di dati clinici storici in ambiente di sviluppo e produzione. Decisione formalizzata nella mappa architetturale.
  - **Nuovo Logo Autify**: Integrata la risorsa grafica premium ad alta definizione `autify_logo.png` a sostituzione del logo bradipo.
- **Risoluzione Typo clinico POS**:
  - Corretta la dicitura `QQdV` (con doppia Q) nel termine corretto **QdV** (*QualitÃ  di Vita*) all'interno della dashboard multidimensionale dell'applicazione amministrativa.
- **TracciabilitÃ  Avanzata del Registro Accessi**:
  - Estesa la persistenza del registro accessi su file (`viewer_logs.json`) per tracciare lo `username` ed il `role` di tutti gli operatori (sia `admin` che `viewer`) che eseguono correttamente la procedura di login.
  - Sviluppata l'interfaccia di visualizzazione dei log in *Impostazioni* introducendo un pannello di filtri interattivi (`ChoiceChip`), badge grafici colorati distinti per i ruoli ed il troncamento intelligente dei dispositivi lunghi (user-agent) tramite `Tooltip` al passaggio del mouse.

## [2.17.0] - 2026-05-28

### Aggiunto
- **Nuovo Sistema Multi-Utente, Hashing bcrypt e Sessioni JWT (Auth & RBAC v2.17.0)**:
  - **Archiviazione MongoDB & Hashing bcrypt**: Transizione dalle credenziali globali su file di configurazione (`ADMIN_PASSWORD`, `VIEWER_PASSWORD`) a una vera gestione multi-utente con credenziali univoche e password cifrate tramite algoritmo robusto **bcrypt** (rounds=12) memorizzate nella nuova collezione MongoDB `users`.
  - **Token JWT per la Gestione delle Sessioni**: Implementato il rilascio di token standard **JSON Web Tokens (JWT)** con validitÃ  limitata (8 ore) all'accesso. Il frontend memorizza in sicurezza il token in `localStorage['jwt_token']` e lo trasmette come header `Authorization: Bearer <token>` a tutte le API protette.
  - **Gestione Utenze e Pannello Amministratore**: Sviluppata la sezione di amministrazione utenze all'interno della schermata "Impostazioni" nel frontend Admin (accessibile solo al ruolo `admin`). Consente la gestione CRUD completa (creazione, modifica ruolo, reset password, e abilitazione AI per ogni singolo operatore, bloccando l'auto-eliminazione).
  - **Logica di Primo Accesso (Bootstrap)**: Introdotta la creazione automatica di un utente amministratore di default (`admin` / `admin`) al primo avvio dell'applicazione (se la collezione `users` Ã¨ vuota), con vincolo di username immutabile per motivi di sicurezza e tracciamento.
  - **Autorizzazioni AI Granulari**: Eliminato il flag globale `viewer_ai_enabled` e introdotto il permesso `ai_enabled` specifico per ciascun operatore. Gli endpoint di analisi dell'Intelligenza Artificiale ora verificano questo permesso decodificandolo direttamente dal payload del JWT dell'utente loggato.
  - **RetrocompatibilitÃ  Client**: Mantenuto il supporto per l'autenticazione tramite il vecchio header `X-Admin-Password` all'interno della dependency FastAPI `verify_auth`, garantendo la continuitÃ  operativa dei moduli compilazione legacy dei client non ancora aggiornati.
  - **Registro Accessi su File**: Conservata la persistenza dei log di connessione per gli operatori in sola lettura (`viewer_logs.json` gestito localmente tramite `auth_manager.py`) per mantenere lo storico del server intatto.

## [2.16.17] - 2026-05-28


### Modificato
- **Nuovo Logo / Avatar Bradipo HD**:
  - Sostituito il precedente logo a bassa risoluzione `logo_bradipo.png` con la nuova risorsa premium ad alta definizione `avatar_bradipo_hd..png` (a doppia estensione) caricata su Git.
  - Aggiornati i riferimenti in tutta l'applicazione, inclusa la schermata di login, l'header principale del dashboard e l'animazione di caricamento IA a puzzle.

## [2.16.16] - 2026-05-28

### Modificato
- **Sfondo Watermark Bradipo HD post-login**:
  - Sostituito il precedente sfondo watermark `light_neural_bg.jpg` con la nuova risorsa premium `bradipo_hd_BG.png` ad alta definizione.
  - Regolata l'opacitÃ  dello sfondo in overlay all'**8%** (`0.08`) per un watermark elegante e discreto che garantisce la perfetta leggibilitÃ  dei testi e delle schede informative in tutto il portale amministrativo.

## [2.16.15] - 2026-05-28

### Corretto
- **VisibilitÃ  Watermark "Light Neural" post-login**:
  - Risolto il problema per cui l'immagine di sfondo a rete neurale (`light_neural_bg.jpg`) non era visibile sulle schede post-login.
  - La causa era il posizionamento del watermark *sotto* le pagine nel `Stack` di `main.dart`: gli sfondi solidi delle singole pagine coprivano completamente il watermark.
  - Spostato il watermark posizionandolo *sopra* le pagine (in fondo all'elenco dei figli dello `Stack`), rendendolo visibile come overlay con un'opacitÃ  ottimale del **12%** (`0.12`). Grazie ad `IgnorePointer`, il tocco e l'interazione con gli elementi sottostanti non vengono ostacolati.

## [2.16.14] - 2026-05-28

### Modificato
- **Flusso di Modifica ed Edit UX (Dettaglio Valutazione)**:
  - Modificato il pulsante d'azione di salvataggio in **"Salva ed esci"** (precedentemente "Salva modifiche").
  - Ottimizzato il comportamento di salvataggio: ora al click su "Salva ed esci", una volta completato il salvataggio con successo sul backend, l'applicazione esce automaticamente dalla modalitÃ  di edit (`_isEditMode = false`), portando la UI di nuovo in stato di sola lettura protetta.

## [2.16.13] - 2026-05-28

### Corretto
- **Salvataggio Dati Socio-Demografici nel Dettaglio Valutazione**:
  - Risolto il problema per cui le modifiche ai dati di "Informatore 1", "Informatore 2" e "Condizioni / Diagnosi" non venivano persistite dopo il salvataggio in modalitÃ  Edit.
  - Le mappe secondarie (`inf1`, `inf2`, `condizioni`, `persona`) venivano copiate ed eseguito il cast con `Map.from()` per sicurezza in ambiente Flutter Web, ma le modifiche dell'utente non venivano poi riscritte indietro nella mappa di stato globale `_editableDemographics`.
  - Implementata la riscrittura esplicita dei dizionari modificati all'interno degli eventi `onChanged` dei rispettivi moduli di input della UI, garantendo il corretto salvataggio e allineamento dati con il backend.

## [2.16.12] - 2026-05-28

### Corretto
- **Gestione Dati Socio-Demografici nel Dettaglio Valutazione**:
  - Risolto l'errore a runtime (`TypeError: Instance of 'minified:it<dynamic, dynamic>': type 'minified:it<dynamic, dynamic>' is not a subtype of type 'Map<String, dynamic>'`) visualizzato come schermata grigia all'accesso del dettaglio di una valutazione (es. scala POS).
  - Il crash era causato dai casting diretti con l'operatore `as Map<String, dynamic>?` applicati alle sotto-mappe (`persona`, `informatore1`, `informatore2`, `condizioni`) della struttura `demographics` all'interno di `_buildDemographicsCard()` in `evaluation_detail_screen.dart`. In ambiente Flutter Web, le sotto-mappe decodificate sono istanze di `Map<dynamic, dynamic>` e non consentono il cast diretto.
  - Implementata la conversione sicura tramite `Map<String, dynamic>.from(...)` e controlli di tipo `is Map` sia per i campi di rendering in `evaluation_detail_screen.dart` sia per la deserializzazione dei metadati nel modello `AggregatedEvaluation` in `evaluation_model.dart`, garantendo robustezza e compatibilitÃ  totale.

## [2.16.9] - 2026-05-28

### Aggiunto
- **Integrazione Dati SIS nell'Analisi IA (Gemini)**:
  - Esteso il servizio di generazione report IA (`GeminiService`) ed il modello di visualizzazione dei domini per includere i dati clinici e psicometrici completi della scala **SIS (Supports Intensity Scale)** nel contesto inviato all'IA.
  - Vengono ora forniti a Gemini: Punteggi Standard e Percentili per le 6 Sottoscale (Domini A-F), la Somma dei Punteggi Standard, l'Indice SIS Globale e la relativa Classificazione dell'IntensitÃ  dei Supporti (Fascia di bisogno), le Top 4 prioritÃ  di tutela individuate nella Sezione 2, e lo stato dettagliato degli Alert Medici (Sezione 3A) e Alert Comportamentali (Sezione 3B).
  - Questo allineamento permette all'IA di formulare valutazioni evolutive e cliniche premium integrando pienamente la SIS alle scale POS e San MartÃ­n.

## [2.16.8] - 2026-05-28

### Corretto
- **Comparazione Multidimensionale (Dashboard Admin)**:
  - Risolto il bug per cui in presenza di 3 scale compilate (es. POS, San MartÃ­n e SIS), la scala SIS veniva erroneamente assegnata come "posEval" sovrascrivendo la scala POS originale e restituendo l'errore "Nessun dominio in comune trovato tra le scale."
  - Esclusa in modo esplicito la scala SIS dal ciclo di assegnazione per la comparazione in `multidimensional_dashboard_screen.dart`, garantendo che il confronto e il relativo grafico a barre normalizzato (0-100%) avvengano **solo ed esclusivamente tra le scale POS e San MartÃ­n (SM)** come richiesto.

## [2.16.7] - 2026-05-28

### Ottimizzato
- **User Experience (UX) Sottoscale SIS**:
  - Risolto il problema del mancato riposizionamento dello scorrimento quando si cambia sottoscala (es. passando da "Vita Domestica" a "ComunitÃ ").
  - Integrata una `ValueKey` legata all'indice della sottoscala attiva (`_activeSubscaleIndex`) su `ListView.builder` sia nella Dashboard Admin che nel Client. Questo fa sÃ¬ che lo scroll state della lista venga ricreato pulito ad ogni cambio di tab, riposizionando l'utente **sempre all'inizio della lista (in testa alla pagina)** in modo nativo ed istantaneo.

## [2.16.6] - 2026-05-28

### Aggiunto
- **Stato di Validazione e Pulsante di Conferma per i Bisogni Eccezionali (Sezione 3)**:
  - Sviluppato un meccanismo di validazione attiva per il Tab 4 (Bisogni Eccezionali) sia nella Dashboard Admin che nel Client.
  - FinchÃ© l'utente non convalida esplicitamente le risposte, la sezione mostra la dicitura **"X/X Da verificare.." in arancione** con una specifica icona di stato di attenzione (sia nel menu laterale `NavigationRail` che nelle horizontal tabs).
  - Integrato un banner clinico premium in fondo al Tab 4 con il pulsante **"CONFERMA E VALIDA RISPOSTE"** in arancione. Cliccando sul pulsante, lo stato si convalida, il progresso diventa verde e visualizza **"Completato"** (o "29/29 Completato"), e compare un'icona di spunta verde.
  - Implementato lo sblocco dinamico: se l'utente decide di modificare una qualsiasi risposta della Sezione 3 dopo aver validato, il sistema reimposta automaticamente lo stato su "Da verificare.." finchÃ© non viene cliccato nuovamente il pulsante di conferma o sblocco manuale.

## [2.16.5] - 2026-05-28

### Corretto
- **Bug Rendering e IncompilabilitÃ  Sottoscala C nel Wizard SIS (Frontend Admin & Client)**:
  - Risolto il crash visualizzato come area grigia vuota dovuto a un `minified:TypeError` (cast non valido da `int` a `Map`) per gli item `C1`-`C9` della Sottoscala C.
  - Il bug era generato dalla collisione dei codici della Sezione 3 Comportamentale (SEZ3C) che nel database condividevano gli stessi identificativi `C1`...`C13`. La pre-inizializzazione a `0` (valore intero) per SEZ3C sovrascriveva le chiavi tridimensionali (che richiedono una `Map` `{"F": x, "D": y, "T": z}`) della Sottoscala C.
  - Implementata la mappatura automatica correttiva a livello di caricamento dati (`_loadData()`) che converte e isola i codici della sezione comportamentale SEZ3C nel formato `BC1`...`BC13`, eliminando all'origine la collisione e allineandosi al motore di calcolo del backend FastAPI.

## [2.16.4] - 2026-05-28

### Aggiunto
- **Esportazione PDF Premium per la Scala SIS (Supports Intensity Scale)**:
  - **Titolo Dinamico**: Sostituito il titolo hardcoded "POS ETEROVALUTATIVA" con il titolo formale "SUPPORTS INTENSITY SCALE (SIS)" per valutazioni SIS.
  - **Riepilogo Metriche Psicometriche**: Sviluppato un box di sintesi clinico premium con sfondo Teal dedicato che mostra in evidenza l'Indice SIS globale, il Percentile, la Somma dei Punteggi Standard e la Classificazione dell'IntensitÃ .
  - **Grafico a Barre Standardizzato**: Disegnato un grafico a barre ad hoc per i 6 domini principali (sottoscale A-F) tarato sul range dei punteggi standard (0-20) e arricchito con la linea della media normativa (= 10) per una lettura clinica immediata.
  - **Tabella Riepilogativa SIS**: Creata una tabella specifica per i 6 domini SIS con punteggi grezzi (somma F+D+T), punteggi standard e percentili.
  - **Sezioni Specialistiche Aggiuntive**: Aggiunta una pagina intera per i risultati della Sezione 2 (le prime 4 prioritÃ  di tutela con testi parlanti) e della Sezione 3 (medica/comportamentale con i relativi alert clinici e conteggi di risposte parziali ed estensive).
  - **Supporto Risposte Tridimensionali**: Corretta la visualizzazione delle risposte tridimensionali nel dettaglio risposte del PDF, mostrando ora il formato leggibile `Freq: X | Durata: Y | Tipo: Z (Tot: T)` per ciascun elemento.

## [2.16.3] - 2026-05-28

### Corretto
- **Gestione e validazione Bisogni Eccezionali (Sezione 3)**:
  - Pre-inizializzate le risposte a 0 sia per la Sezione 3 Medica (SEZ3M) che per la Sezione 3 Comportamentale (SEZ3C) per evitare che la sottoscala C risulti incompilata o ingrigita all'avvio.
  - Modificato il conteggio di completamento in `sis_wizard_screen.dart` in modo che la sezione 3 restituisca sempre 29/29 elementi completati se inizializzata.
- **Rendering Tridimensionale Sottoscale SIS C1-C9**:
  - Corretto il bug in `evaluation_detail_screen.dart` integrando la mappatura `_findSectionForQuestion` per determinare correttamente la tridimensionalitÃ  in base al codice sezione anzichÃ© solo al tipo di punteggio.
  - Aggiunto un fallback robusto per la conversione tridimensionale in presenza di dati storici incompleti.

## [2.16.2] - 2026-05-27

### Corretto
- **Bug visualizzazione ed elaborazione SIS (Supports Intensity Scale)**:
  - **ISSUE 1 (Scheda Analisi)**: Sostituito il titolo hardcoded "POS Eterovalutativo" con "Supports Intensity Scale (SIS)" associato a un gradiente Teal premium e accenti cromatici dedicati.
  - **ISSUE 2 (Legenda Domini)**: Sostituita la visualizzazione orizzontale a capo con un layout a colonne ordinato e puntato (2 colonne per POS, 3 colonne per SIS) ad alto contrasto visivo.
  - **ISSUE 3 (Evidenziamento Dettaglio Risposte)**: Risolto il mancato evidenziamento e il limite dei soli 3 punteggi (1, 2, 3) per gli item tridimensionali. Sviluppato un visualizzatore/selettore compatto e dinamico (Freq/Durata/Tipo) per ciascun item con scala 0-4 e codice colore.
  - **ISSUE 4 (Percentili e Fascia a zero/vuoti)**: Risolto il bug allineando il dizionario ritornato dal motore di calcolo backend `calcola_punteggi_sis` per esportare i campi standard `"punteggio_diretto"`, `"percentile_dominio"` e `"fascia"` attesi dai modelli Flutter.
  - **Riepilogo Tabellare (Intestazioni colonne tagliate)**: Aggiunte abbreviazioni grafiche concise per ciascuno dei domini e sezioni della scala SIS e aumentata la larghezza massima a 95px per evitare testi incompleti.

## [2.16.1] - 2026-05-27

### Corretto
- **Bug calcolo direct scores per risposte tridimensionali (SIS)**: Risolto il 500 errore (Internal Server Error) riscontrato accedendo alla pagina dell'analisi/storico dopo aver compilato e salvato una scala SIS. La funzione `compute_direct_scores` in `analytics.py` ora gestisce in modo sicuro sia punteggi numerici classici (POS, San MartÃ­n) che dizionari tridimensionali `{"F": x, "D": y, "T": z}` calcolando la somma corretta di F+D+T, evitando eccezioni di cast di tipo `TypeError`.

## [2.16.0] - 2026-05-27

### Aggiunto
- **Wizard Clinico Orchestratore SIS (Supports Intensity Scale)**: Sviluppato `sis_wizard_screen.dart` da zero sia per `frontend_admin` che per `frontend_client`.
  - **State Management**: Gestione dello stato integrata per mantenere l'intero set di risposte tridimensionali (`F`, `D`, `T`) e non perdere dati cambiando Tab o premendo "Indietro".
  - **Layout Adattivo e Bento Design**: Menu di navigazione a sinistra (`NavigationRail` su tablet/web >800px) e barra in basso / horizontal tabs scrollabili su smartphone.
  - **Sub-Navigatore Orizzontale per Sottoscale**: Menu secondario (horizontal `TabBar`) per scorrere rapidamente tra le Sottoscale A-F riducendo il carico cognitivo dell'operatore.
  - **Integrazione Dati Intake**: Form di configurazione per date, operatori, e il set completo di informatori e condizioni socio-demografiche del soggetto.
  - **Estrazione e Drag & Drop Ranking**: Integrazione di `SisRankingWidget` nello step di riepilogo per ordinare interattivamente le prime 4 prioritÃ  di tutela legale, e di `SisMedicalList` per la compilazione dei bisogni eccezionali con calcolo real-time degli alert di soglia.
- **Sincronizzazione Versioni**: Incrementata la versione globale della suite a `2.16.0` (backend API, app_version.dart, admin pubspec.yaml, client pubspec.yaml).

## [2.15.2] - 2026-05-27

### Aggiunto
- **Gestione Globale Hotkeys via HardwareKeyboard**: Risolto il problema del focus della tastiera nel Wizard di compilazione (sia nell'Admin che nel Client). Ora le scorciatoie sequenziali tridimensionali (digitando ad esempio `123` per Frequenza=1, Durata=2, Tipo=3 e premendo `Enter` per avanzare) rimangono attive ed estremamente reattive in qualunque situazione di navigazione, anche dopo aver cliccato con il mouse sulle opzioni o sullo sfondo. La gestione controlla inoltre lo stato del navigatore (`ModalRoute.isCurrent`) per disattivarsi automaticamente quando compaiono dialog o popup sovrapposti.
- **Allineamento Versioni**: Incrementata la versione globale della suite a `2.15.2` (backend, app_version.dart, admin pubspec.yaml) e della versione del client a `2.7.4`.

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
  - **ValiditÃ  dei Dati**: La navigazione tra le domande richiede obbligatoriamente il completamento di tutte e tre le dimensioni di risposta prima di poter cliccare su "Avanti" o salvare.
  - **Test Suite**: Realizzata la suite `test_sis.py` per validare asincronamente tutti i test del backend superando 10/10 test con successo.
- **Aggiornamento Versione**: Incrementata la versione globale della suite a `2.15.0` in `app_version.dart`, `pubspec.yaml` (admin) e `main.py` (FastAPI backend).

## [2.14.3] - 2026-05-26

### Ottimizzato
- **Razionalizzazione Testi Storico IA**: Spostata la descrizione estesa dell'iniezione del contesto nello storico direttamente all'interno del banner verde premium di informazioni (tooltip) e rimossa la precedente etichetta descrittiva duplicata per eliminare ridondanze visive e rendere il layout piÃ¹ compatto ed elegante.

## [2.14.2] - 2026-05-26

### Aggiunto
- **Miglioramento dell'UsabilitÃ  dello Storico Report IA**: Inserito un banner informativo premium sopra la checklist dello storico per spiegare chiaramente lo scopo dei checkbox di selezione ("Seleziona per utilizzare questo report nella nuova analisi IA").
- **Ottimizzazione Schermata Impostazioni**: Modificata l'apertura di default dei pannelli di espansione ("Gestione Accessi e Sicurezza" e "Configurazione AI (Gemini)"), ora impostati come chiusi all'avvio della pagina per una consultazione piÃ¹ ordinata e pulita.

## [2.14.1] - 2026-05-26

### Corretto
- Risolto un errore di compilazione sul client Flutter admin in `multidimensional_dashboard_screen.dart` correlato alla nullabilitÃ  dell'attributo `sesso` dell'utente (`String?`), che impediva il corretto completamento della build Docker nel container di produzione.

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
  - Integrata in `GeminiService` la capacitÃ  di ricevere ed iniettare lo storico selezionato delle relazioni precedenti all'interno del prompt di Gemini, per un'analisi evolutiva longitudinale.
  - Aggiunta l'opzione grafica "Salva in Storico" a fianco dei comandi del report generato con indicatori reattivi di caricamento.
  - Inserito il pannello premium *"Storico Relazioni IA e Iniezione Contesto"* con checklist di selezione, pulsante per leggere al volo qualsiasi relazione precedente nel `DocumentReaderScreen` e comandi di eliminazione sicura con modal di conferma.
  - Eseguita una bonifica meticolosa e sistematica del vocabolario, sostituendo i riferimenti clinici con termini inclusivi di supporto ed educativi (es. `"andamento educativo e di supporto nel tempo"` al posto di `"evoluzione clinico-funzionale"`).
- **Allineamento Versioni**: Incrementata la versione globale della suite a `2.12.0` in `app_version.dart` e `pubspec.yaml` (admin).

## [2.11.0] - 2026-05-26

### Aggiunto
- **Document Reader Clinico Virtuale (Fogli A4)**:
  - Sviluppata la nuova schermata `DocumentReaderScreen` per la visualizzazione immersiva delle relazioni AI.
  - Impaginazione ad alta fedeltÃ  con fogli A4 virtuali, testata clinica personalizzata, margini reali e piÃ¨ di pagina con numerazione automatica ("Pagina X di Y").
  - Supporto alle interruzioni di pagina fisiche tramite il tag markdown standard `---`.
  - Controlli premium nella toolbar: regolazione della dimensione del font, zoom dei fogli, copia testo rapida ed esportazione PDF integrata.
  - Switch interattivo tra tre temi colore: *Clinical* (bianco/slate), *Warm* (avorio/crema) e *Dark* (antracite/scuro).
  - Collegamento diretto in `MultidimensionalDashboardScreen` tramite pulsante "ModalitÃ  Lettura" e pulsante rapido "Schermo Intero / Lettura A4" all'interno della Card di sintesi clinica.
- **Allineamento Versioni**: Incrementata la versione globale della suite a `2.11.0` in `app_version.dart` e `pubspec.yaml` (admin).

## [2.7.2] - 2026-05-23

### Modificato
- **Ottimizzazione Layout "Analisi Utente"**:
  - Equalizzate dinamicamente le altezze dei box "POS Eterovalutativo" e "San MartÃ­n" sopra i grafici utilizzando flexbox con allineamento stretched (`crossAxisAlignment: CrossAxisAlignment.stretch`) nella visualizzazione desktop, garantendo una perfetta simmetria visiva e l'assenza di spazi vuoti asimmetrici.
  - Introdotto un sotto-box interno dedicato alla **Legenda dei Domini** all'interno del card POS, con scorrimento verticale personalizzato (`Scrollbar` + `SingleChildScrollView`), mostrando il mapping dinamico `[Sigla] = [Nome Esteso]: [Valore]` basato sui punteggi del paziente per massimizzare la leggibilitÃ  ed evitare di occupare spazio extra.
  - Aggiornate le etichette delle colonne in accordo con la terminologia clinico-educativa inclusiva: POS rinominato in `"POS Eterovalutativo"` con sottotitolo `"Valutazione degli esiti personali e della QQdV percepita"`, e San MartÃ­n con sottotitolo `"Valutazione osservativa della qualitÃ  di vita"`.
- **Evoluzione Data Visualization (Radar Chart)**:
  - Esteso il grafico radar (`RadarChart` di `fl_chart`) per la scala San MartÃ­n incorporando due dataset di riferimento stabili:
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
  - Implementata la possibilitÃ  di eliminare definitivamente una specifica valutazione storica direttamente dalla schermata di dettaglio ([evaluation_detail_screen.dart](file:///home/gianvito/progetti/AutAnalysis/frontend_admin/lib/screens/evaluation_detail_screen.dart)).
  - **Integrazione RBAC & Safety UX**: L'opzione di cancellazione non viene renderizzata nel DOM per il ruolo Viewer. Per l'utente Admin, il pulsante (icona a forma di "X" circolare) compare ed Ã¨ cliccabile solo se la modalitÃ  di modifica ("Edit Mode") Ã¨ attiva.
  - **Safety UX (Modal di Conferma)**: Introdotto un dialog premium di conferma eliminazione con avviso di irreversibilitÃ  dell'operazione.
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
  - **Impostazioni di Sistema (`settings_screen.dart`)**: Disabilitati in modalitÃ  Viewer i cursori per la regolazione dei parametri di validitÃ  delle scale, i pulsanti per l'esportazione e l'importazione del database, la chiave API e il modello di Gemini.
  - **Anagrafica Utenti (`anagrafica_screen.dart`)**: Disabilitati i comandi di creazione di nuovi utenti e le azioni di modifica ed eliminazione sia all'interno delle schede individuali che nell'elenco tabellare.
  - **Protocolli di Supporto (`protocols_screen.dart`)**: Disabilitati e colorati in tonalitÃ  grigia premium i comandi per rinominare ed eliminare le scale di valutazione.
  - **Dettaglio Valutazione (`evaluation_detail_screen.dart`)**: Nascosti completamente i pulsanti "Edit" e "Salva modifiche" nell'AppBar per l'utente Viewer, impedendo qualsiasi modifica retroattiva alle valutazioni salvate.
  - **Selezione Valutazione (`selection_screen.dart`)**: Disabilitato il pulsante per avviare una nuova valutazione, con aggiornamento dinamico della label in "Sola Lettura - Compilazione Disabilitata".
  - **Wizard di Compilazione (`wizard_screen.dart`)**: Inserita una guardia logica di controllo nel metodo di salvataggio `_saveEvaluation()` per intercettare e respingere a livello client qualsiasi tentativo anomalo di sottomissione dati da parte del Viewer.
- **Allineamento Versioni**: Incrementata la versione dell'intera suite a `2.7.0` in `app_version.dart`, in entrambi i file `pubspec.yaml` (admin e client), ed esportata nei metadati dei backup del database in `routes.py` e `main.py`.

## [2.6.2] - 2026-05-22

### Aggiunto
- **Gestione Dinamica e Reattiva della ValiditÃ  delle Scale**: Implementato un sistema client-side reattivo completo per regolare i parametri di scadenza delle scale di valutazione (POS e San MartÃ­n).
  - Aggiunta una sezione "Parametri di ValiditÃ  Scale" nelle Impostazioni con tre Slider per regolare:
    - Mesi di validitÃ  per la scala POS (1-24 mesi).
    - Mesi di validitÃ  per la scala San MartÃ­n (1-24 mesi).
    - Giorni di preavviso per l'alert di scadenza (0-60 giorni).
  - Persistenza locale dei parametri tramite `shared_preferences`.
  - Propagazione globale e in tempo reale dello stato reattivo tramite il pacchetto `provider` (`SettingsNotifier`).
  - Aggiornamento dinamico istantaneo degli indicatori di stato ("POS", "SM") nella lista utenti (`anagrafica_screen.dart`), ricalcolati in base alle nuove soglie tramite la classe helper `ValidityCalculator`.
  - Tooltip informativi arricchiti con il dettaglio dei mesi di validitÃ  attuali per una trasparenza ottimale.
- **Miglioramento dell'UsabilitÃ **: Avvolta la schermata Impostazioni in un contenitore a scorrimento verticale (`SingleChildScrollView`) per prevenire overflow dell'interfaccia su schermi con risoluzione verticale ridotta.

### Modificato
- **Allineamento Versioni**: Incrementata la versione dell'intera suite a `2.6.2` in `app_version.dart`, in entrambi i file `pubspec.yaml` (admin e client), ed esportata nei metadati dei backup del database in `routes.py`.

## [2.6.1] - 2026-05-22

### Aggiunto
- **Tooltip Dettagliato Card KPI Dashboard**: Aggiunto un tooltip interattivo e animato con stile premium (sfondo scuro semi-trasparente, bordi arrotondati, testo formattato) alla card "DA VALUTARE / SCADUTI" sulla Dashboard per visualizzare l'esatto conteggio delle scale mancanti/scadute separate per tipologia (POS e San MartÃ­n). Supporta sia l'hover su desktop che il tap su dispositivi mobili/tablet.

### Modificato
- **Logica Card KPI Dashboard (Conteggio Individuale Scale)**: Modificata la logica di calcolo delle card KPI "Valutazioni Attive" e "Da Valutare / Scaduti" nella Dashboard. Ora i contatori mostrano la somma totale dei singoli test/scale (POS + San MartÃ­n) validi o mancanti anzichÃ© il conteggio univoco degli utenti, calcolando la percentuale di copertura rispetto al massimo teorico delle scale somministrabili (2 per utente).
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
- **UniformitÃ  e TracciabilitÃ **: Allineata la versione del frontend (`kFrontendVersion`) e l'esportazione dei metadata del backend alla release `2.6.0`.

## [2.5.1] - 2026-05-22

### Risolto
- **Normalizzazione Scala San MartÃ­n**: Corretto il calcolo del valore massimo teorico per i domini della Scala San MartÃ­n nella modalitÃ  "Compara". Dato che le risposte della San MartÃ­n si basano su una scala Likert da 1 a 4 (mentre POS si basa su 1 a 3), il denominatore della percentuale Ã¨ stato corretto a `numero domande Ã 4` (anzichÃ© `Ã 3`). Questo evita che le barre arancioni "sfondino" il limite del 100% (arrivando al 125%+).
- **LeggibilitÃ  del Grafico di Comparazione**: Sostituite le sigle dei domini (es. "SP", "RI") con i loro nomi completi (es. "Sviluppo Personale", "Relazioni Interpersonali") sull'asse X del grafico comparativo. Le etichette lunghe sono state ruotate a -0.4 radianti per prevenire sovrapposizioni e migliorare il design visivo.
- **Footer e Tooltip**: Aggiornato il testo esplicativo nel footer del grafico di comparazione e i dettagli del tooltip per riflettere accuratamente il calcolo del massimo teorico per entrambe le scale.
- **Pannelli di Dettaglio individuali**: Estesa la parametrizzazione del calcolo del massimo teorico anche ai grafici a barre dei singoli domini nel caso la scala San MartÃ­n debba essere visualizzata tramite barre in assenza di analisi psicometrica.

## [2.5.0] - 2026-05-22

### Aggiunto
- **ModalitÃ  Comparazione ("Compara")**: Introdotto un interruttore (Toggle) "Compara" nella scheda Overview dell'analisi utente. Quando abilitato, collassa le due schede POS e San MartÃ­n in un unico grafico comparativo unificato.
- **Logica di Normalizzazione (0-100%)**: Implementata la normalizzazione automatica dei punteggi assoluti di ciascun dominio in valori percentuali rispetto al punteggio massimo teorico (numero di domande Ã 3) per consentire un confronto omogeneo tra le scale.
- **Intersezione dei Domini**: Il grafico comparativo mostra esclusivamente i domini comuni (es. SP, BE, BF, BM, IS, RI) presenti in entrambe le scale.
- **Grafico a barre raggruppate (Grouped Bar Chart)**: Realizzato un grafico a barre raggruppate utilizzando `fl_chart`, con barre affiancate per ciascun dominio comune (Blu per POS, Arancione per San MartÃ­n), legenda e tooltip interattivo che mostra sia il valore assoluto originale che la percentuale normalizzata: `"$ValoreAssoluto / $PunteggioMassimo ($Percentuale%)"`.
- **Transizioni animate**: Integrato un `AnimatedSwitcher` combinato con `FadeTransition` e `SlideTransition` per garantire un'animazione fluida e premium nel passaggio dalla visualizzazione standard a quella comparativa.

## [2.4.1] - 2026-05-22

### Risolto
- **PDF - Rimozione Orari di Apertura**: Rimosso l'orario di servizio della Fondazione ("Orari: lun-ven dalle 9.00 alle 17.00") dalla sezione in alto a destra di tutte le intestazioni dei PDF generati.
- **PDF - Aggiornamento Logo Ufficiale**: Sostituito il vecchio logo ad alto contrasto/scuro nell'angolo in alto a sinistra di tutti i PDF generati con il nuovo logo ufficiale su sfondo bianco fornito dall'utente.

## [2.4.0] - 2026-05-22

### Risolto
- **Rilevamento Scala San MartÃ­n (Accenti/Etichette)**: Risolto definitivamente il bug in cui la colonna San MartÃ­n continuava a mostrare "POS" e a nascondere il grafo radar. La causa era il carattere accentato "Ã­" (i acuta) nel nome "Scala San MartÃ­n", che ora viene normalizzato in "i" durante la decodifica.
- **Icone presenza scale (San MartÃ­n grigia)**: Risolto il bug per cui le icone di compilazione della scala San MartÃ­n restavano grigie nelle schede/badge degli utenti pur essendo presenti nel database. Il backend ora arricchisce correttamente la mappa delle scale supportando sia gli ID testuali che gli ID MongoDB (ObjectId), e normalizza gli accenti.
- **Titolo PDF San MartÃ­n**: Aggiornato il titolo della scala San MartÃ­n nei PDF esportati da "Report Valutativo" a "SCALA SAN MARTÃN", uniformandolo con il corrispettivo "POS ETEROVALUTATIVA".
- **Safety Net Storico**: Aggiunto un ordinamento esplicito lato client nella Dashboard Multidimensionale per garantire che venga prelevata la valutazione piÃ¹ recente in presenza di duplicati o cronologia multipla.

## [2.3.5] - 2026-05-22

### Risolto
- **Dashboard - Distribuzione Documentazione**: La percentuale di completamento per scala veniva ricevuta dal backend con un denominatore errato (somma di tutte le valutazioni anzichÃ© numero di pazienti). Il frontend ora calcola la percentuale **lato client** da `count / totalPatients Ã 100`, garantendo che POS 18/18 â 100% e San MartÃ­n 14/18 â 77.8% indipendentemente dal valore restituito dal backend.

## [2.3.4] - 2026-05-22

### Risolto
- **Analisi Utente - Etichetta San MartÃ­n**: La colonna San MartÃ­n mostrava erroneamente "POS" come titolo. La funzione di rilevamento `_isSanMartinScale` ora controlla sia l'ID che il nome della scala (con normalizzazione accenti/spazi/trattini).
- **Analisi Utente - Grafici sovrapposti**: Il grafico a barre POS aveva `maxY` hardcoded a 20, causando barre schiaccianti per punteggi superiori. Ora il valore massimo dell'asse Y Ã¨ calcolato dinamicamente dai dati reali (+10% di margine).
- **Analisi Utente - Radar Chart San MartÃ­n mancante**: PoichÃ© il rilevamento San MartÃ­n falliva, il radar chart non veniva mai renderizzato. Con la correzione dell'identificazione, il grafo radar appare correttamente nella colonna San MartÃ­n.

## [2.3.3] - 2026-05-22

### Risolto
- **Allineamento versione UI**: Aggiornata la costante hardcoded `kFrontendVersion` e i file di configurazione (`routes.py`, `pubspec.yaml`) per allineare la versione mostrata in basso a sinistra della dashboard e nei dump del database alla release corretta `2.3.3`.

## [2.3.2] - 2026-05-22

### Risolto
- **Build Flutter Web**: Corretti alcuni errori di tipizzazione di Dart (es. assegnazioni scorrette di tipi di dato ai Map del body per la rotta API, uso di un getter errato per `DomainScore`) che causavano il fallimento silente del compilatore `dart2js` con `exit code 1` durante il deploy su Docker.

## [2.3.1] - 2026-05-22

### Modificato/Risolto
- **Dashboard Multidimensionale**: Corretto il rendering dei grafici a barre in modo che il punteggio effettivo si sovrapponga correttamente alla barra del punteggio massimo, risolvendo l'invisibilitÃ  delle barre.
- **Dashboard Principale**: Risolto il calcolo della percentuale di completamento dei documenti per contare il numero di "pazienti unici" invece del totale delle compilazioni storiche.
- **Docker**: Abbassato il livello di ottimizzazione della build di Flutter Web da `-O 4` a `-O 2` per prevenire errori "Out of Memory" (`exit code 1`) durante il deploy tramite Docker Desktop.

## [2.3.0] - 2026-05-22

### Aggiunto
- ModalitÃ  "Edit" nella schermata di dettaglio valutazione, per consentire la modifica controllata di metadata (Operatore, Intervistato/a) e risposte.
- Carta intestata formattata (logo + dati fondazione) per tutti i PDF generati (POS e San MartÃ­n).
- Titolo dinamico per i PDF ("POS ETEROVALUTATIVA" per la scala POS).

### Modificato
- Refactoring completo della `MultidimensionalDashboardScreen` in stile "Bento Grid" per migliorare l'UX.
- Normalizzazione degli identificatori (rimozione accenti) nel backend per la risoluzione corretta dell'ultima compilazione San MartÃ­n.
- Modifica al servizio Gemini per utilizzare system prompt personalizzati sull'expertise ASD.

## [2.2.0] - Precedenti iterazioni
- Creazione dei frontend Flutter (Admin e Client) e backend FastAPI.
- Gestione base delle scale San MartÃ­n e POS.
- Setup iniziale del sistema di valutazione multidimensionale.
## [2.18.7] - 2026-05-30
### Fixed
- Backend 502 Bad Gateway (AuditLog missing models)
- PWA Support added (manifest and metatags)

