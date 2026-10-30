# Registro centralizzato dei test differiti

Aggiornato: 30 ottobre 2026. Questo file raccoglie i casi da realizzare, completare ed eseguire dopo la fase fix. **Nessun caso è attestato come superato sulla revisione finale.** Le esecuzioni storiche in file.md riguardano revisioni intermedie. Non eseguire automaticamente questi test: la fase è stata rinviata dall'utente.

Per ogni esecuzione futura registrare ID, commit/diff esatto, ambiente/versioni, dati sintetici, comando o passi UI, risultato atteso/osservato, evidenza senza segreti, esito PASS/FAIL/SKIP e difetto collegato. Uno SKIP non è un PASS. Tutti i casi sotto sono **DA VERIFICARE**; i riferimenti ai file automatizzati indicano materiale già preparato, da confrontare con ciascun caso e completare.

## C1 — Preparazione e criteri

Fonti: ASTRA-02/03, backend/app/backup_service.py, maintenance.py, routers/backup.py, BACKUP_OPERATIONS.md, frontend api_service/settings_screen. Materiale esistente: backend/tests/test_backup_service.py e test_backup_integration.py. Non aggiungere credenziali reali alle fixture.

Preparare replica set MongoDB usa-e-getta e standalone separato, database sintetico autanalysis con dieci collection coerenti, admin/viewer, chiavi temporanee e copia legacy a otto collection. Usare almeno due account, riferimenti tra valutazioni/scale/utenti, job in tutti gli stati, notifiche lette/non lette, impostazioni IA cifrate, licenza trial e identità commerciali sintetiche. Per prove API/UI includere Nginx e Flutter. Database cliente e provider a pagamento esclusi. L'integration suite usa C1_TEST_MONGODB_URL localhost e DB autify_c1_test_<uuid>; le prove di avvio app/migrazione richiedono uno stack separato, non cambiare l'URI di produzione.

| ID / livello | Preparazione e azione | Risultato atteso |
|---|---|---|
| C1-01 unità + Mongo | Export→decrypt→decode→restore delle dieci collection con ObjectId, datetime UTC, Binary, Int64 e campi extra BSON | Tipi e valori preservati; differenze ammesse solo token_version, job interrotti e audit aggiunto |
| C1-02 Mongo | Archivio con collection vuote, destinazione popolata | Le collection vuote vengono realmente svuotate; nessun dato vecchio sopravvive |
| C1-03 unità + API | Mancanza/aggiunta collection, nomi errati e live collection non registrata | Rifiuto prima delle scritture; export non produce archivio incompleto |
| C1-04 unità + API | JSON radice non oggetto, chiavi duplicate, schema ignoto, database errato, lista/documento malformato | 422 senza mutazioni; errore comprensibile, nessun 500 per tipi ostili |
| C1-05 unità | ID duplicati/applicativi/_id, riferimenti mancanti o tipo dict/list, date assenti/stringa in v2, tipi coercibili ma errati | Rifiuto schema/riferimenti prima della transazione |
| C1-06 unità | Admin assente, hash non stringa/formato errato, flag non booleani, token_version bool/Int64/limiti | Rifiuti corretti; Int64 valido accettato; almeno un admin con hash strutturalmente valido |
| C1-07 unità + Mongo | Legacy JSON ed ENC completi: decode→restore, ripetere validate sul documento convertito | Migrazione idempotente, date UTC, jobs/notifiche vuoti; nessun errore da seconda validazione |
| C1-08 unità | Legacy parziale, date ambigue/non valide, tipi perduti da default=str | Rifiuto dati non ricostruibili in modo affidabile; nessuna invenzione di tipi/ID |
| C1-09 unità | Cifra/decifra v2, ruota chiave con keyring; chiave assente/corta, sconosciuta, header/nonce/cipher alterati | Round-trip con chiavi corrette; rifiuto alterazioni; nessun segreto in log/errori |
| C1-10 unità | ENC legacy con JWT corrente/precedente, keyring non JSON/non lista | Lettura solo con chiave corretta, errore gestito negli altri casi |
| C1-11 unità + API | Impostazioni IA cifrate con chiave originale e chiave incompatibile | Compatibile accettato; incompatibile rifiutato prima delle scritture, segreti non azzerati |
| C1-12 API + proxy | File/payload al limite e oltre 64MiB, overhead multipart, documento oltre limite BSON, export troppo grande | Limiti coerenti, 413 o rifiuto previsto; nessun export nuovo non reimportabile per dimensione |
| C1-13 Mongo | Export concorrente: cambiare dati tra letture di due collection | Snapshot coerente, non mescola stati temporali |
| C1-14 Mongo | Iniettare errore in ogni collection dopo delete e durante insert | Rollback completo di tutte le collection; confronto con stato iniziale |
| C1-15 Mongo | Violazione indice unique e fallimento inserimento audit finale | Nessuna sostituzione parziale; indici destinazione mantenuti |
| C1-16 Mongo | Cancellazione richiesta, processo interrotto prima commit, disconnessione prima/durante commit | Atomicità; quando esito incerto messaggio senza falsa garanzia rollback, audit/ID permette ricostruzione |
| C1-17 Mongo | Errore transient/retry callback, commit con esito sconosciuto | Nessun effetto esterno duplicato; un solo evento restore committed; nessun reinvio applicativo cieco |
| C1-18 Mongo + API | Restore su standalone/primary assente e manutenzione disabilitata | Rifiuto esplicito; nessun fallback distruttivo |
| C1-19 API | Manutenzione riavviata con unico processo: login/settings/export/import/audit e richieste di dominio/IA concorrenti | Percorsi consentiti serializzati; dominio/nuovi job503; eventuale gate licenza documentato |
| C1-20 API | Restore con JWT preesistenti da origine e destinazione, poi login con credenziali archivio | Vecchie sessioni revocate; nuovo login valido, epoca entro int64 |
| C1-21 Mongo | Job pending/running/completed/failed e notifiche con riferimenti validi | Solo pending/running diventano failed; nessuna chiamata provider automatica |
| C1-22 API + Mongo | Stessa identità licenza, commerciale diversa, destinazione vuota/trial | Identità commerciale diversa bloccata; recupero consentito negli scenari documentati |
| C1-23 API | Anonimo/viewer/admin, licenza valida/scaduta su export/import e CSV | Backup completo solo admin; recupero API admin possibile anche scaduta, CSV mantiene gate |
| C1-24 UI | Export, selezione file, conferma/annulla, restore successo/errore e doppio click | Annulla non invia; azioni occupate disabilitate; errori visibili; successo torna al login |
| C1-25 UI + rete | Timeout invio/header/body, errore di rete e risposta proxy dopo possibile commit | Nessun retry automatico; istruzione verifica audit/manutenzione; UI torna utilizzabile |
| C1-26 infrastruttura | Copia sintetica standalone esistente → Compose replica set stesso volume; restart ripetuti | Dati e volume conservati, bootstrap idempotente, primary healthy, backend avviato dopo health |
| C1-27 infrastruttura | Replica set con nome diverso, writer esterni, più processi | Nessuna riconfigurazione distruttiva automatica; documentare prerequisiti non imposti dal lock locale |
| C1-28 packaging | Versione generata, immagine backend, env/keyring, proxy route import | Versione archivio coerente con VERSION; modulo incluso; limite speciale solo import |
| C1-29 recupero | Simulare restore licenza scaduta/UI bloccata e timeout senza ID ricevuto | Recupero via API autenticate; controllo audit infrastrutturale in sola lettura secondo procedura |

