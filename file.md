# C1 — Registro operativo e punto di ripresa

Data: 2026-10-29. Mandato: implementare C1 (ASTRA-02/03) e tenere traccia qui di ogni punto. Repository base 9dc15b5acd50167fb3f81fd8d080a2f5546f6c06; audit_astra.md preesistente non versionato da preservare. Nessuna delega ad altri agenti.

## Stato
FIX C1-C6 IMPLEMENTATI — verifica finale rinviata su richiesta utente. Stato corrente nel checkpoint 15 in fondo; i precedenti sono cronologia. Test differiti centralizzati in test.md.

## Evidenze ricontrollate
- Mongo Compose attuale standalone: non supporta transazioni multi-documento. Un ciclo delete/insert con compensazione non garantisce atomicità dopo crash.
- 10 collection, mapping export/import ne include 8; vuoti ignorati; codec default=str; 5 MiB import contro export illimitato.
- Chiave backup derivata da JWT, nessun identificatore/formato cifratura versionato; credenziali IA cifrate con chiave distinta o JWT.
- Docker Desktop installato ma daemon non raggiungibile. Verificare possibilità test Mongo isolato; non toccare dati/volumi utente.
- UI import/export da settings e api_service; test esistenti controllano autorizzazioni e input malformato ma non rollback reale.

## Piano per punto
1. ASTRA-02: transazione atomica vera, validazione completa prima della scrittura, collezioni vuote, rollback/errori e concorrenza; requisito replica set esplicito e configurazione riproducibile. Nessun fallback distruttivo su standalone.
2. ASTRA-03: registro unico collection, formato versionato Extended JSON/BSON, versione app affidabile, limiti simmetrici, chiave backup dedicata con identificatore e compatibilità legacy, controlli chiavi IA e identità licenza.
3. UI/operatività: messaggi coerenti, procedura manutenzione/restore e recupero, dati sintetici nei test.
4. Verifiche: unità/endpoint, Mongo reale isolato se disponibile, suite backend e analisi/build frontend pertinenti. Documentare limiti senza dichiarare end-to-end non provato.
5. Aggiornare audit/architettura/changelog e questo registro; nessun deploy né uso di database reale cliente.

## Decisioni ancora da finalizzare
- Protezione da job IA in volo durante restore: manutenzione avviata con restart per impedire nuovi job e vecchi task del processo, mantenendo login/settings/backup accessibili.
- Ripristino licenza: recupero stessa istanza, vietare sovrascrittura identità commerciale diversa; clone non implica duplicazione licenza.
- Formato legacy: accettare solo backup completi delle collection storiche, reidratare campi data noti e rifiutare ambiguità; non preservare silenziosamente collezioni assenti.

## Prossima azione
Leggere questo file e audit_astra.md all'eventuale rinnovo contesto. Rispettare il checkpoint 3: niente test, analisi statiche o build finché l'utente non richiede la fase di verifica.

## Checkpoint implementazione 1
- git pull --ff-only origin main: già aggiornato.
- Aggiunti backup_service.py (Extended JSON canonico, envelope AES-GCM v2 con key id, keyring legacy, validazione, snapshot e transazione restore), maintenance.py e registro collection in database.py.
- Router backup ora delega al servizio; no fallback delete/insert standalone.
- Compose predisposto replica set singolo autify-rs con healthcheck idempotente e variabili backup. Il volume autify_data non è rinominato né cancellato.
- Ripristino: revoca sessioni con nuova epoca token_version, pending/running riportati a failed con spiegazione; nessuna riemissione automatica provider. Licenza commerciale di istanza diversa bloccata.
- UI in corso: errori backend leggibili, limite64MiB, conferma e ritorno login.
- Docker Desktop avviato; SOLO container di test autify-c1-audit-20261029, Mongo8.0.4, localhost:27091, volumi temporanei Docker --rm. Non avviato stack reale.
- DA FARE: test validazione, round-trip Mongo reale/rollback e snapshot, errori rete/commit, indice/licenza/keyring; docs operazioni e aggiornamenti release/audit. Rivedere schema per evitare validazioni che accettino tipi poi inutilizzabili.

## Checkpoint verifiche 2
- Suite backend completa con Mongo reale isolato: 118 passed (prima estensione test), 94 warning preesistenti/deprecazioni. Inclusi errori in tutte le 10 collection, errore indice unique reale, snapshot con scrittura concorrente, restore DB vuoto e vuoti/chiavi/sessioni/job.
- Prima esecuzione: 40 passed/1 failed; rilevato BSON Int64 non accettato dal controllo type(...)=int. Corretto per accettare int/Int64 ed escludere bool; nuova suite118 tutta verde.
- Flutter analyze --no-pub --no-fatal-infos: exit0, 21 deprecazioni preesistenti. Riformattazione collaterale settings ridotta: mantenuti soltanto blocchi backup, testo e conferma.
- VERSION aggiornata4.0.3 e propagata da bump_version.py, ora genera anche backend/app/version.py copiato dal Dockerfile.
- Aggiunti ulteriori test cancellazione e HTTP export/import; da eseguire. Build Flutter in corso session39919.
- Da completare: documentazione manutenzione/migrazione e limiti; verifica Compose in stack isolato; gestione esito commit incerto; test schema date/licenze finali; pulizia container test e aggiornamento stato audit.

