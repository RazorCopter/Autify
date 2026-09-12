# REMEDIATION — Autify

Piano riscritto integralmente il 12 settembre 2026 sulla base dell’assessment del commit `cad2ca2714796d3199152e1d5a49c143df9d8fbc`. Il riferimento centrale è [ARCHITECTURE_MAP.md](ARCHITECTURE_MAP.md).

**Stato: nessun fix applicato da questo assessment.** Le modifiche richieste sono documentali; tutti gli interventi sotto sono aperti. Questo piano sostituisce le precedenti checklist e i loro indicatori di completamento. La storia rimane in Git.

## Criteri e limiti

- **P0:** chiudere prima di un’ulteriore esposizione dell’app agli utenti: autorizzazioni e accesso ai segreti.
- **P1:** correggere prima di considerare affidabili ripristino, indicatori, calcoli e relazioni; oppure prima del prossimo rilascio, secondo l’area.
- **P2:** robustezza, osservabilità e manutenibilità dopo i blocchi precedenti.
- “Riprodotto” indica test locali su codice dello snapshot e dati sintetici. Le collection simulate non certificano semantica/transazioni di MongoDB reale.
- Nessuna scansione della produzione, uso di credenziali reali, chiamata Gemini, build Docker/Flutter o validazione normativa completa delle scale. Nessuna attribuzione CVE o audit aggiornato delle dipendenze.
- I numeri di riga seguenti sono quelli dello snapshot e servono a trovare funzioni e blocchi; dopo i fix usare anche i nomi simbolici.

## Registro interventi