Chiusura C1: completare casi critici su Mongo reale e flusso UI, documentare limiti infrastrutturali e verificare backup di ritorno prima di considerare un deploy. Mock e controllo whitespace non dimostrano atomicità o recuperabilità reale.

## C2 — Identità, sessioni e permessi viewer

Perimetro: ASTRA-10 bootstrap/sessione e ASTRA-08 IA/notifiche viewer. Fonti: auth.py, routers/auth.py, _helpers.py, settings.py, ai.py, maintenance.py, login_screen.dart, main.dart, api_service.dart. Tutti i casi **DA REALIZZARE/ADEGUARE ED ESEGUIRE**, nessuna nuova prova effettuata. Riutilizzare le fixture esistenti aggiornandole al contesto autenticato con token_version e al nuovo endpoint capabilities; non rimuovere controlli per far passare test vecchi. Provider IA simulato, mai chiamate a pagamento.

| ID / livello | Preparazione e azione | Risultato atteso |
|---|---|---|
| C2-01 bootstrap | DB vuoto, INITIAL_ADMIN_PASSWORD assente/vuota/corta/>72byte; poi valore valido | Avvio rifiutato senza password valida; nessun admin/admin creato. Con valore valido un admin bcrypt, must_change_password=true, nessun segreto nei log |
| C2-02 Mongo | Riavvio su DB popolato con variabile cambiata/assente, bootstrap concorrente | Credenziali esistenti preservate; un solo admin grazie a indice unique; nessuna sovrascrittura |
| C2-03 migrazione | Vecchio admin/admin senza flag o flag falso; account con password già diversa | Solo bootstrap storico insicuro marcato obbligatorio; password diversa conservata. Ripetere dopo restore legacy senza restart |
| C2-04 API | Login admin/viewer con must_change_password=true; chiamare GET/POST dominio, backup, users, settings, IA, notifiche e percorsi client | 403 password_change_required su tutte le API protette diverse dal cambio personale; nessun dato o scrittura di dominio |
| C2-05 UI | Login obbligatorio, refresh prima del cambio, back browser e flag localStorage manomesso | UI torna al login/dialog; bypass client non supera enforcement server |
| C2-06 API + UI | Cambio personale con password corrente corretta, nuova>=12caratteri<=72byte e conferma | Hash aggiornato, flag falso, token_version incrementato, audit senza segreti; tutte le vecchie sessioni401; login con nuova password funziona |
| C2-07 API | Password attuale errata, nuova uguale, conferma diversa, Unicode>72byte, spazi soli, campi role/username aggiunti | Rifiuto400/422 senza modifica di hash/flag/versione; extra vietati; nessun cambio di altri account |
| C2-08 Mongo | Due cambi paralleli e reset admin concorrente | Compare-and-swap consente solo il cambio coerente con hash/versione letti; conflitto409 senza sovrascrittura del valore più recente |
| C2-09 API | JWT senza sub/exp/iat/token_version, versioni bool/stringa, firma errata/scaduto, account eliminato | 401; nessun fallback per JWT privo di versione; login emette token completo |
| C2-10 API | Token con vecchi claim role/ai_enabled, DB aggiornato; cambio autorizzazioni con incremento versione | Permessi ricavati dal DB; token revocati401. Claim vecchi non concedono privilegi |
| C2-11 UI | Admin modifica sé stesso via gestione utenze (password/ruolo/flag IA) | Pulizia sessione e nuovo login; nessuna dashboard con token revocato |
| C2-12 API | Viewer, tutte le quattro combinazioni flag personale/globale IA; admin personaleON/OFF | Viewer202 solo entrambiON; altri403 senza job/provider. Admin richiede flag personale, non quello globale |
| C2-13 UI + API | Viewer abilitato avvia IA da schermata multidimensionale con prompt server configurato | Payload senza system_prompt; job usa prompt server. Richiesta manuale viewer con override anche vuoto403; admin override consentito |
| C2-14 API | GET ai/capabilities e settings/ai come admin/viewer abilitato/disabilitato | Capabilities espone solo metadati minimi e can_analyze; settings/ai solo admin; nessun prompt, URL, header o hint chiave nei dati viewer. GET settings viewer senza gemini_prompt |
| C2-15 API | Viewer legge una propria notifica, poi ID altrui e inesistente | Propria200/read=true; altrui/inesistente404 e documento immutato |
| C2-16 API + UI | Viewer read-all con notifiche proprie/altrui e flag IA OFF | Aggiornate solo proprie non lette; contatore coerente; lettura notifiche indipendente da permesso nuova generazione |
| C2-17 API | Viewer tenta PUT/DELETE notifiche, URL simili, settings/users e scritture dominio | Eccezione RBAC limitata ai due POST previsti; nessuna autorizzazione generalizzata |
| C2-18 API | Account con cambio obbligatorio e licenza scaduta/in manutenzione | Cambio personale disponibile senza gate licenza, serializzato in manutenzione; altre operazioni ancora bloccate |
| C2-19 C1+C2 | Restore utenti con flag obbligatorio, epoca Int64 e password bootstrap storica | Revoca C1 mantenuta, login/cambio C2 coerenti, admin deve cambiare prima di nuovo export/import |
| C2-20 UI + rete | Risposta cambio persa dopo salvataggio, 409, 401, rate limit, errore validazione | Messaggi utili, nessun accesso con token vecchio; possibilità nuovo login senza loop; credenziali mai nei log |
| C2-21 confezionamento | Compose/.env.example, VERSION e derivati, frontend/backend aggiornati insieme | Variabile bootstrap inoltrata senza default noto; versione4.0.4 coerente; client aggiornato usa capabilities e change-password |