## Checkpoint 3 — stato corrente e istruzioni di ripresa

**Mandato aggiornato:** l'utente ha chiesto di concentrarsi sui fix e rimandare i test. Da questa indicazione non sono stati eseguiti altri test, analisi statiche o build. Non avviare automaticamente la fase di verifica al rinnovo contesto. Le prove del checkpoint 2 riguardano una revisione intermedia.

### Interventi implementati per punto

- **ASTRA-02 / atomicità:** restore delle dieci collection, inclusi vuoti e audit, in una sola transazione MongoDB snapshot/majority; standalone rifiutato. Validazione preventiva e verifica identità licenza. Connessione persa/esito commit incerto segnalati senza suggerire retry automatici.
- **ASTRA-02 / concorrenza e sessioni:** manutenzione dopo restart, un solo processo backend, stop writer esterni; middleware serializza richieste consentite. Nuova epoca token int64 per ogni account, job pending/running convertiti in failed. La manutenzione non è un lock distribuito.
- **ASTRA-03 / completezza e tipi:** registro BACKUP_COLLECTIONS, dieci collection, export snapshot, BSON Extended JSON canonico, rifiuto collection live sconosciute, versione generata dal file VERSION. Import/export limitati a 64 MiB; Nginx65MiB per multipart.
- **ASTRA-03 / chiavi:** AES-GCM v2 con header autenticato e key id, chiave backup dedicata, keyring precedente e lettura ENC legacy con vecchi JWT. Controllo decifrabilità configurazione IA prima delle scritture.
- **Compatibilità legacy:** conversione otto collection storiche, date note a UTC, nuove collection vuote. Corretto per revisione manuale un bug di doppia validazione: il documento migrato ora espone schema_version=2 e database=autanalysis, così decode e restore accettano lo stesso risultato.
- **Validazione difensiva:** tipi Pydantic strict senza coercizioni scartate, date obbligatorie, hash password stringa/formato bcrypt, flag account booleani, token commerciale stringa e riferimenti opzionali tipizzati. Nessuna normalizzazione arbitraria dei dati incoerenti.
- **UI/API:** conferma sostituzione archivio, errori dettagliati, logout dopo successo; timeout include anche attesa header/invio e avverte di verificare esito. API backup admin accessibili a licenza scaduta; CSV resta soggetto a licenza. La UI mantiene il gate licenza: recupero via API amministrative quando necessario; audit via Mongo in sola lettura se gate impedisce consultazione.
- **Documentazione:** aggiunto BACKUP_OPERATIONS.md; aggiornati audit_astra.md, CHANGELOG.md, ARCHITECTURE_MAP.md e REMEDIATION.md. Versione locale4.0.3. DATA-01 implementato ma non chiuso come validato.

### Verifiche storiche e limiti attuali

- La build Flutter citata come in corso nel checkpoint 2 è terminata con exit0 prima del cambio strategia. Anche compose config era passato sulla revisione intermedia. Non sono prove della revisione attuale.
- Gli ultimi cambi a schema/date, registro collection, esito incerto, gate licenza, migrazione legacy e timeout NON sono stati eseguiti né testati. I nuovi scenari nei file test esistono ma restano rinviati; non aggiunti altri test dopo la richiesta.
- Svolta soltanto lettura/revisione del codice e `git diff --check` (nessun errore whitespace), non validazione funzionale.
- L'avvio automatico replica set Compose era stato lanciato in ambiente isolato prima della richiesta, ma la verifica finale del suo health/bootstrap non è stata completata. Migrazione del volume di una precedente installazione non eseguita.
- Pulizia completata: fermato/rimosso container usa-e-getta autify-c1-audit-20261029; rimosso solo progetto sintetico autify-c1-verify con il suo container, rete e volume autify-c1-verify_autify_data dopo controllo delle etichette. Nessun volume cliente eliminato. Docker Desktop lasciato disponibile.
- Nessun deploy, nessuna modifica al database cliente, nessun commit/push. Non considerare 4.0.3 distribuita.

### Mappa per riprendere

`database.py` registro → `backup_service.py` codec/chiavi/validazione/tx → `routers/backup.py` auth e upload → `main.py` gate licenza e `maintenance.py` → Compose/env/Nginx → `api_service.dart`/`settings_screen.dart`. `VERSION` → `bump_version.py` → `app/version.py` e versioni frontend/backend. I test preparati sono `backend/tests/test_backup_service.py` e `test_backup_integration.py`.

**Prossimo passo quando autorizzata la fase test:** verificare revisione finale, soprattutto decode→restore legacy, tipi strict con dati reali anonimizzati, vincoli/rollback/cancellazione/commit incerto, snapshot concorrente, gate admin/licenza, manutenzione con UI e migrazione standalone su copia isolata. Prima del deploy occorrono chiavi custodite, backup infrastrutturale e finestra di manutenzione secondo BACKUP_OPERATIONS.md. Per altri fix seguire i cluster dell'audit senza allargare implicitamente C1.


## Checkpoint 4 - 30 ottobre 2026, test.md e fix C2

Mandato: PRIMA centralizzare i casi C1 in test.md, POI procedere C2. Eseguito in questo ordine. Nessun test, analisi statica, build o avvio applicativo: soltanto lettura/revisione, modifiche e controllo whitespace del diff. Nessun nuovo test eseguibile C2: i casi da realizzare sono nel registro centrale.