| ID | Priorità | Intervento | Stato |
| --- | --- | --- | --- |
| [SEC-01](#sec-01) | P0 | API client senza autenticazione | Aperto |
| [SEC-02](#sec-02) | P0 | Backup completo accessibile al viewer | Aperto |
| [SEC-03](#sec-03) | P1 | Revoca sessioni e variazioni dei privilegi non effettive fino a scadenza JWT | Aperto |
| [SEC-04](#sec-04) | P1 | Bootstrap e gestione delle credenziali | Aperto |
| [DATA-01](#data-01) | P1 | Ripristino distruttivo, parziale e non fedele ai tipi originali | Aperto |
| [DATA-02](#data-02) | P1 | Identità modificabili e storico non ancorato alla versione della scala | Aperto |
| [FUN-01](#fun-01) | P1 | Filtri semantici basati su date non mantenute e ricerca sovrascritta | Aperto |
| [FUN-02](#fun-02) | P1 | Tre definizioni incompatibili di validità e scadenza | Aperto |
| [SCORE-01](#score-01) | P1 | Validazione insufficiente e indici calcolati su risposte incomplete | Aperto |
| [SCORE-02](#score-02) | P1 | Provenienza e coerenza delle tabelle San Martín da validare | Aperto |
| [AI-01](#ai-01) | P1 | Storico IA associato agli indici più recenti e provenienza salvata inesatta | Aperto |
| [AI-02](#ai-02) | P1 | Chiave Gemini nel browser e policy IA incoerente | Aperto |
| [OPS-01](#ops-01) | P1 | Versione e distribuzione degli asset non affidabili | Aperto |
| [QA-01](#qa-01) | P1 | Suite test non riproducibile e copertura delle invarianti insufficiente | Aperto |
| [PERF-01](#perf-01) | P1 | Indicatori troncati e cache non invalidata su tutte le mutazioni | Aperto |
| [OBS-01](#obs-01) | P2 | Audit incompleto ed errori convertiti in dati apparentemente validi | Aperto |
| [DATA-03](#data-03) | P2 | Import scala perde le sottodomande composite | Aperto |
| [UI-01](#ui-01) | P2 | Operazioni asincrone senza gestione robusta del ciclo di vita | Aperto |
| [ARCH-01](#arch-01) | P2 | Concentrazione delle responsabilità e concorrenza PDF da verificare | Aperto |
| [SEC-05](#sec-05) | P2 | Contratto password incompatibile con bcrypt risolto dall’ambiente | Aperto |

<a id="sec-01"></a>
## SEC-01 — API client senza autenticazione

**Priorità:** P0. **Evidenza:** Riprodotto ASGI locale. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:43 (client_router), get_client_patients:1988, create_evaluation:1938; frontend_admin/lib/services/api_service.dart:674.

**Problema e impatto.** Il router client non ha dependency auth. GET /api/client/patients restituisce le anagrafiche senza JWT; POST /api/client/evaluations accetta scritture anonime. Il nome operatore arriva dal payload e viene registrato nell’audit. I controlli viewer nella UI non proteggono questi endpoint.

**Verifica.** Con collection sintetiche: GET anonima 200; POST anonima con scala inesistente e punteggio fuori dominio 201, con operatore arbitrario nell’audit. Non è stata verificata l’esposizione della distribuzione reale dietro eventuali controlli esterni.

**Intervento.** Proteggere tutti gli endpoint client con autenticazione; richiedere esplicitamente un ruolo autorizzato alle scritture. Aggiungere Bearer anche alle chiamate client Flutter, ricavare l’autore dal contesto autenticato. Se è necessario un percorso pubblico, progettarlo separatamente con autorizzazione limitata alla singola compilazione.

**Criterio di chiusura.** Anonimo riceve 401; viewer riceve 403 sulle scritture; admin può completare entrambi i wizard; audit attribuito al JWT. Eseguire test per ogni rotta client, non solo sul router admin.

<a id="sec-02"></a>
## SEC-02 — Backup completo accessibile al viewer

**Priorità:** P0. **Evidenza:** Riprodotto ASGI locale. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:31 (verify_auth), export_database:1727, _collect_collection:1717.

**Problema e impatto.** La protezione del router consente GET ai viewer. export-db non richiede admin e include users con hashed_password e settings con gemini_api_key. La mascheratura applicata a GET /settings non si applica al backup.

**Verifica.** JWT viewer sintetico: GET /api/admin/export-db → 200; hash e chiave sintetici presenti nel JSON. È un’esposizione di dati e segreti all’interno del ruolo di sola lettura, anche quando l’IA è disabilitata.

**Intervento.** Richiedere admin esplicitamente per export/import e applicare una matrice di privilegi per operazione. Conservare la completezza del backup amministrativo; separare eventuali esportazioni consultabili dai viewer. Verificare se backup siano stati scaricati da ruoli non previsti e ruotare le credenziali effettivamente esposte.

**Criterio di chiusura.** GET export-db restituisce 401 anonimo, 403 viewer e backup completo admin. Testare che un viewer ai_enabled=false non recuperi chiavi tramite endpoint alternativi.

<a id="sec-03"></a>
## SEC-03 — Revoca sessioni e variazioni dei privilegi non effettive fino a scadenza JWT

**Priorità:** P1. **Evidenza:** Codice + verifica locale. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/auth.py:44,59,81; backend/app/routes.py:update_user:268, delete_user:292.

**Problema e impatto.** verify_auth verifica firma e scadenza ma non consulta l’operatore corrente o una versione della sessione. Eliminazione account, cambio password, downgrade ruolo o disabilitazione IA non invalidano i token già emessi, validi fino a otto ore.

**Verifica.** Un token firmato con il segreto sintetico, relativo a un account inesistente nelle collection di test, ottiene 200 su GET /users. Non è una dimostrazione di falsificazione del JWT: il test usa intenzionalmente la chiave locale.

**Intervento.** Verificare stato e ruolo correnti dell’operatore oppure adottare session_version/token_version confrontata lato server e incrementata sugli eventi rilevanti. Definire logout/revoca e durata in base alle esigenze operative.

**Criterio di chiusura.** Un token valido prima di eliminazione, cambio password o downgrade deve perdere immediatamente i privilegi precedenti; coprire anche ai_enabled.

<a id="sec-04"></a>
## SEC-04 — Bootstrap e gestione delle credenziali

**Priorità:** P1. **Evidenza:** Codice; validità delle credenziali esterne non verificata. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/auth.py:104; backend/test_audit.py; backend/app/models.py:8,31.

**Problema e impatto.** Su collection users vuota il bootstrap crea un account con password predefinita nota, senza obbligo server di sostituzione. Uno script diagnostico versionato contiene inoltre credenziali in una URI MongoDB. Non si assume che queste siano valide o utilizzate in produzione.

**Verifica.** Il repository è pubblico nello snapshot. Nessun tentativo di uso delle credenziali è stato eseguito e i loro valori non sono riprodotti in questo documento.

**Intervento.** Bootstrap con segreto temporaneo fornito dall’ambiente o procedura iniziale controllata, cambio obbligatorio prima dell’uso e nessun segreto nei log. Rimuovere la URI dallo script, usare configurazione esterna e verificare/ruotare eventuali credenziali reali esposte, inclusa la storia Git pertinente.

**Criterio di chiusura.** Avvio su DB vuoto senza account prevedibile; lo script usa solo configurazione esterna; verifica della rotazione documentata se le credenziali erano reali.

<a id="data-01"></a>
## DATA-01 — Ripristino distruttivo, parziale e non fedele ai tipi originali

**Priorità:** P1. **Evidenza:** Riprodotto ASGI locale con collection simulate. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:_collect_collection:1717, export_database:1727, import_database:1758.

**Problema e impatto.** Import valida solo forma superficiale e dimensione, poi esegue delete_many prima di insert_many. Le collection vuote vengono saltate. Export converte datetime in stringhe ed elimina _id; import non ripristina i tipi BSON né riconcilia riferimenti legacy. Un backup oltre 5 MiB può essere esportato ma non reimportato; Nginx non configura client_max_body_size.

**Verifica.** Collection non vuota + elenco vuoto: 200 ma dati vecchi conservati. Valore malformato: 500 dopo la cancellazione nella simulazione. Data ISO importata come str. Queste prove verificano ordine e trasformazioni del codice, non atomicità o transazioni di un MongoDB reale.

**Intervento.** Definire formato versionato e modalità esplicita restore/merge; validare integralmente tutte le collection, riferimenti e tipi prima di scrivere. Preparare staging e rollback/snapshot verificato; valutare transazioni solo su topologia MongoDB compatibile. Ripristinare anche gli elenchi vuoti, conservare/migrare gli identificativi necessari e allineare limiti proxy/API/export. Non eseguire cancellazioni su produzione come prova.

**Criterio di chiusura.** Round-trip su DB isolato con datetime, riferimenti legacy, collection vuote, backup grande e fallimento iniettato: nessuna perdita o stato intermedio pubblicato; restore ripetibile e verificabile.

<a id="data-02"></a>
## DATA-02 — Identità modificabili e storico non ancorato alla versione della scala

**Priorità:** P1. **Evidenza:** Codice + riproduzione parziale locale. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:update_patient:514, delete_patient:530, import_scale:796, update_scale:928, delete_scale:945; backend/app/models.py:141,191.

**Problema e impatto.** PUT anagrafica e scala accettano un id nel corpo diverso dal path. Eliminare un utente cancella le valutazioni ma lascia ai_analyses. Import/update scala sovrascrivono la definizione corrente; le valutazioni contengono solo id_scala e vengono ricalcolate con quella definizione, senza una versione immutabile. Eliminare una scala può lasciare valutazioni non interpretabili.

**Verifica.** PUT /patients/p1 con id=p2: 200, riferimenti delle valutazioni restano p1. DELETE utente: relazione IA sintetica rimane. La variazione retroattiva dei calcoli è dedotta dal percorso di lettura della scala corrente.

**Intervento.** Rendere gli ID immutabili e verificare corrispondenza path/body; definire cancellazione/archiviazione coerente e gestione dei riferimenti delle relazioni. Versionare le scale e collegare le valutazioni alla versione o snapshot usato; impedire cancellazioni incompatibili con lo storico. Migrare con un report degli orfani, non correggerli alla cieca.

**Criterio di chiusura.** ID divergente rifiutato; nessun orfano dopo le operazioni previste; un aggiornamento scala non cambia i risultati delle valutazioni storiche; riferimenti delle relazioni verificati.

<a id="fun-01"></a>
## FUN-01 — Filtri semantici basati su date non mantenute e ricerca sovrascritta

**Priorità:** P1. **Evidenza:** Riprodotto localmente + tracciamento delle scritture. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:get_patients:311, create_evaluation:1938, delete_evaluation:1900.

**Problema e impatto.** La query filtra ultimo_*_compilato nel documento anagrafico prima di leggere le valutazioni; tali date sono ricalcolate solo nella risposta e non vengono mantenute da create_evaluation. Un utente può quindi avere valutazioni e risultare mai valutato. Inoltre incompleti/scaduti/in_scadenza sovrascrivono query["$or"], cancellando la ricerca nome/cognome.

**Verifica.** Collection simulate: un utente con valutazione viene incluso in mai_valutati; ricerca combinata con incompleti non contiene più il predicato $regex. Il comportamento dipende anche da eventuali date preesistenti importate o risalvate dal frontend.

**Intervento.** Calcolare gli ultimi eventi in una pipeline prima di filtro/paginazione oppure mantenere un riepilogo persistente su tutte le mutazioni con backfill e invarianti verificabili. Comporre ricerca e filtro con $and; trattare la ricerca come testo, con escaping e limiti.

**Criterio di chiusura.** Fixtures oltre una pagina: total e risultati corretti per ogni filtro, combinazione ricerca/stato/filtro, creazione, modifica e cancellazione valutazione.

<a id="fun-02"></a>
## FUN-02 — Tre definizioni incompatibili di validità e scadenza

**Priorità:** P1. **Evidenza:** Confermato staticamente. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:317,338,1400,1500; frontend_admin/lib/models/app_settings.dart:9; services/validity_calculator.dart; services/api_service.dart:getPatients.

**Problema e impatto.** UI: default POS 6 mesi, San Martín 12, SIS 12, alert 20 giorni e mesi di calendario. Filtro API: POS 12, San Martín 12, SIS 36, alert 30 giorni e mesi da 30 giorni. Dashboard: POS/San Martín 180 giorni e SIS 365. La UI non invia i parametri validity; le sue preferenze sono locali al browser e non nel backup DB. La dashboard ragiona su tre scale, il filtro incompleti su sei.

**Verifica.** Le divergenze sono letterali nel codice. Non è stata scelta una nuova regola educativa al posto della struttura.

**Intervento.** Definire una policy condivisa e versionata per scale richieste, durata, alert, calendario e timezone. Persistenza server e stesso calcolo per dashboard, anagrafiche, filtri ed export; migrare esplicitamente le preferenze locali.

**Criterio di chiusura.** Stessa valutazione e stessa data di riferimento producono lo stesso stato in tutte le viste; casi fine mese, bisestili, soglia esatta, scale opzionali e configurazioni personalizzate.

<a id="score-01"></a>
## SCORE-01 — Validazione insufficiente e indici calcolati su risposte incomplete

**Priorità:** P1. **Evidenza:** Riprodotto localmente. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/models.py:123,129,141; backend/app/routes.py:create_evaluation:1938, update_evaluation:1078; backend/app/analytics.py:168,305,724,886.

**Problema e impatto.** SISItemResponse tipizzato esiste ma Answer usa Union[int, dict] non vincolata. Non vengono verificati appartenenza domanda/scala, unicità delle risposte, completezza, riferimenti e range specifici. Il motore SIS calcola punteggi anche per domini senza item; i motori diretto e SIS trattano diversamente dati fuori intervallo. San Martín può sommare solo i domini disponibili e produrre un indice globale.

**Verifica.** SIS con zero risposte: somma standard 27, indice 68 e zero item. F=99 per A1: aggregazione diretta 99, motore SIS 4. Una risposta con dati incongrui viene accettata dall’API nella prova SEC-01.

**Intervento.** Validazione server dipendente dalla versione della scala su creazione e modifica, con errori 422 chiari. Distinguere bozza/incompleta da completata; non pubblicare indici normativi finché mancano i requisiti. Condividere lo stesso calcolo tra API, UI e PDF, senza correzioni silenziose di input invalidi.

**Criterio di chiusura.** Casi vuoti, parziali, duplicati, codici ignoti, tipi errati e range estremi non generano indici validi; ogni scala ha fixtures complete e risultati coerenti fra export, dettaglio e IA.

<a id="score-02"></a>
## SCORE-02 — Provenienza e coerenza delle tabelle San Martín da validare

**Priorità:** P1. **Evidenza:** Anomalie strutturali confermate; correttezza normativa non certificata. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/analytics.py:10,252,264,305; backend/app/ScalaSanMartin.json; scale/Scala San Martin.json.

**Problema e impatto.** Le due copie San Martín contengono 95 domande: dominio IS con 11, altri domini con 12. Le matrici Python includono intervalli sovrapposti AU=13 e BE=19; il risultato dipende dall’ordine delle righe. La matrice Python prevale sulla tabella JSON e il fallback può scegliere un valore vicino quando manca quello esatto.

**Verifica.** Conteggio strutturale dei JSON e enumerazione degli intervalli Python. Non è stato stabilito quale valore o struttura sia corretta secondo il manuale: le anomalie non autorizzano a inventare la domanda o il punteggio mancante.

**Intervento.** Confrontare con l’edizione autorizzata del protocollo e con chi governa le scale; registrare provenienza/versione. Unificare la fonte dei valori, eliminare ambiguità e rendere esplicito il comportamento fuori dominio. Verificare anche le altre tabelle; i test SIS presenti coprono solo alcuni esempi.

**Criterio di chiusura.** Golden fixtures approvate per ogni estremo, assenza di sovrapposizioni/gap non previsti, numero/codici item verificati e parità fra dati importati e motore.

<a id="ai-01"></a>
## AI-01 — Storico IA associato agli indici più recenti e provenienza salvata inesatta

**Priorità:** P1. **Evidenza:** Confermato staticamente lungo l’intero flusso. **Stato:** [ ] Aperto.

**Riferimenti:** frontend_admin/lib/screens/multidimensional_dashboard_screen.dart:119,194,295; frontend_admin/lib/services/gemini_service.dart:181.

**Problema e impatto.** _analyses è indicizzato per idScala e contiene solo l’analisi di history.first. Quando si include lo storico, il serializer applica gli stessi indici recenti a ogni valutazione precedente della scala. _autoSaveAnalysis salva tutti gli ID di _latestEvaluations, non quelli effettivamente selezionati/inviati; non include correttamente lo storico scelto. Tutte le scale non San Martín/SIS vengono inoltre raggruppate nella selezione POS.

**Verifica.** Il percorso di lettura, selezione, serializzazione e salvataggio è stato seguito nel codice. Nessuna richiesta reale a Gemini è stata eseguita.

**Intervento.** Indicizzare analisi per id_valutazione, recuperare/calcolare quelle di ciascun evento e costruire un unico oggetto di contesto immutabile usato sia per richiesta sia per persistenza. Salvare IDs/versioni selezionati, modello, versione prompt e metadati necessari alla tracciabilità. Selezione esplicita per ciascun tipo scala.

**Criterio di chiusura.** Due valutazioni della stessa scala con indici diversi mantengono entrambi i risultati nel payload IA; esclusioni rispettate; evaluations_used coincide esattamente con gli eventi inviati.

<a id="ai-02"></a>
## AI-02 — Chiave Gemini nel browser e policy IA incoerente

**Priorità:** P1. **Evidenza:** Confermato staticamente. **Stato:** [ ] Aperto.

**Riferimenti:** frontend_admin/lib/services/gemini_service.dart:6,21,98; screens/multidimensional_dashboard_screen.dart:194,295,2803; backend/app/routes.py:get_settings:1137, save_patient_ai_analysis:566.

**Problema e impatto.** La chiave viene restituita ad admin e viewer con ai_enabled, poi utilizzata dal browser. Il flag globale viewer_ai_enabled governa il pulsante mentre il flag del JWT governa la chiave; un viewer abilitato può generare ma il salvataggio viene bloccato dal RBAC di scrittura. Dopo la generazione il codice salva automaticamente: non esiste il passaggio di approvazione dichiarato nella mappa precedente. I documenti salvati non hanno stato bozza/approvato.

**Verifica.** Il serializer include ID, data di nascita, note e dati di valutazione; note/allegati/storico possono contenere ulteriori informazioni identificative. Non è stata verificata alcuna configurazione del provider o requisito legale.

**Intervento.** Portare la chiamata Gemini in un servizio backend con chiave non recuperabile dai client, autorizzazione unificata, limiti per utente, timeout e audit. Separare dati e istruzioni, minimizzare il contesto e definire il ciclo bozza/revisione/approvazione. Allineare esplicitamente generazione, lettura, export e salvataggio per i viewer senza ampliare implicitamente i loro privilegi.

**Criterio di chiusura.** Nessuna chiave nei payload browser; matrice ruolo/ai_enabled/flag globale verificata; l’IA produce una bozza con provenienza corretta; salvataggio e approvazione seguono la policy stabilita.

<a id="ops-01"></a>
## OPS-01 — Versione e distribuzione degli asset non affidabili

**Priorità:** P1. **Evidenza:** Confermato staticamente. **Stato:** [ ] Aperto.

**Riferimenti:** VERSION; backend/app/main.py; frontend_admin/pubspec.yaml; frontend_admin/lib/app_version.dart; docker-compose.yml; backend/Dockerfile; frontend_admin/nginx.conf; frontend_admin/lib/config.dart.

**Problema e impatto.** VERSION/backend indicano 2.23.4, frontend/CACHE_BUST 3.0.0. VERSION non è incluso nel contesto di build backend né copiato nell’immagine: export può riportare unknown. Nginx assegna cache annuale immutable anche a main.dart.js con nome stabile; no-store su index.html non invalida quel JS. URL produzione hardcoded e CORS solo produzione ostacolano ambienti separati.

**Verifica.** Configurazioni versionate, senza build container o verifica browser della cache. Non si deduce quale versione sia effettivamente in produzione.

**Intervento.** Scegliere la versione prevista senza decrementi automatici, propagare con bump_version.py e aggiungere verifica di coerenza. Includere metadata release nel build backend. Cache corta/revalidata per entrypoint non fingerprintati, lunga solo per asset con hash; test di aggiornamento da release precedente. Rendere URL/origini configurabili per ambiente.

**Criterio di chiusura.** Backend/UI/backup riportano la stessa versione; browser con cache preesistente riceve la nuova app; staging funziona senza chiamare la produzione; nessun deploy è richiesto da questo assessment.

<a id="qa-01"></a>
## QA-01 — Suite test non riproducibile e copertura delle invarianti insufficiente

**Priorità:** P1. **Evidenza:** Esecuzione locale. **Stato:** [ ] Aperto.

**Riferimenti:** backend/tests/test_endpoints.py:9,15,39,218,251; backend/requirements.txt; frontend_admin/test/; frontend_admin/lib/services/api_service.dart.

**Problema e impatto.** La fixture imposta JWT_SECRET_KEY dopo l’import di app, che lo richiede già. Starlette 0.36.3 del manifest non funziona con TestClient e httpx 0.28.1. Con httpx 0.27.2 resta un fallimento per MockCollection senza count_documents; il mock manca anche di altri operatori/paginazione usati nel codice. Non c’è manifest test Python o workflow CI. Il parsing statico dei file Python rileva inoltre un errore di sintassi in update_changelog.py:5, script ausiliario storico non usato dall’app. I widget test usano dart:io mentre l’app importa dart:html: compatibilità da risolvere, non testata qui.

**Verifica.** Senza segreto: errore raccolta. Con segreto esterno e httpx 0.28.1: 11 passed, 10 errors. Solo nell’ambiente di assessment, con httpx 0.27.2: 20 passed, 1 failed. Python locale 3.12, diverso dal container 3.11. I test non certificano autorizzazioni, restore, storico IA o tabelle normative.

**Intervento.** Definire dipendenze runtime/test riproducibili; impostare env prima degli import; sostituire mock fragili con contract test e integrazione su MongoDB isolato. Aggiornare compatibilmente FastAPI/Starlette/httpx invece di affidarsi indefinitamente al solo downgrade diagnostico. Separare HTTP e storage browser tramite interfacce iniettabili e predisporre CI backend + Flutter Web.

**Criterio di chiusura.** Da checkout pulito, test backend e Flutter ripetibili; copertura negativa auth e dati, migrazione/restore, regressioni IA; build verificata con gli stessi runtime di distribuzione.

<a id="perf-01"></a>
## PERF-01 — Indicatori troncati e cache non invalidata su tutte le mutazioni

**Priorità:** P1. **Evidenza:** Confermato staticamente; impatto dipendente dai volumi. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:get_dashboard_stats:1158, get_patients:311, get_evaluations:661, export_patients_csv:1804, update_patient:514.

**Problema e impatto.** Dashboard legge al massimo 2.000 utenti e 5.000 valutazioni senza paginazione o avviso, quindi può restituire totali parziali. Altre letture impongono limiti silenziosi a storico/scale/analisi. Archiviazione tramite update_patient non invalida la cache di 300 secondi. CSV produce righe in streaming ma accumula prima tutte le valutazioni per utente in RAM. La cache è per processo.

**Verifica.** Non sono stati eseguiti benchmark e non si conoscono i volumi reali. I limiti e le invalidazioni mancanti sono espliciti nel codice.

**Intervento.** Aggregazioni MongoDB per conteggi/ultimi eventi, paginazione esplicita e segnali di troncamento. Centralizzare invalidazioni; definire coerenza con più processi e protezione da ricalcoli contemporanei. Per CSV aggregare solo le ultime date utili senza mantenere tutto lo storico.

**Criterio di chiusura.** Dataset oltre ogni limite attuale restituisce totali corretti; archiviazione/restore/modifica aggiornano gli indicatori; consumo memoria e latenza misurati sul volume concordato.

<a id="obs-01"></a>
## OBS-01 — Audit incompleto ed errori convertiti in dati apparentemente validi

**Priorità:** P2. **Evidenza:** Confermato staticamente. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:49,207,268,1078,1681,1727,1758,1974; frontend_admin/lib/services/api_service.dart.

**Problema e impatto.** Login, gestione operatori, export/import e diverse modifiche non invocano log_audit. Errori audit vengono solo stampati. Dashboard intercetta eccezioni e restituisce 200 con zeri e traceback. ApiService spesso converte errori in liste vuote/null/bool senza distinguere assenza dati da fallimento. Il parametro limit dei log non ha bound espliciti.

**Verifica.** Tracciamento delle chiamate e dei rami except; nessuna ispezione dei log reali. SEC-01 copre anche l’attribuzione falsificabile della compilazione.

**Intervento.** Definire catalogo eventi e attore autenticato; tracciare operazioni amministrative e accessi rilevanti senza segreti. Errori strutturati e codici HTTP corretti, correlation ID, niente traceback verso i client. Distinguere stato vuoto/errore nella UI e limitare paginazione audit.

**Criterio di chiusura.** Ogni operazione sensibile produce l’evento previsto; simulazione guasto DB mostra errore riconoscibile e non indicatori a zero; nessun segreto o traceback nelle risposte.

<a id="data-03"></a>
## DATA-03 — Import scala perde le sottodomande composite

**Priorità:** P2. **Evidenza:** Riprodotto con protocollo sintetico. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py:878 (costruzione Question in import_scale); backend/app/models.py:99; frontend_admin/lib/screens/wizard_screen.dart:1122.

**Problema e impatto.** Question supporta tipo e sottodomande e la UI ha un percorso composito, ma l’import standard non copia questi campi dalla domanda sorgente. Un protocollo composito importato diventa likert con sottodomande assenti.

**Verifica.** Import sintetico restituisce 200 con tipo=likert e sottodomande=null. Nei cinque file della cartella scale/ esaminati non sono state trovate domande composite: il difetto è riprodotto sulla funzionalità supportata dal modello, non dichiarato come danno già presente nei dati operativi.

**Intervento.** Preservare e validare tipo/sottodomande attraverso import, DB, API, modelli Dart e salvataggio risposte. Allineare eventuali formati sorgente diversi senza appiattimenti silenziosi.

**Criterio di chiusura.** Round-trip di una scala composita mantiene struttura e punteggi; errori di formato vengono rifiutati prima della scrittura.

<a id="ui-01"></a>
## UI-01 — Operazioni asincrone senza gestione robusta del ciclo di vita

**Priorità:** P2. **Evidenza:** Confermato staticamente. **Stato:** [ ] Aperto.

**Riferimenti:** frontend_admin/lib/screens/multidimensional_dashboard_screen.dart:90,194,295; frontend_admin/lib/services/gemini_service.dart:98; frontend_admin/lib/services/api_service.dart.

**Problema e impatto.** I flussi lunghi IA/caricamento eseguono setState e usano context dopo await senza controlli mounted in tutti i rami. Le chiamate HTTP non definiscono timeout/cancellazione applicativi; il parsing Gemini assume candidates[0].content.parts[0].text. Il caricamento storico/analisi per scala è sequenziale.

**Verifica.** Nessuna esecuzione Flutter o richiesta Gemini; rischio desunto dai percorsi asincroni e dal parser. Non è affermato un crash riprodotto su browser.

**Intervento.** Stati caricamento/errore espliciti, mounted e cancellazione quando la schermata viene chiusa, timeout e gestione risposte vuote/bloccate/parziali. Concorrenza limitata per caricamenti indipendenti; retry solo dove idempotente.

**Criterio di chiusura.** Uscita dalla schermata durante IA, timeout e risposta Gemini senza candidati non causano eccezioni UI o perdita silenziosa del risultato.

<a id="arch-01"></a>
## ARCH-01 — Concentrazione delle responsabilità e concorrenza PDF da verificare

**Priorità:** P2. **Evidenza:** Valutazione architetturale sul codice. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/routes.py (1.994 righe); backend/app/pdf_generator.py (1.720); frontend_admin/lib/screens/multidimensional_dashboard_screen.dart (3.599); evaluation_detail_screen.dart (3.556).

**Problema e impatto.** Controller mescola autorizzazioni, import/export, query, aggregazioni e policy. Le schermate mescolano stato, calcolo e presentazione. PDF è già spostato con asyncio.to_thread: non è corretto affermare che il rendering avvenga sempre sull’event loop. Tuttavia gli helper usano pyplot globale con tight_layout/savefig, per cui richieste concorrenti richiedono una verifica mirata.

**Verifica.** La dimensione non prova da sola un difetto. Il rischio concorrenza PDF non è stato riprodotto; va verificato con due richieste e dati distinti. Non serve sostituire lo stack per affrontare questi problemi.

**Intervento.** Dopo i fix funzionali, separare router/policy, servizi valutazioni e backup, repository dati e motori puri. Estrarre view model e componenti UI testabili. Per PDF usare figure esplicite e isolamento/serializzazione dove necessario, con limite di concorrenza e dimensione.

**Criterio di chiusura.** Contract test invariati durante il refactor; due PDF simultanei non scambiano grafici o contenuti; limiti di risorse osservabili.

<a id="sec-05"></a>
## SEC-05 — Contratto password incompatibile con bcrypt risolto dall’ambiente

**Priorità:** P2. **Evidenza:** Riprodotto localmente. **Stato:** [ ] Aperto.

**Riferimenti:** backend/app/models.py:UserCreate, UserUpdate; backend/app/auth.py:22,29; backend/requirements.txt.

**Problema e impatto.** I modelli ammettono fino a 128 caratteri, ma bcrypt 5.0.0 risolto dal vincolo >=4.0.0 rifiuta input oltre 72 byte. hash_password non converte questo errore in una risposta di validazione. Il numero di byte può superare quello dei caratteri con Unicode.

**Verifica.** hash_password su 73 caratteri ASCII genera ValueError nell’ambiente di assessment. Non si assume che il container in produzione abbia la stessa versione.

**Intervento.** Definire esplicitamente politica e algoritmo password; validazione coerente in byte se resta bcrypt, oppure migrazione controllata dell’hashing con verifica degli hash esistenti. Non troncare silenziosamente. Allineare messaggio UI e API.

**Criterio di chiusura.** Limiti ASCII/Unicode, creazione, cambio password e login gestiti senza 500; compatibilità con hash preesistenti verificata.

## Ordine di lavoro e dipendenze

1. **Contenimento:** SEC-01 e SEC-02 insieme all’aggiornamento delle chiamate Flutter. Verificare SEC-04 senza utilizzare credenziali trovate nel repository. QA-01 abilita i test di regressione fin dall’inizio.
2. **Identità e dati:** SEC-03, SEC-05, DATA-01 e DATA-02. Preparare un backup e verificarne il ripristino su ambiente isolato prima di qualsiasi migrazione. Non eseguire l’attuale import per “provare” su dati reali.
3. **Affidabilità dei risultati:** FUN-01/FUN-02, SCORE-01/SCORE-02 e DATA-03. Le tabelle richiedono una fonte approvata: più ragionamento del modello non sostituisce questa verifica.
4. **IA:** AI-01 prima di fidarsi dei confronti storici; AI-02 per chiavi, privilegi e workflow bozza/approvazione. Collegare le relazioni alle versioni definite in DATA-02.
5. **Rilascio e qualità:** OPS-01, PERF-01, OBS-01, UI-01. Completare QA-01 con CI e build dello stesso ambiente di distribuzione.
6. **Refactor:** ARCH-01 dopo la stabilizzazione dei contratti. Mantenere FastAPI/Flutter/MongoDB; non emerge la necessità di una riscrittura totale.

## Evidenze di test dell’assessment

Ambiente: Python 3.12 locale, FastAPI 0.109.2, Starlette 0.36.3, Pydantic 2.6.1, bcrypt 5.0.0. Il Dockerfile usa Python 3.11: gli esiti non sostituiscono una verifica sull’immagine. Nessun codice applicativo o test del repository è stato modificato per ottenere gli esiti.

| Prova | Esito |
| --- | --- |
| Raccolta test senza JWT_SECRET_KEY esterna | Errore all’import app: fixture troppo tardiva |
| Suite con segreto sintetico e httpx 0.28.1 | 11 passed, 10 errori di setup TestClient |
| Stessa suite con solo httpx 0.27.2 nell’ambiente locale | 20 passed, 1 failed: MockCollection.count_documents assente |
| Verifiche ASGI/pure aggiuntive | 16 osservazioni locali, riepilogate sotto |
| Flutter, Docker, MongoDB reale, provider IA | Non eseguiti |

Comando della suite, dalla directory backend, in un virtualenv con requirements e dipendenze test installate:

```bash
JWT_SECRET_KEY=assessment-only-synthetic-secret-not-for-production PYTHONPATH=. python -m pytest tests/test_endpoints.py test_sis.py -q --tb=short
```

Il downgrade httpx è stato solo diagnostico; non è stato committato né indicato come soluzione definitiva.

Le prove aggiuntive hanno usato httpx.ASGITransport, lifespan disattivato e sostituzione in memoria delle sette collection in routes/auth; nessuna connessione MongoDB. I token sono firmati con una chiave sintetica conosciuta al test. La seguente tabella è il registro compatto delle osservazioni, non una suite di regressione già integrata.

| Scenario | Esito osservato |
| --- | --- |
| GET anagrafiche client senza token | 200, un utente sintetico restituito |
| POST valutazione senza token, scala inesistente, dati invalidi | 201, persistita e autore arbitrario nell’audit |
| GET backup con viewer | 200, hash e chiave sintetici presenti |
| JWT per operatore non presente nel DB di test | 200 su GET /users |
| Ricerca + filtro incompleti | Predicato regex assente nella query finale |
| Utente con valutazione e filtro mai_valutati | Incluso nei risultati della simulazione |
| ID corpo diverso da ID path in PUT anagrafica | 200, riferimento della valutazione non aggiornato |
| DELETE anagrafica con relazione IA | Relazione rimasta orfana |
| Import elenco vuoto | 200, dati precedenti conservati |
| Import collection malformata | 500, collection già cancellata nella simulazione |
| Import data ISO | Persistita come str |
| Import domanda composita sintetica | Diventa likert, sottodomande null |
| SIS senza risposte | Indice 68, somma standard 27, zero item |
| SIS A1 con F=99 | Diretto 99, motore SIS 4 |
| Intervalli San Martín enumerati | Sovrapposizioni AU=13 e BE=19 |
| Hash password ASCII di 73 caratteri | ValueError con bcrypt 5.0.0 |

Riproduzione minima senza API per la verifica dei punteggi, dalla directory backend:

```python
from app.analytics import calcola_punteggi_sis, compute_direct_scores
print(calcola_punteggi_sis([], {})["indice_sis"])  # 68 nello snapshot
answers = [{"codice_domanda": "A1", "punteggio": {"F": 99, "D": 0, "T": 0}}]
print(compute_direct_scores(answers, {"A": "A"})[0]["punteggio_totale"])  # 99
print(calcola_punteggi_sis(answers, {})["domini"][0]["punteggio_grezzo"])  # 4
```

## Correzioni pregresse riconosciute

Il piano precedente non va interpretato come interamente ancora aperto. Nello snapshot sono presenti: obbligo di JWT_SECRET_KEY, assenza del fallback password in chiaro, rimozione di auth_manager.py, pool/timeout Motor, lifespan, migrazione attivo al bootstrap, query bulk per alcune letture, cache dashboard, generazione PDF tramite asyncio.to_thread e output CSV incrementale. Questi miglioramenti sono reali ma non chiudono automaticamente le criticità residue sopra. In particolare “filtri server-side”, “CSV streaming” e “RBAC presente” non bastano a dimostrare correttezza complessiva.

## Protocollo di chiusura

Per chiudere un intervento: indicare commit, data, test/evidenza e limiti residui; aggiornare prima la mappa centrale quando cambiano contratti, ruoli, dati o flussi. Spuntare la voce solo dopo verifica. Non segnare come risolte anomalie normative sulla base di un’ipotesi del modello. Non modificare la versione applicativa per il solo aggiornamento di questo assessment.