Per C2-20 verificare anche ripresa dopo ricarica: se la richiesta ha già aggiornato la password, la nuova credenziale consente il login; non assumere che un errore di rete implichi rollback. I test API devono montare le vere dipendenze auth/RBAC/licenza, non soltanto invocare direttamente l'handler con auth simulata.

## C3 — Valutazioni, protocolli e storico

Tutti i casi **DA REALIZZARE/ADEGUARE ED ESEGUIRE**. Fonti: evaluation_contract.py, scale_import.py, routers/evaluations.py e settings.py, analytics.py, modelli e vista dettaglio Flutter. Usare copie dei protocolli repository e dati sintetici. Per concorrenza/snapshot usare Mongo replica set reale isolato; mock non attestano transazioni.

| ID | Preparazione e azione | Risultato atteso |
|---|---|---|
| C3-01 | Import HTTP del JSON SIS incluso nel repository, autenticato admin | Nessun NameError; sezioni A-F/SEZ2/SEZ3, opzioni e metadati preservati |
| C3-02 | Import JSON non oggetto, scala non oggetto, sezioni/alias duplicati, payload che tenta di sovrascrivere sezioni con metadati extra | 422; protocollo precedente intatto, nessuna modifica parziale |
| C3-03 | Create e update con stessi input invalidi: lista vuota, item mancanti, extra, duplicati anche via codice e id_domanda equivalenti | Stesso rifiuto422 in entrambi; nessuna scrittura |
| C3-04 | Punteggi bool/stringa/float, interi fuori opzioni, dict F/D/T su domanda ordinaria | Rifiuto senza coercizione silenziosa; zero valido quando previsto |
| C3-05 | SIS: dimensione mancante/extra, bool, fuori0-4, A3 F=4; scala con solo sei item o item A-F aggiunti | Rifiuto; protocollo supportato richiede i 49 item A-F della fonte locale; A3 F<=3 |
| C3-06 | SIS completa e legacy con un item per ciascuno dei sei domini | Completa analizzabile; legacy incompleta senza indice/percentile, messaggio esplicito, mai indice68 ottenuto dal vecchio caso parziale |
| C3-07 | Composito: conteggio0/N, negativo/N+1, senza sottodomande; wizard seleziona zero esplicito | Range coerente; solo risposte reali nel payload, nessuna chiave ausiliaria _checklist |
| C3-08 | Create stesso id_valutazione, anche concorrente; avvio con duplicati preesistenti | Unique impedisce duplicati,409; migrazione indice fallisce senza cancellare dati storici da riparare |
| C3-09 | Create con snapshot client falsificato | Snapshot server completo prevale; hash e provenienza original salvati, senza _id/revision di Mongo |
| C3-10 | Salva valutazione, modifica struttura/opzioni/metadati scala, rileggi analysis/PDF/aggregati e modifica risposte | Tutti usano lo snapshot originario; validazione update segue le opzioni storiche |
| C3-11 | Elimina scala dopo valutazione, naviga dal profilo multidimensionale allo storico | Protocollo storico ancora elencato; dettaglio/PDF/analisi disponibili; nuova compilazione della scala eliminata non consentita |
| C3-12 | Legacy senza snapshot, primo accesso e successivi dopo modifica scala | Snapshot congelato una volta, provenance legacy_current_not_original; UI/PDF dichiarano ricostruzione, non originale attestato |
| C3-13 | Modifica/import/delete scala con legacy senza snapshot, iniettare errore dopo freeze | Freeze e mutazione nella stessa transazione; rollback conserva intero stato precedente |
| C3-14 | Create concorrente a modifica/delete scala | Snapshot coerente con una versione intera, conflitto/ritentativo transazionale senza mix tra versioni |
| C3-15 | Snapshot malformato o legacy senza scala corrente né snapshot | 409 esplicito; nessun fallback a protocollo inventato; UI termina caricamento con errore |
| C3-16 | Dettaglio seleziona due valutazioni con versioni differenti della stessa scala | Domande, etichette e opzioni della selezione corrente; conteggio composito modificabile0..N |
| C3-17 | Legacy incompleta/malformata su aggregati, analisi, PDF e dashboard storico | Nessun punteggio standard o alert falsamente rassicurante; dati originali conservati, avviso visibile |
| C3-18 | Utente eliminato mentre create/update valutazione è in corso | Transazione/riferimento utente impedisce nuovo orfano; update senza documento non ritorna successo |
| C3-19 | Backup/restore dopo eliminazione scala con snapshot valido e con snapshot invalido | C1 accetta riferimento soddisfatto dallo snapshot valido; rifiuta assenza o snapshot incompatibile |
| C3-20 | Round-trip dati BSON di snapshot e hash, protocolli POS/San Martin/SIS/compositi del repo | Metadati conservati; nessuna integrazione silenziosa da versioni bundled più recenti; calcoli validi confrontati con fixture di dominio approvate |

Non introdotto workflow bozze: nuove create/update devono essere complete. Non interpretare questi fix come certificazione delle tabelle normative. Per dati legacy parziali la conservazione non implica validità ai fini degli indici. C6 resta responsabile della policy scadenze/KPI.

## C4 — Coda IA persistita e cancellazioni

Tutti i casi **DA REALIZZARE/ADEGUARE ED ESEGUIRE**. Fonti: job_worker.py, transactions.py, main.py, routers/ai.py e patients.py. Adapter finto con contatore invocazioni e barriera controllabile; niente chiamate provider reali. Eseguire scenari transazionali su Mongo isolato, prove restart su processi separati.