- **test.md:** 29 casi C1 e 21 C2 con preparazione, azioni e risultati attesi; tutti DA VERIFICARE sulla revisione finale. File.md conserva il contesto, test.md governa la futura campagna test.
- **ASTRA-10 bootstrap:** auth.ensure_default_admin senza fallback; INITIAL_ADMIN_PASSWORD esplicita (>=12 caratteri, <=72 byte), inoltrata da Compose e documentata in .env.example. DB popolato preservato; race protetta da indice unique/DuplicateKeyError. Vecchio admin/admin marcato must_change_password all'avvio e login, incluso dopo restore. Non cambiata .env locale, nessun segreto stampato.
- **ASTRA-10 sessioni:** auth.verify_auth richiede sub/exp/iat/token_version, confronta epoca, legge ruolo/flag dal DB. Account con cambio obbligatorio limitato a POST /api/admin/auth/change-password tra le API protette. Altri percorsi403 con codice password_change_required. Token storici senza versione richiedono nuovo login.
- **Cambio personale:** payload vieta extra, verifica corrente, nuova>=12char/<=72byte/diversa e conferma; compare-and-swap hash/versione evita sovrascritture concorrenti. Audit senza segreti, flag azzerato, token_version incrementato e nuovo login. Policy precedente creazione/reset amministrativo altri account invariata.
- **UI sessione:** dialog con conferma usa endpoint personale; successo pulisce sessione e ricarica login. Flag obbligatorio persistito per refresh e 403 gestito nel client. Auto-modifica admin password/ruolo/flag riporta al login. Multipart convertito a Response per leggere il corpo errore.
- **ASTRA-08 IA viewer:** payload omette system_prompt per non-admin, API rifiuta override anche vuoto; doppio flag preservato. GET settings/ai solo admin; GET ai/capabilities restituisce provider/model/configured/can_analyze senza prompt/URL/header/hint chiavi. GET settings viewer senza gemini_prompt. Schermata multidimensionale usa capabilities.
- **ASTRA-08 notifiche:** eccezione wrapper solo POST notifications/{id}/read e notifications/read-all; filtri username mantenuti negli handler. Permesso nuova generazione non necessario per leggere notifiche pregresse. Altre scritture viewer bloccate.
- **Interconnessione C1:** cambio personale consentito e serializzato in manutenzione, esente gate licenza attraverso router auth. Account ripristinati con flag devono cambiarla prima di altre API. Nessuna nuova collection.
- **Versione/docs:** VERSION4.0.4 propagata tramite bump_version.py (generazione, non build/test). AUTH_OPERATIONS.md nuovo; aggiornati changelog, architettura, remediation, operazioni backup e audit. C1 4.0.3 resta riferimento storico, stack locale corrente4.0.4.

### Ripresa e limiti

Leggere questo checkpoint, test.md e audit appendice C. Nessun deploy/commit/push o DB reale toccato; preservate modifiche C1 locali. Revisione a lettura non certifica runtime Python/Dart o flusso browser. Non avviare test senza successiva richiesta. In seguito usare vere dipendenze auth/RBAC/licenza e verificare C1+C2 insieme, adeguando fixture al contesto token_version. Aggiornare frontend/backend insieme: vecchio client incompatibile con cambio obbligatorio e settings IA viewer. Job in corso restano C4, provenienza IA C5. Centralizzare anche futuri casi C3-C10 in test.md.


## Checkpoint 5 - C3/C4 in corso, 30 ottobre 2026

Mandato: stesso procedimento, fix C3 (ASTRA-01/04/05) e C4 (ASTRA-09/11), casi differiti in test.md, nessun test/analyzer/build. Decisioni: nuove valutazioni complete, nessun nuovo workflow bozza implicito; snapshot originale prioritario, legacy ricostruito dalla scala corrente con provenienza dichiarata, mai spacciato per originale. Worker persistito con claim/lease, bounded concurrency e pubblicazione atomica; running interrotto non riemette automaticamente richieste a pagamento. Delete coordinato tramite transazione e scrittura sul documento utente condivisa con enqueue/publicazione. Tutto in corso, non considerare ancora completato.


## Checkpoint 6 - C3/C4 implementati localmente, versione4.0.5

Mandato e confini: C3 ASTRA-01/04/05 e C4 ASTRA-09/11. Nessun test, analisi statica, build o esecuzione applicativa effettuata; solo lettura, modifiche e git diff --check. VERSION propagata via bump_version.py (generazione file). Test differiti in test.md:20 casi C3 +22 C4, oltre29 C1 e21 C2; totale92. Nessun nuovo file test eseguibile C3/C4.

### C3 per punto

- ASTRA-01: estratto scale_import.py, importato da settings.py; input malformato422 e salvataggio scala via save_scale transazionale. Metadata extra non possono sostituire sezioni/_id.
- ASTRA-04: evaluation_contract.py risolve snapshot; nuovi snapshot completi con hash/provenienza server. Legacy senza snapshot congelato da scala corrente e marcato legacy_current_not_original. Nessuna attestazione originale inventata; senza scala o con snapshot corrotto409. Save/import/delete scala congela legacy nella stessa transazione; create scrive anche sul documento scala per conflitto corretto.
- Lettori collegati: PDF, analysis, aggregati e update backend; AggregatedEvaluation include snapshot_scala, dettaglio Flutter risolve domande/opzioni per selezione. Nuova API patients/{id}/evaluation-scales include scale eliminate ma presenti nello storico; usata dal profilo multidimensionale, non dal catalogo nuove compilazioni. UI/PDF segnalano legacy ricostruito.
- ASTRA-05: validatore condiviso richiede tutte le risposte una sola volta, alias canonici, tipi strict, punteggi nelle opzioni, SIS F/D/T0..4 con A3F<=3, nucleo49item dalla fonte locale; compositi conteggio0..N. Nuovo indice unique parziale stringa su id_valutazione; duplicati legacy bloccano l'indice senza eliminazione automatica.
- No workflow bozza introdotto: nuove create/update complete; legacy parziale conservato senza indici standard e con avviso. Wizard filtra chiavi ausiliarie checklist e consente zero esplicito; editor usa range composito. Non cambiate tabelle normative, policy scadenze resta C6.
- Backup C1 accetta valutazione con scala eliminata soltanto se snapshot strutturalmente valido e id coerente. Nuova data lease inclusa nel codec.

### C4 per punto

- ASTRA-09: job_worker.py, polling2s dal lifespan; niente create_task per singola richiesta. Pending persistito con versione proprietario e identita Mongo parent, claim atomico con lease900s. Una esecuzione/processo, massimo2 running globali e200 pending tramite contesa transazionale su settings.global_settings. Nessuna collection nuova.
- Prima del provider ricontrollo account/flag/sessione e anagrafica attiva/identita parent. Provider timeout650s e max_retries=0 per evitare replay ambiguo. Pending dopo restart recuperabile; running scaduto o legacy senza lease diventa failed/incerto, mai riaccodato. Pending legacy senza versione proprietario verificabile fallisce senza invio.
- Risultato, completed/failed, notifica e audit in una transazione; ID output deterministici, filtro status+lease per pubblicazione. Input transitori rimossi solo su terminalizzazione del worker. DB failure dopo provider non richiama provider: se risposta non persiste, recovery segnala esito incerto; non garantito exactly-once remoto.
- ASTRA-11: delete utente con valutazioni/relazioni/job/notifiche e audit atomico. Enqueue, create/update valutazione, relazione manuale e pubblicazione toccano parent per conflitto col delete. Identita Mongo evita attribuzione a nuovo record riusando lo stesso id applicativo. Pubblicazione tardiva non ricrea job/figli eliminati.
- Worker cancellato allo shutdown; non avviato in manutenzione C1. Restore continua a trasformare pending/running in failed. Archiviazione attivo=false preserva dati, blocca nuove esecuzioni ma non annulla provider gia chiamato; nessun TTL/retention inventato.

### Evidenze esterne preservate e ripresa

Alla ripresa richiesta dall'utente rilevati test_resul.md con risultati C1 di altra attivita, modifiche frontend_admin/pubspec.lock e .flutter-plugins-dependencies e HEAD diverso dal baseline iniziale. File preservati, nessuna attribuzione di quelle esecuzioni a questo lavoro o alla revisione finale C3/C4. Nessun reset, pull distruttivo, commit/push/deploy o DB cliente toccato.

Documenti aggiornati: test.md, audit appendice D, CHANGELOG, ARCHITECTURE_MAP, REMEDIATION, BACKUP_OPERATIONS; nuovo EVALUATIONS_JOBS_OPERATIONS.md. Leggere questo checkpoint e test.md per ripresa. Tutti i fix C1-C4 attendono verifica finale; non avviare test automaticamente finche non richiesti. Prima rilascio verificare replica set, indici con dati legacy, concorrenza vera e UI completa. C5 (provenienza canonica valutazioni IA), C6 (KPI/date), C7-C10 restano aperti. Orfani/duplicati preesistenti richiedono inventario e riparazione separata; nessuna bonifica distruttiva automatica.

Revisione finale UI C3: quando validation_message presente, dashboard indici/alert e grafici standard vengono omessi; resta avviso con dettaglio risposte. Nessuna rappresentazione di alert assente per protocollo incompleto. Diff whitespace ricontrollato, nessuna esecuzione funzionale.


## Checkpoint 7 - C5 in corso

Perimetro ASTRA-07/15. Implementati ai_context.py (fonti da ID, appartenenza, snapshot C3, transazione di cattura, analisi per ogni valutazione, JSON conserva zero, minimizzazione), payload Flutter solo ID, conferma invio contenuti liberi, provenance/hash persistiti, execution config registrata dal worker. Nuove relazioni draft; approvazione admin legata a hash report, UI e PDF da documento server; solo relazioni approvate riutilizzabili. Legacy/manuali non promossi a provenance canonica. Pulizia prompt/allegati terminali al bootstrap/restore. Ancora da completare revisione collegamenti, test.md/docs/versione. Nessun test/analyzer/build eseguito, file esterni preservati.


## Checkpoint 8 - C5 implementato localmente, versione4.0.6