| ID | Preparazione e azione | Risultato atteso |
|---|---|---|
| C4-01 | Accoda, arresta API prima del claim, riavvia | Job pending ripreso dal polling; una chiamata provider, senza dipendenza dal vecchio create_task della richiesta |
| C4-02 | Due o più processi reclamano lo stesso pending | Un claim atomico/lease token, una sola esecuzione normale |
| C4-03 | Molti pending, più processi; coda con200 pending | Non più di2 running globali, un job alla volta per processo; enqueue oltre200 rifiutato429 |
| C4-04 | Arresto dopo claim prima/durante chiamata, restart entro/dopo900secondi | Running non riaccodato; dopo lease failed con avviso esito incerto; zero replay automatici |
| C4-05 | Legacy running senza lease e pending senza owner_token_version | Running chiuso come incerto; pending privo di autorizzazione verificabile fallisce senza provider |
| C4-06 | Provider timeout/429/503/rete interrotta | max_retries=0 nel worker, un solo tentativo; errore pubblico generico senza segreti, nuova analisi solo esplicita |
| C4-07 | Provider risponde dopo timeout/cancellazione o lease scaduta | Nessuna pubblicazione tardiva da worker senza lease valida; nessuna falsa notifica successo |
| C4-08 | Arresto/errore dopo ogni scrittura di report/stato/notifica/audit | Commit tutto o niente; un solo risultato con ID deterministico e una notifica terminale |
| C4-09 | Commit pubblicazione con esito sconosciuto, retry callback/worker recovery | Stato committed riconosciuto; nessuna seconda richiesta provider e nessun doppio risultato |
| C4-10 | Provider risponde, DB indisponibile prima della pubblicazione | Non riemettere provider; job resta running fino a recovery, poi failed/incerto; perdita risposta dichiarata |
| C4-11 | Elimina utente con job pending/running/completed, valutazioni, report e notifiche | Cancellazione atomica di tutte le dipendenze; audit nella stessa transazione |
| C4-12 | Delete utente mentre worker pubblica, in entrambi gli ordini | O pubblicazione precede delete e viene cancellata, o worker non pubblica; nessun orfano/ricreazione |
| C4-13 | Delete concorrente a enqueue, create valutazione e salvataggio manuale relazione | Scritture confliggono sul documento utente; nessun figlio creato dopo delete |
| C4-14 | Cancella e ricrea lo stesso ID applicativo utente durante un vecchio job | parent_mongo_id impedisce di attribuire il risultato alla nuova anagrafica |
| C4-15 | Errore dopo ogni delete della cascata e audit failure | Rollback completo; parent/figli non rimangono parzialmente rimossi |
| C4-16 | Archivia con attivo=false, accoda o processa pending | Nuovi job e pending non ancora inviati bloccati; storico preservato; running già inviato non annullato presso provider |
| C4-17 | Revoca token/flag/ruolo o elimina operatore prima del processing | Ricontrollo permessi C2; nessuna chiamata quando non più autorizzato |
| C4-18 | Avvio BACKUP_MAINTENANCE_MODE=true e restore C1 | Nessun worker avviato; restore trasforma pending/running in failed; nessun job rieseguito uscendo dalla manutenzione |
| C4-19 | Backup/restore lease_expires_at/parent_mongo_id/owner_token_version e job terminali | BSON/date coerenti; nessuna nuova collection esclusa dal registro C1 |
| C4-20 | Arresto lifespan, DB offline, ripartenza e record legacy orfani | Task gestito/cancellato, polling riprende senza creare task illimitati; nessuna promessa exactly-once provider |
| C4-21 | Successo/fallimento con input/allegato sensibile | Input transitorio rimosso dal job terminale, audit/log/notifiche senza errori provider grezzi; report conservato secondo policy corrente |
| C4-22 | Viewer legge report/notifiche proprie dopo recovery; prova ID altrui | Policy C2 preservata, stati UI coerenti; nessun accesso indiretto a input privati del job |

Non configurata una retention temporale automatica: nessun TTL introdotto per report/storico. La cancellazione definitiva elimina i dati associati; l'archiviazione ordinaria li conserva. La chiamata già inviata a un provider può restare fatturata anche dopo cancellazione locale: verificare che la UI/documentazione non prometta annullamento remoto o exactly-once. Doppio invio volontario di POST /ai/analyze crea due operazioni distinte: idempotenza C4 riguarda claim e pubblicazione dello stesso job.

## Evidenze esterne e revisione da attestare

Alla ripresa è presente test_resul.md con risultati C1 di un'altra attività e file Flutter di dipendenze modificati. Preservati; non sono esecuzioni effettuate durante C3/C4 e non attestano la revisione finale. La futura campagna deve registrare il commit/diff esatto: non promuovere automaticamente a PASS i casi corrispondenti sulla base di risultati precedenti.

## C5 — Provenienza canonica, minimizzazione e revisione delle relazioni

Tutti i casi **DA REALIZZARE/ADEGUARE ED ESEGUIRE**. Fonti: ai_context.py, job_worker.py, routers/ai.py, modelli, backup_service.py e frontend multidimensionale/api_service. Fixture: due utenti distinti, due date della stessa scala con snapshot differenti, risposte valide contenenti0, fonti legacy, report draft/approved/manuali, allegato sintetico. Provider finto con cattura del payload; mai inviare dati reali nelle prove.