ASTRA-07/15 implementati. Nessun test/analyzer/build/provider eseguito; solo revisione per lettura e git diff --check. Nuovi24 casi C5 in test.md, totale116 C1-C5. Nessuna nuova collection, nessun deploy/commit/push/DB cliente toccato. Preservati test_resul.md e lockfile esterni.

- ai_context.py: cattura transazionale da id_paziente/evaluation_ids/history_report_ids, appartenenza verificata; snapshot C3 e validazione completa, analisi per ciascuna valutazione. Vecchi payload patient/evaluations/history_reports rifiutati422. ID legacy non migrati richiedono migrazione esplicita. Congelamento legacy C3 conservato come provenienza dichiarata.
- ASTRA-07: client invia solo ID, rimosso dal percorso invio il fallback analyses[idScala]; cache analisi ultima scala resta solo per grafici locali. Job usa dati catturati, non stato successivo. provenance registra ID/hash fonti/snapshot, timestamp, app/prompt version, input/system/attachment hash. Il worker verifica hash e registra execution effettiva (provider/modello richiesto/generation/network/protocollo/hash endpoint) prima dell'invio; credenziali non persistite nella provenienza.
- ASTRA-15: JSON preserva0/false/null e distingue protocollo da analisi. Esclusi nome/cognome/CF/data nascita/note anagrafiche/demographics/operatore/note risposta dal payload strutturato. Note aggiunte/report/allegati solo con conferma esplicita UI/API; non anonimizzati automaticamente. Filename generico, guardrail dati vs istruzioni; nessuna garanzia assoluta anti-injection o conformita legale.
- Relazioni nuove draft; manuali manual_unverified, legacy legacy_unreviewed senza backfill inventato. Approve endpoint admin con hash testo e audit transazionale, revisore/data; solo approved con hash coerente riutilizzabile. PDF salvato legge server e mostra stato/fonti; vecchio export libero marcato bozza. Campo notes modificabile non cambia report originale e non viene incluso implicitamente nel contesto successivo.
- C4: pending pre-C5 senza provenance falliscono senza chiamata; success/failure preservano metadata e puliscono input. Bootstrap rimuove prompt/allegati solo da completed/failed. C1 restore rimuove input transitori, supporta reviewed_at e fonti eliminate con hash storico. Nessuna retention TTL introdotta, backup precedenti non riscritti. Hash non consente ricostruzione di input ormai eliminati.
- Versione4.0.6 propagata da VERSION tramite bump_version.py. Aggiornati audit appendice E, changelog, architettura/remediation; nuovo AI_PROVENANCE_OPERATIONS.md. Documentare/validare limiti1MiB contesto,100 valutazioni,50 report e10MiB allegato.

Ripresa: leggere checkpoint8 e test.md C5. Prima rilascio verificare integrazione C1-C5, aggiornare client/server insieme e adeguare vecchie fixture che usavano payload completo o builder rimosso. Test precedenti non attestano questa revisione. C6-C10 restano aperti; non eseguire test finche la fase non viene richiesta dall'utente.


## Checkpoint 9 - C6 in corso (2026-10-30)

Implementati expiry.py (policy unica, calendario Europe/Rome, stati per scala e utente, validazione C3), elenco paginato dopo filtro semantico stabile, dashboard sulla stessa proiezione, indicatori Flutter da server, editor policy condivisa (sei durate e scale richieste). Rimossi limiti silenziosi nelle letture coinvolte; Mongo tz_aware. Nessun test/analyzer/build eseguito. Restano revisione finale, docs/test.md, versione. Default durate server preservati 12/12/36/12/12/12; tre scale richieste POS/SM/SIS come precedente dashboard, ora configurabili. Nessuna migrazione dati effettuata. Da validare con struttura le durate/policy prima del rilascio. Conteggi calcolati al momento della richiesta, non snapshot storico tra richieste; possibili variazioni per scritture concorrenti.


## Checkpoint 10 - C6 implementato localmente, versione4.0.7

Stato di ripresa: C1-C6 implementati nel perimetro documentato; verifica finale rinviata per richiesta utente. C7-C10 aperti. Nessun test, analyzer, build, avvio app, provider o migrazione DB eseguito in C6. Solo lettura del codice, editing e git diff --check. Nessun commit/push/deploy. File di altre attivita preservati.