| ID | Preparazione e azione | Risultato atteso |
|---|---|---|
| C5-01 | Seleziona due valutazioni della stessa scala in date/versioni diverse e richiedi IA | Client invia entrambi gli ID; server ricalcola ogni analisi col proprio snapshot; nessun fallback per idScala |
| C5-02 | Alterare body patient/evaluations/history_reports o inviare vecchio payload completo | 422 con richiesta aggiornamento client; dati e analisi client non considerati canonici |
| C5-03 | ID valutazione o relazione di altro utente, assente o vuoto | Rifiuto prima del job/provider, nessuna mescolanza di dati |
| C5-04 | ID duplicati, oltre100 valutazioni/50 report, id_valutazione discordante | Rifiuto422; singolo id_valutazione coerente supportato con id_paziente esplicito |
| C5-05 | Valutazione legacy senza snapshot; scala corrente disponibile/assente | Congelamento C3 con provenienza dichiarata, oppure409; mai snapshot trattato come risultato analitico |
| C5-06 | Selezionare protocollo incompleto o punteggi invalidi | Rifiuto prima dell'invio; nessun indice inventato per completare il contesto |
| C5-07 | Input con zero, false e campi analitici null | JSON preserva0/false/null distintamente; zero non diventa assenza |
| C5-08 | Nome/cognome/CF/data nascita/note anagrafiche/demographics/nome operatore/note risposta sintetici riconoscibili | Assenti dal payload strutturato; codice utente locale non inviato come identificatore personale; contesto mantiene date valutazioni e punteggi |
| C5-09 | Note libere, allegato e/o report storico senza conferma; poi conferma UI | Prima422; poi contenuti selezionati trasmessi esplicitamente; annulla non accoda. Nessuna promessa di anonimizzazione automatica dei testi |
| C5-10 | Nome file identificativo e allegato sintetico | Nome generico al provider, bytes invariati e SHA256 coerente; hash non contiene bytes/base64 |
| C5-11 | Note/report/allegato contengono richieste di sovrascrivere istruzioni | Dati separati in JSON e guardrail aggiunto al system prompt; prova comportamentale distinta dai controlli di serializzazione, nessuna garanzia assoluta anti-injection |
| C5-12 | Modifica valutazione/snapshot durante cattura e dopo accodamento | Cattura transazionale coerente; il job conserva input congelato/hash della versione catturata, non rilegge dati successivi |
| C5-13 | Confronta hash input, snapshot, system prompt e fonti con contenuti catturati | Hash riproducibili per byte/codec documentati; provenienza include app/prompt version, ID e timestamp cattura |
| C5-14 | Cambia modello/generation/provider tra enqueue e processing | Execution registra configurazione effettivamente letta dal worker, prima del provider; non dichiara modello remoto risolto se non noto |
| C5-15 | Corrompi user_prompt/system_prompt/allegato persistito senza aggiornare hash | Worker fallisce senza provider; nessuna pubblicazione con provenienza incoerente |
| C5-16 | Successo/errore/lease recovery, bootstrap con job terminali vecchi e restore C1 | Input transitori rimossi; hash/provenance/execution conservati. Controllare che non siano cancellati input di job pending/running normali |
| C5-17 | Nuova relazione automatica e salvataggio manuale | Entrambe draft; automatica canonical, manuale manual_unverified; ID valutazioni manuali verificati per appartenenza |
| C5-18 | Leggi relazioni legacy senza nuovi campi | Restano legacy_unreviewed con provenienza non attestata; nessun backfill fittizio di modello/input/versioni |
| C5-19 | Viewer tenta approvazione; admin approva con hash corretto/obsoleto | Viewer403; admin approva solo testo letto corrente, hash obsoleto409; audit e revisore/data atomici |
| C5-20 | Riutilizza report draft/legacy/approved o report modificato dopo approvazione | Solo approved con hash corrispondente entra nel contesto; UI disabilita selezione altri stati; API applica stessa regola |
| C5-21 | UI legge/esporta un report salvato e prova ad alterare testo client | PDF da documento server con stato e fonti; export libero preesistente marcato bozza/provenienza non attestata |
| C5-22 | Elimina valutazione sorgente dopo generazione, poi backup/restore | Provenienza storica con ID/hash conservata; backup ammette fonte eliminata solo con metadati hash validi. Hash non viene presentato come copia ricostruibile dei dati |
| C5-23 | Delete utente concorrente a cattura, enqueue, approvazione o pubblicazione | Vincoli C4 preservati, nessun figlio ricreato; rollback approvazione se parent scompare |
| C5-24 | Permessi C2, limiti1MiB contesto/10MiB allegato, cambio pagina durante conferma, errori provider/log | Niente bypass viewer/system prompt; limiti applicati; nessun setState dopo dispose nel flusso modificato; log/audit senza testo note, prompt o segreti |

I controlli C5 non sono una certificazione legale o di anonimizzazione. I testi liberi, i titoli dei protocolli, le relazioni precedenti e gli allegati possono contenere identificativi: verifica operatore esplicita. Non introdotta retention temporale per report o metadati; pulizia limitata agli input transitori dei job terminali. Totale registro:116 casi C1-C5.


## C6 - Scadenze, date, conteggi e navigazione (4.0.7)

Tutti i seguenti28 casi sono DA ESEGUIRE. Nessun test, analyzer, build o migrazione eseguito durante C6. Preparare dati isolati e orologio controllato; confrontare dashboard/elenco senza scritture concorrenti. I risultati precedenti non attestano questa revisione.

| Caso | Preparazione / azione | Risultato atteso |
|---|---|---|
| C6-01 | Settings assenti o solo alcune durate persistite | Default server12/12/36/12/12/12; valori persistiti conservati; richieste POS/SM/SIS, preavviso30 |
| C6-02 | Admin salva sei durate, subset richieste e preavviso; riapre su altro browser | Valori comuni persistiti e riletti; nessuna dipendenza da SharedPreferences |
| C6-03 | Viewer/operatore chiama POST policy; GET autenticato | Scrittura solo admin; GET disponibile; nessun aggiramento RBAC C2 |
| C6-04 | Durata0/121/bool/stringa, scala ignota/duplicata, elenco vuoto, preavviso negativo, payload malformato |422 senza modifiche parziali o errore500 |
| C6-05 | Vecchio client POST settings omette nuovi campi; query validity_* discordanti | Policy persistita preservata; parametri query ignorati; badge dipendono dal server |
| C6-06 |31 gennaio +1 mese,29 febbraio +12 mesi,31 dicembre | Ultimo giorno del mese target, anno corretto; nessun overflow al mese successivo |
| C6-07 | Giorno scadenza, giorno successivo; warning0/30; limite esatto | Valida/in preavviso durante scadenza, scaduta giorno dopo; soglia warning inclusiva |
| C6-08 | Timestamp equivalenti UTC/offset, cambio ora legale Europe/Rome, confine mezzanotte | Stessa data locale e stato; trend nel mese locale corretto |
| C6-09 | BSON aware/naive, ISO Z/offset, dd/MM/yyyy, dd-MM-yyyy, yyyy/MM/dd | Normalizzazione coerente UTC, naive interpretati UTC, nessun confronto naive/aware |
| C6-10 | Data impossibile/vuota/tipo errato e data futura | Scala incompleta, mai copertura inventata; storico data non interpretabile409; documento non riscritto |
| C6-11 | Nessuna valutazione; solo scala opzionale; richiesta mancante | Mai valutati nel primo caso; incompleti negli altri; categorie esclusive |
| C6-12 | Richieste complete con scaduta e in preavviso; una mancante e una scaduta | Precedenza incomplete > scadute > in scadenza; KPI e filtro stesso insieme |
| C6-13 | Tutte richieste valide, una in preavviso, opzionale scaduta | Coperti include preavviso; opzionale non riduce copertura richiesta |
| C6-14 | Ultima valutazione incompleta dopo precedente valida | Stato incompleto; nessun fallback che nasconda il problema |
| C6-15 | Snapshot valido, scala eliminata/modificata; legacy senza snapshot | Snapshot prevale; legacy usa catalogo corrente dichiarato; GET non inventa snapshot o modifica dati |
| C6-16 | Risposte duplicate/mancanti, SIS invalido, zeri validi | Validazione C3 condivisa: incomplete escluse dalla copertura, zero valido conservato |
| C6-17 | Pi? record stessa data, inserimenti in ordine diverso | Spareggio stabile per _id, ultima data effettiva usata |
| C6-18 | Utenti archiviati, attivo assente, riferimenti legacy all'_id stringa | Attivo assente incluso coerentemente; archiviati esclusi KPI; alias non duplica utenti nella distribuzione |
| C6-19 | Click ciascuno dei quattro alert e due KPI coperti/da completare | Elenco stesso insieme/conteggio su dataset fermo; schema paginazione coerente |
| C6-20 | Pi? compilazioni stessa scala/utente | Totale compilazioni incrementa per record; distribuzione conta utente unico; copertura conta coppie richieste |
| C6-21 | Cambio set richieste da3 a6 o subset diverso | Denominatore aggiornato, nessun vincolo residuo a tre scale nei filtri/KPI; badge tutte sei |
| C6-22 | Oltre5000 utenti,10000 valutazioni,1000 storico,2000 relazioni,100 scale | Nessun troncamento nei percorsi C6; ultima data/relazione trovata; dimensioni risposte osservate |
| C6-23 | Pagina1/2, nomi omonimi, ricerca multiparola combinata con stato/filtro | Ordinamento stabile cognome/nome/id/_id, totale prima del paging; nessun duplicato a dataset fermo |
| C6-24 | Creazione/modifica/delete valutazione e cambio policy a dashboard aperta | Rilettura aggiorna badge e KPI; cache vecchie ultimo_* e dashboard non governano stato |
| C6-25 | Forecast giorno0/7/55/56, scaduta e incompleta | Fasce settimanali corrette, scaduta in criticita, incomplete non diventano appuntamenti; giorno56 escluso |
| C6-26 | UI mobile/desktop, entrambe dashboard, errore rete policy, salvataggio e dispose | Conteggi utenti separati da coppie; badge server, errore visibile, niente salvataggi impliciti o setState dopo dispose |
| C6-27 | Backup/restore C1 con policy nuova e date miste; regressione job/auth con tz_aware | Policy conservata, date supportate coerenti, lease e token C2/C4 senza regressioni |
| C6-28 | Carico su volumi elevati, richieste concorrenti/cambio giorno/policy | Misurare memoria/latency; nessuna promessa di snapshot inter-richiesta; variazioni lecite documentate, valutare proiezione persistita se necessaria |