1. expiry.py: policy unica da global_settings, sei durate, required_scale_types, warning. Default server12/12/36/12/12/12, richieste POS/SM/SIS; nuove API GET/POST expiry-policy con scrittura admin, audit. Vecchio POST settings preserva campi omessi. I parametri query validity_* restano deprecati e ignorati. Validazione tipi/intervalli, nessun nuovo valore clinico inventato.
2. Date: timezone Europe/Rome, mesi calendario con clamp fine mese, valida per tutto il giorno di scadenza; warning inclusivo. Parser UTC condiviso supporta ISO/BSON e tre formati data legacy; naive assunto UTC. Mongo tz_aware, Evaluation normalizza UTC. Nessuna migrazione fisica di documenti. Date invalide/future segnate incomplete, storico invalido409.
3. Completezza: ultima valutazione per scala determinata per data e _id; data invalida prioritaria per non nascondere anomalie. Validazione C3 su snapshot, legacy su catalogo corrente esplicitamente dichiarato; nessuna scrittura snapshot in GET. Cache ultimo_* compatibile ma mai autorevole per filtri. Richieste/opzionali distinte.
4. Filtri e KPI: stessa proiezione e precedenza mai_valutati/incompleti/scaduti/in_scadenza/coperti. Filtri coperti (include preavviso) e da_completare, KPI in entrambe dashboard su numero utenti; grafico su coppie utenti attivi/scale richieste. Totale valutazioni ora conta compilazioni, distribuzione utenti unici con alias canonici, trend Europe/Rome. Cache5min non letta; richieste distinte possono cambiare per scritture/giorno/policy.
5. Limiti: nessun taglio100/1000/2000/5000/10000 nei percorsi scadenze modificati; cursor per ogni blocco500 ID, pagina stabile cognome/nome/id/_id dopo filtro; ultimo report IA per timestamp normalizzato. Storico completo non paginato e dashboard/filtri O(dati): test di carico indispensabili, eventuale proiezione persistita futura, non dichiarare prestazioni costanti o ASTRA-12 globalmente chiuso.
6. Flutter: PatientModel riceve stato_scale, badge usa server senza ValidityCalculator; pannello ExpiryPolicySettings sostituisce slider locali con editor sei scale/richieste/preavviso, salva esplicito e gestione errori. ValidityCalculator e vecchie preferenze restano compatibilita inutilizzata nel percorso attivo. Client e server vanno aggiornati insieme. Dashboard richiede rilettura dopo cambi policy.
7. Documentazione: EXPIRY_OPERATIONS.md, audit appendice F,28 casi C6 in test.md (totale144), changelog/architettura/remediation. VERSION4.0.7 propagata con bump_version.py, non build. tzdata aggiunta ai requirements per il database IANA su tutti gli ambienti.

Riprendere da checkpoint10 e appendice F. Non eseguire test finche l'utente non apre la fase dedicata. Prima rilascio: test C1-C6, validazione policy della struttura e inventario delle date anomale; benchmark per archivi grandi. I risultati test_resul.md preesistenti non attestano questa revisione. Nessun container esterno va ripulito come parte di questo lavoro.


## Checkpoint 11 - C7 in corso

Implementati: PATCH CORS; safe_csv_cell e CSV admin/no-store; password nuove/reset12 caratteri e sessione JWT60min configurabile (15..480), token browser in sessionStorage e rimozione vecchio token persistente all'avvio. AI crypto enc:v2 con chiave dedicata e keyring, lettura v1/JWT legacy esplicita, errori chiavi503 senza fallback distruttivo; endpoint admin rewrap con CAS, restore C1 verifica tutte le versioni. SSRF fail-closed, allowlist esatta, HTTPS, LAN esplicita, IP pin con Host/SNI e TLS verificato, niente proxy env/redirect. HTTPX0.27.2/httpcore1.0.9 fissati per l'estensione SNI. Backend nonroot/read-only/tmpfs/cap-drop, DB rete interna, header Nginx e API no-store. Preparati overlay Mongo auth e provision utenti senza reset; NON eseguiti. Default Compose legacy resta senza auth finche si pianifica la migrazione, residuale da dichiarare. Ancora da completare revisione sorgenti e docs/test.md/versione. Nessun test/analyzer/build/app/DB eseguito.


## Checkpoint 12 - C7 applicato localmente, versione4.0.8

Ripresa: C1-C6 implementati nel perimetro documentato; C7 fix applicativi e materiali di migrazione implementati, con ASTRA-16 parzialmente aperto per attivazione Mongo autenticato. C8-C10 aperti. Tutti da verificare nella fase test. Nessun test/analyzer/build, provider, avvio app, deploy, commit, push o intervento sul DB in questa fase. Solo revisione codice e git diff --check. Nuovi36 casi C7 in test.md, totale180.