Totale registro aggiornato:144 casi C1-C6. Restano da pianificare eventuali migrazioni massivamente correttive solo dopo inventario delle anomalie reali. Questi casi non attestano prestazioni o compatibilita runtime prima dell'esecuzione.


## C7 - Sicurezza rete, chiavi, sessioni ed export (4.0.8)

36 casi DA ESEGUIRE. Nessun test/analyzer/build/provider/DB cliente eseguito durante C7. Usare solo dati sintetici, gateway controllati e un volume Mongo isolato. Procedure e residui in SECURITY_OPERATIONS.md. Nessun risultato precedente certifica questa revisione.

| Caso | Preparazione / azione | Risultato atteso |
|---|---|---|
| C7-01 | Preflight PATCH settings/ai da origine ammessa e origine estranea | Metodo ammesso solo per origini configurate; nessuna wildcard o credenziale CORS introdotta |
| C7-02 | Origini/porte dev esplicite, richieste same-origin, viewer PATCH | CORS coerente con env; RBAC resta applicato anche quando il preflight riesce |
| C7-03 | Crea/reset password11/12 caratteri, spazi soli, Unicode oltre72 byte | Rifiuto valori fuori policy, create/update coerenti; UI indica12, API autorevole |
| C7-04 | Login con account storico e nuova password valida | Accesso storico preservato salvo cambio obbligatorio C2; revoca versioni invariata |
| C7-05 | JWT segreto assente/corto/placeholder, durata fuori15..480 e default60 | Avvio rifiutato con configurazione invalida; nuovi exp coerenti; nessun fallback noto |
| C7-06 | Login, reload, chiusura e riapertura scheda, token localStorage pre-C7 | JWT nuovo solo sessionStorage; token persistente cancellato all'avvio; nuovo accesso richiesto dopo chiusura, salvo ripristino sessione del browser |
| C7-07 | Logout,401, cambio password e ruoli tra due schede | Credenziali sessione ripulite nel flusso corrente; DB resta autorevole, metadati UI non concedono diritti |
| C7-08 | GET/POST API, errori403/503, PDF e CSV | Cache-Control no-store/nosniff; nessun caching risposte con dati riservati |
| C7-09 | HTML/JS/assets/API/errori Nginx e iframe altra origine | Header presenti nei location e negli errori; nessuna perdita per ereditarieta add_header; app Flutter e PDF funzionanti |
| C7-10 | Backend uid10001, filesystem readonly, PDF/Matplotlib concorrenti | Nessuna scrittura fuori tmpfs, cache funzionante, cap-drop/no-new-privileges; misurare tmpfs256MiB |
| C7-11 | Connettivita container UI/API/DB e porte host | UI non raggiunge DB tramite rete condivisa, API raggiunge DB; DB senza porte pubblicate; rete data interna |
| C7-12 | Cifratura nuova senza chiave IA, chiave corta e dedicata valida | Nessun fallback JWT/seed, errore esplicito; enc:v2 con key-id e round-trip corretto |
| C7-13 | Leggi enc:v2 con attiva, precedente, mancante, token corrotto e versione ignota | Keyring corretto legge; errori espliciti senza cancellare o sovrascrivere configurazione |
| C7-14 | Enc:v1 da vecchia chiave IA e da JWT corrente/precedente | Lettura compatibile con keyring IA/JWT appropriato; nessuna scrittura nuova v1 |
| C7-15 | Materiali keyring JSON invalidi, ciphertext client mascherato, header vuoto | Errori controllati; maschere non sostituiscono segreti; nessun null invalido nei custom_headers |
| C7-16 | Loader con ai malformato/differentemente tipizzato o chiave non leggibile, plaintext legacy senza chiave attiva; migrazione concorrente a update |409/503, nessun reset a default; CAS preserva modifiche concorrenti, documenti originali conservati |
| C7-17 | Admin rewrap con keyring completo e alcuni segreti non decifrabili | Tutti ricifrati oppure nessuna scrittura; nessun segreto nella risposta/audit |
| C7-18 | Viewer/operatore rewrap, modifica settings concorrente, header vuoto |403; CAS409 senza perdita modifica; mappa header resta validabile |
| C7-19 | Rewrap, rotazione JWT e restore di backup antecedente/successivo | Entrambe le famiglie leggibili con chiavi conservate; chiavi C1 distinte da IA, restore senza chiave fallisce prima delle scritture |
| C7-20 | URL credenziali/query/fragment/backslash/controlli/porte invalide/scope IPv6 | Rifiuto preventivo, niente chiamata o salvataggio endpoint invalido |
| C7-21 | Allowlist host esatto e sottodominio non elencato, lista vuota | Nessuna autorizzazione implicita sottodominio; lista vuota consente solo destinazioni pubbliche HTTPS |
| C7-22 | DNS inesistente, timeout, lista vuota e A/AAAA misti pubblico/privato | Fail-closed; timeout attesa15s; nessun provider raggiunto con indirizzo vietato |
| C7-23 | Loopback, link-local metadata, multicast, reserved, mapped IPv6 e numeri IPv4 alternativi | Sempre negati dopo risoluzione/canonicalizzazione; niente bypass tramite formati alternativi |
| C7-24 | Endpoint LAN RFC1918/ULA con combinazioni allowlist/flag | Consentito solo con nome esatto e ALLOW_PRIVATE_AI_ENDPOINTS; altri non-global negati |
| C7-25 | HTTP pubblico, HTTP LAN con/senza flag, HTTPS con certificato errato | HTTP pubblico negato; LAN richiede tutti i consensi; TLS invalido mai accettato |
| C7-26 | DNS restituisce pubblico alla validazione e privato prima della richiesta | Controllo al trasporto blocca la richiesta; nessuna nuova risoluzione hostname dopo pin IP |
| C7-27 | Server TLS controllato con Host virtuale e SNI, A/AAAA multipli | Host/SNI originali, socket all'IP validato; certificato verificato; fallimento primo IP non causa replay automatico |
| C7-28 | Redirect verso rete interna, HTTP_PROXY/HTTPS_PROXY/ALL_PROXY malevoli | Nessun redirect o proxy d'ambiente seguito, chiavi non consegnate al proxy |
| C7-29 | Generate/test/models e fallback /v1/models, custom Host/proxy/Authorization | Tutti passano dal trasporto; header di instradamento vietati; Authorization senza duplicati di case |
| C7-30 | Worker C4, errori DNS/provider e cancellazione durante risposta | Nessun retry aggiuntivo nel worker, pulizia input e provenienza C5 preservate; no valori segreti negli errori |
| C7-31 | CSV admin/viewer/operatore, licenza valida/scaduta | Solo admin con vincolo licenza preesistente; pulsanti altri ruoli disabilitati, audit avvio senza dati di riga |
| C7-32 | Celle =,+,-,@, prefissi spazi/tab/CR/LF/Unicode, virgolette/semicolon/accenti | Nessuna formula attiva in foglio isolato; escaping CSV/BOM/Unicode corretti; DB immutato |
| C7-33 | CSV oltre100 scale/utenti e date miste, anagrafiche archiviate, download interrotto | Date C6 complete e normalizzate, inclusione archiviate esplicita come export globale; memoria a lotti, stream interrotto non dichiarato completato |
| C7-34 | Provision su replica set isolato: utenti assenti/esistenti/ruoli o credenziali discordanti | Utenti distinti creati; esistenti mai reimpostati; conflitti rifiutati; nessun segreto nei log |
| C7-35 | Overlay auth con keyfile assente/permessi corretti, URI app e root health | Configurazione incompleta fallisce; primary autenticato; accesso senza credenziali negato, app limitata ad autanalysis |
| C7-36 | C1 backup/restore, indici C2/C3, transazioni e worker C4 sul Mongo autenticato; recupero isolato | Permessi app sufficienti senza root, volumi preservati, recupero documentato; deploy sempre con overlay, niente downgrade silenzioso |