1. ASTRA-14: main.py ammette PATCH, Compose espone CORS_ORIGINS, origini esatte preservate.
2. ASTRA-22: security.safe_csv_cell neutralizza formule anche con prefissi spazi/controlli Unicode, senza cambiare DB. CSV admin/403 altri, pulsanti disabilitati, audit avvio/no-store; date C6 a lotti100 senza vecchio taglio100 scale. Streaming interrotto non significa export completato.
3. ASTRA-17: ssrf.py URL rigorose/DNS fail-closed; allowlist esatta, tutti gli IP controllati. PubblicoHTTPS; LAN RFC1918/ULA solo flag+hostnameesatto, HTTP locale ulteriore flag. Loopback/link-local/metadata/multicast/unspecified/reserved vietati sempre. PinnedAITransport crea richiesta su IP approvato con Host e sni_hostname originali; TLS verificato, keepalive0, proxy env/redirect disabilitati, nessun replay automatico agli altri IP. Generate/test/models/fallback tutti sul trasporto. DNS async timeout15s (thread resolver non interrompibile). HTTPX0.27.2 e httpcore1.0.9 fissati sul contratto SNI; provider fissi trust_env=False.
4. Crypto IA: enc:v2 key-id e Fernet con AI_SETTINGS_ENCRYPTION_KEY>=32, nessuna nuova cifratura da JWT/seed. AI_SETTINGS_PREVIOUS_KEYS e AI_SETTINGS_LEGACY_JWT_KEYS leggono vecchi materiali; JWTcorrente supportato solo lettura v1. Decoder fallisce esplicitamente, handler503, loader settings malformate409 senza reset. Endpoint POST settings/ai/rewrap-secrets solo admin, decifra tutto prima di scrivere con CAS; header vuoti restano stringhe. Backup C1 verifica tutti gli enc:* tramite decoder comune prima restore. Conservare vecchie chiavi per archivi precedenti.
5. Sessioni: JWTsecret>=32 nonplaceholder; nuovi token60min (env15..480), precedenti restano fino al proprio exp/revoca. Password nuove/reset>=12/max72byte, blankrifiutate, login storici non reimpostati. Flutter JWT in sessionStorage, token localStorage preC7 cancellato all'avvio; UI metadata ancora locale ma server DB autorevole. Non HttpOnly, nessuna protezione completa XSS affermata.
6. Container/header: backend uid10001, readonly, tmpfs/tmp256MiB per Matplotlib, no capability/privilege escalation; DB rete interna data solo API/DB. Header Nginx inclusi anche nei location add_header (CSP object/base/frame, no script-src non verificata); API no-store. TLS/HSTS pubblico sul terminatore esterno.
7. Mongo: docker-compose.mongo-auth.yml, ops/provision_mongo_users.js pronti ma NON eseguiti. Default base compatibile noauth, non confondere con autenticazione attiva. Procedura script utenti root/app distinti, no reset, readWrite solo autanalysis, keyfile0400 con gosu, healthroot e URIapp. Per attivare occorre finestra manutenzione/inventario/backup/provision/overlay e verifica C1-C4. Solo replica set esistente gia inizializzato; no bootstrap vuoto automatico. Nessuna nuova collection. C7 resta parzialmente aperto operativamente fino all'attivazione; TLS Mongo non implementato.
8. SECURITY_OPERATIONS.md descrive procedure e limiti; audit appendice G, architettura/remediation/changelog aggiornati; VERSION4.0.8 tramite bump_version.py. Conservati test_resul.md, lock Flutter, modifiche test/service di altre attivita senza assumerle come collaudo corrente.

Alla ripresa leggere questo checkpoint e SECURITY_OPERATIONS.md. Nessun test finche richiesto. Non rimuovere container esterni o rigenerare segreti reali. Prima rilascio verificare36 casi C7, integrazione C1-C6 e pianificare attivazione Mongo autenticato; non dichiarare C7 interamente chiuso o sicurezza certificata.

Nota finale C7: loader at-rest protetto anche con CAS (sia sottodocumento IA sia migrazione legacy) e rifiuto ai persistito non-dict. Evita reset/concorrenza durante lettura/migrazione; verificare C7-16. git diff --check senza segnalazioni, nessun altro controllo eseguito.


## Checkpoint 13 - C8 in corso (2026-10-30)

Perimetro ASTRA-13/18/19/20. Discovery: audit helper assorbe errori, update/delete eval e import/update/delete scala/settings senza eventi equivalenti; PDF Paragraph con dati non uniformemente escaped, pyplotglobale e mappa POS bundled sovrascrive snapshot. License force_remote non admin, trial senza indiceunique, mantenere lifetime offline e protocollo centrale. Readiness manca DB, Flutterstable/nginxalpine e requirements mobili, nessuna CI. Strategia: eventi con versione/correlation, audit atomico nei flussi principali e segnale esplicito sui legacy postcommit; PDF escape sorgenti+figure isolate/lock; recupero backup admin a licenza scaduta gia C7presente, controlli licenza/singleflight/CAS; manifest/versioni/pipeline manuale senza eseguire build/test/deploy. Tutto da completare; nessuna verifica eseguita.


## Checkpoint 14 - C8 implementazione in revisione

Aggiunti audit.py (evento/versione/correlation, indici, record transazionale, post_commit degraded segnalato in header e snackbar Flutter); valutazioni create/update/delete, protocolli standard/SIS/import/update/delete, anagrafica create/update/delete, settings legacy/IA/policy/rewrap con audit atomico. Job enqueue/publish e report approvato/restore metadati audit coerenti. Registro admin e limite/offset stabili, API non nasconde errore. pdf_service.py: escape XML testo libero, generazione lockRLock e semaphore2/attesa5s, thread non cancellabile protetto; PDF generator Figure isolate, niente POS bundled sopra snapshot. Licenze: singletonunique parziale, lockperprocess singleflight/CAS, force_remote admin, lifetime policy invariata, deactivation non rinnova trial originario; backupadmin recuperabile in schermata licenza senza riaprire operativita. Readiness DB/replica writable e dipendenze Compose health. Manifest deps44runtime/49test da metadatiPyPI con hash, targetPython3.11Linux; nessuna installazione. Immagini pinned per digest Python3.11.14, Flutter3.41.9 (versione registrata locklocale), Nginx1.28.0, Mongo8.0.4; BUILD_VERSIONS.json. CI GitHub solo workflow_dispatch, backendtests e subsetFlutterVM+webbuild, artifact opzionali senza push/deploy; NON eseguita. Ancora da rifinire docs/test/versione e verificare per lettura collegamenti. Nessun test/analyzer/build/app/DB eseguito. Letture rete solo metadati ufficiali PyPI/registry/GitHub e docs. Generatore manifest ha richiesto un secondo passaggio per sniffio assente localmente, aggiunto pin1.3.1; non installato nulla. Files esterni preservati.


## Checkpoint 15 - C8 implementato localmente, versione4.0.9

Stato: C1-C6 fix locali nel perimetro documentato; C7 applicativo e materiali migrazione pronti, Mongoauth ancora da attivare; C8 implementato e non collaudato. C9/C10 aperti.40 nuovi casi differiti C8, totale220 in test.md. Nessun test/analyzer/installazione/renderPDF/build/CI/provider/deploy/commit/push o intervento DB cliente eseguito. Lettura/editing, metadati ufficiali registry/PyPI/GitHub e git diff --check soltanto. Preservati test_resul.md, lock Flutter e file test/service modificati da altre attivita.

- Audit: audit.py evento schema1/UUID/appversion/UTC/correlation target/versione opzionale. Indici cronologia/correlazione; middleware header X-Correlation-ID e X-Audit-Status. record(session) fallisce con rollback; post_commit per login/export/licenze remote/diagnostica segnala degraded, non falsifica fallimento di una mutazione gia conclusa. Flutter avviso via CustomEvent/messenger, API registro non maschera errori.
- Audit atomico esteso a valutazioni create/update/delete, freezelegacy, protocolli importstandard/SIS/update/delete, anagrafica CRUD, account operatori e cambio password (C2CAS/epoch mantenuti), settings legacy/IA/policy/rewrap, bozza manuale/update note/approve/delete report, enqueue e publish IA, restore C1. Job porta correlation origine; evento automatico snapshotlegacy con attore sistema. Nessun testo libero sensibile/chiave in nuovi dettagli, nessun TTL. Vecchi log non riscritti. Cache date post-create e derivata C6: guasto non trasforma piu salvataggio riuscito in errore; log generico.
- Registro solo admin API/UI, pagine API limit1..1000/offset, ordine timestamp/_id, campi opzionali perlegacy; tooltipversione/correlation. Nessuna nuova collection, backupregistro invariato.
- PDF: nuovo pdf_service.py xml_text e serialized_pdf RLock; API render_pdf semaphore2/attesa5s e503 RetryAfter5, slot mantenuto fino a fine thread cancellato. Figure Matplotlib locali, pyplot rimosso; source domande esclusivamente protocollo risolto, rimosso overwrite bundledPOS. Escape note/codici/domande/opzioni/metadati/organizzazione/dati personali, Markdown gia escaped; report libero API max1M. Niente rendering/testvisivi eseguiti, costo/memoria/tmpfs da provare.
- Licenze: unique parziale licenses.id con failesplicito su duplicati storici, lockperprocess serializza stato/activate/deactivate, force_remote admin e UIviewer nonforza. CAS su token/instance/status/lastcheck protegge aggiornamenti da risposta tardiva; non exactlyonce distribuito. Lifetimeoffline invariata e protocollo centrale non cambiato. Cache/grace non estese da timestampfuturo, InvalidTag trattato validazione non disponibile. Deactivation torna solo altrialoriginario residuo da created_at, senza nuova finestra15gg. Backupadmin pulsante nella schermata scaduta; operativita resta bloccata, restore C1 manutenzione.
- Rilascio: BUILD_VERSIONS.json e Docker/Compose pinned digest per Python3.11.14 slimbookworm, Flutter3.41.9 registrato nel progetto, Nginx1.28.0alpine, Mongo8.0.4.44 pacchetti runtime/49test in lock con hashPyPI e only-binary, requirements includono lock; targetCPython3.11Linux, nonhostPython3.14Windows. Nessuna installazione/validazione eseguita. Versioni FastAPI/Pydantic originarie preservate, HTTPX0.27.2/core1.0.9 C7.
- CI .github/workflows/verify-release.yml manuale workflow_dispatch soltanto; backendtests su Mongo effimero, tre testFlutterVM portabili e webcompile; build_images opzionale gatedsuverifica. Nessun push/deploy, artifact con hash/commit/version/imageID/lockhash. Suite browser ancora da fare con C9, ASTRA23/fixturelegacy possono bloccare prima esecuzione e non sono marcati passati. BuilderCirrus dichiarato non piu aggiornato upstream: digest evita deriva ma futura sostituzione mantenuta da pianificare.
- Readiness /health/ready controlla ping e primaryreplicaset con timeout5s; / resta liveness. Compose health API e frontend attende healthy; manutenzione permettehealth. Nuovo docker-compose.release.yml per immagini verificate e flag --no-build --pull never; overlayauthC7 va mantenuto seattivo. RELEASE_OPERATIONS.md distingue rollbackimmagini vsdati e nessuna cancellazione volumi.
- Versione4.0.9 propagata da VERSION con bump_version.py, documenti auditappendiceH/changelog/architettura/remediation/test.md aggiornati. Nuovi indici saranno creati solo al futuroavvio, non oggi.

Ripresa: leggere checkpoint15 e RELEASE_OPERATIONS.md. Mantenere stoptest finche l'utente apre la fase. C8 non equivale a rilascio verificato; restano collaudi audit/failures/legacyfixtures, PDFvisivi/concorrenza, licenzecentraleisolato, installlockLinux, CI/suitebrowser e smoke/rollback. Nessun container esterno da pulire. C7Mongoauth operativo resta aperto; C9/C10 prossimi.