Totale registro aggiornato:180 casi C1-C7. ASTRA-16 resta parzialmente aperto per attivazione Mongo auth e residui sessione/CSP esplicitati in SECURITY_OPERATIONS.md; test e rilascio rinviati. Il Compose base resta legacy senza auth, con isolamento di rete: non equivale ad autenticazione attiva.


## C8 - Audit, PDF, licenze e rilascio (4.0.9)

40 casi DA ESEGUIRE. Nessun test/analyzer/installazione pacchetti/render PDF/build/CI/deploy eseguito durante C8. Manifest e digest preparati da metadati, non da un ambiente collaudato. Usare replica set e dati sintetici; le fixture dei cluster precedenti vanno adeguate agli audit transazionali senza rimuovere le asserzioni di sicurezza.

| Caso | Preparazione / azione | Risultato atteso |
|---|---|---|
| C8-01 | Mutazione autenticata e lettura registro | Evento con attore reale, azione/target, timestampUTC, app_version, event_id/correlation_id; header correlazione generato dal server |
| C8-02 | Header correlazione arbitrario client, due richieste concorrenti, job completato dopo richiesta | Identificatori server isolati; enqueue/pubblicazione job condividono correlazione originaria; nessun contesto di altro utente |
| C8-03 | Create/update/delete valutazione con audit indisponibile | Rollback dati e audit, nessun successo non tracciato; retry non produce doppia compilazione |
| C8-04 | Import POS/SM/SIS, update/delete protocollo con legacy senza snapshot | Evento e freeze C3 nella stessa transazione; rollback completo su errore audit; hash versione corretta |
| C8-05 | Create/update/delete anagrafica durante pubblicazione job | Audit atomico, write_revision preservata; nessun dato figlio ricreato C4 |
| C8-06 | Create/update/delete operatore e cambio password con errore audit | Nessun cambiamento account/hash/epoch senza evento; CAS e revoche C2 preservati |
| C8-07 | Settings legacy/IA/policy/rewrap mentre si accoda un job | Evento atomico, nessun overwrite dei contatori interni settings; segreti non in log |
| C8-08 | Bozza manuale, modifica note, approvazione hash e delete report | Eventi atomici con soli metadati; report e note completi mai copiati nel registro |
| C8-09 | Snapshot legacy ricostruito da GET analisi/PDF | Evento sistema esplicito con hash e provenienza dichiarata; no falsa versione originale |
| C8-10 | Job enqueue/success/failure e restore C1 | Audit parte della transazione; parent/id/provenienza preservati; eventi ripristinati senza backfill inventato |
| C8-11 | Audit guasto dopo login/export/operazione remota licenza | Risultato gia concluso non trasformato in errore retryable; X-Audit-Status degraded e correlation, log generico senza segreti |
| C8-12 | Flutter riceve degraded same-origin/cross-origin | Avviso visibile e intestazioni esposte CORS; nessuna ripetizione automatica della modifica |
| C8-13 | Registro via API e selezione diretta UI come viewer/admin | Viewer403 e nessun caricamento contenuto; admin accede; errori lettura non diventano lista vuota |
| C8-14 | Limite0/1001, offset negativo, timestamp uguali e pagine successive |422 fuori range; ordine timestamp/_id stabile, default200 esplicito |
| C8-15 | Backup/restore eventi storici e nuovi; osserva retention | Campi nuovi preservati, vecchi non arricchiti con prove fittizie; nessuna TTL/cancellazione introdotta |
| C8-16 | Note/nome/scala/opzioni contenenti &,<,>,tag img/a/font, markup malformato | Testo fedele e inerte nel PDF, nessuna risorsa arbitraria o errore parser |
| C8-17 | Intestazione organizzazione e metadati/intervistato con caratteri speciali | Escape uniforme, layout e righe leggibili; controlli XML gestiti |
| C8-18 | Markdown IA con immagini/link HTML, liste/tabelle e Unicode | Sottoinsieme Markdown leggibile; contenuti HTML escapati, niente caricamenti remoti/locali |
| C8-19 | POS snapshot con testo/opzione diversa dal bundled, codice presente in entrambi | PDF usa solo lo snapshot; domande mancanti non inventate dal file corrente |
| C8-20 | Snapshot SM/SIS completo/incompleto/legacy dopo modifica/delete scala | Contenuto e tabelle storiche coerenti con C3; warning e soppressione indici C3 preservati |
| C8-21 | PDF simultanei con nomi/scale differenti | Figure e layout isolati, nessuna mescolanza tra documenti o stato pyplot condiviso |
| C8-22 | Saturazione2 posti, terza richiesta oltre5s, cancellazione client |503 Retry-After5; slot non liberato finche thread finisce; nessuna crescita non limitata di render concorrenti |
| C8-23 | Report libero oltre1M caratteri, note molto lunghe, tmpfs256MiB | Limite API422; misurare memoria/layout e paginazione, errori controllati; nessuna promessa di timeout esecuzione |
| C8-24 | Esporta PDF relazione approved/draft/manuale e confronto visivo tutte scale | Stato/provenienza C5 corretti, intestazioni/righe/grafici leggibili senza tagli; nessuna norma scientifica modificata |
| C8-25 | Pi? bootstrap trial concorrenti e duplicati legacy licenses.id | Un singleton creato, duplicati storici segnalati senza scelta/cancellazione automatica |
| C8-26 | Viewer forza remoto, admin forza remoto, viewer aggiorna schermata |403 al tentativo viewer; UI viewer usa cache; admin puo forzare |
| C8-27 | Richieste stato simultanee con cache scaduta o force_remote | Single-flight per processo, aggiornamento recente riutilizzato; CAS tra processi non sovrascrive stato piu recente |
| C8-28 | Validazione remota ritardata mentre si attiva/disattiva o ripristina licenza |409 su stato cambiato; nessuna perdita della nuova licenza; risposta segnala esito remoto potenzialmente gia avvenuto |
| C8-29 | Lifetime attiva, verifica ordinaria e forzata, offline/risposta revocata | Policy offline lifetime invariata salvo forzatura admin; protocollo centrale immutato |
| C8-30 | Cache/grace con scadenza, timestamp futuro, rete assente, envelope non autenticabile | Nessuna estensione da timestamp futuro; grace solo valida e nei limiti; payload non autenticato non considerato vero |
| C8-31 | Disattiva licenza prima/dopo fine trial originale; created_at mancante | Nessun nuovo trial15gg; solo residuo originario, o scadenza immediata se origine assente; instance_id invariato |
| C8-32 | Licenza scaduta: admin scarica backup da schermata bloccante, viewer tenta; restore manutenzione | Recupero C1 admin disponibile; viewer negato, operativita non riaperta; restore conserva requisiti manutenzione/chiavi |
| C8-33 | Avvio con DB non raggiungibile, standalone, primary/nonprimary e Mongo autenticato | Readiness503 se prerequisiti transazionali mancano,200 primary; liveness distinta, frontend attende health |
| C8-34 | Build con immagini/digest registrati e confronto BUILD_VERSIONS.json | Nessun tag stable/alpine mobile nei FROM, builderFlutter3.41.9 e lock coerenti; compatibilita da provare |
| C8-35 | Installazione lock runtime44/test49 in LinuxPython3.11 pulito, artefatto/hash alterato | Versioni esatte e dipendenze compatibili, solo wheel; hash errato rifiutato. Non usare hostPython3.14 come prova |
| C8-36 | Pubget enforce-lockfile con lock preservato e lock volutamente incoerente | Nessuna risoluzione silenziosa di altre versioni; fallimento esplicito su incoerenza |
| C8-37 | Controlla trigger CI e avvio manuale senza build_images | Nessuna esecuzione automatica push/PR; backend+subsetFlutterVM+compilazione web; niente immagini pubblicate/deploy |
| C8-38 | Pipeline con test fallito e con build_images dopo verifica riuscita | Fallimento blocca job immagini; successo produce archivio/hash/commit/image-id/lockhash, non equivale a copertura di tutti i casi o suite browser |
| C8-39 | Rollout isolato tramite release override e overlay Mongo auth con --no-build --pull never | Solo immagini verificate, nessun build/pull implicito; stessi volumi e auth, smoke funzionale oltre readiness |
| C8-40 | Rollback immagini e scenario dati/segreti non leggibili dal vecchio codice | Ripristino applicativo distinto dai dati; nessuna cancellazione volume o downgrade auth; piano restore C1 isolato con chiavi e backup preservati |

Totale registro aggiornato:220 casi C1-C8. Restano verifiche browser/visive/carico, compatibilita manifest e pipeline; C7 operativo documentato in SECURITY_OPERATIONS.md. Nessuna dichiarazione di rilascio riuscito o chiusura dei rilievi basata sulla sola preparazione.
