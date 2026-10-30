# Backup e ripristino C1 — Autify 4.0.3

Aggiornamento C2 (4.0.4): il cambio password personale è consentito anche in manutenzione. Dopo restore, un account con obbligo di cambio deve completarlo prima delle API backup; il vecchio admin/admin viene marcato al login anche se il backup non contiene il flag. Su nuova destinazione vuota serve INITIAL_ADMIN_PASSWORD per completare il bootstrap prima del recupero. Vedere AUTH_OPERATIONS.md e i casi differiti C1/C2 in test.md.

## Contratto e requisiti

Aggiornamento4.0.5: snapshot storici coerenti consentono backup di valutazioni anche dopo eliminazione della scala corrente; ai_jobs conserva lease_expires_at in BSON e identità del parent. Worker non avviato in manutenzione e job ripristinati non riaccodati. Il requisito replica set si estende a scritture valutazioni/protocolli, coda IA e delete anagrafiche: vedere EVALUATIONS_JOBS_OPERATIONS.md. Nessuna nuova collection.

Il database resta `autanalysis`. `backend/app/database.py::BACKUP_COLLECTIONS` contiene le dieci collection applicative, comprese `ai_jobs` e `notifications`. Una collection applicativa non registrata blocca export/restore anziché essere ignorata. Gli indici di destinazione restano attivi; gli indici applicativi sono creati dal bootstrap. Gli indici custom, gli utenti MongoDB e la configurazione del server non sono inclusi nel file applicativo: usare anche strumenti MongoDB per il disaster recovery infrastrutturale.

Il formato v2 contiene Extended JSON canonico (date BSON, ObjectId, Binary e interi BSON conservati), `schema_version`, database, versione applicativa, ID e data backup. Il file `.enc` usa AES-GCM con header autenticato e identificatore della chiave. Il limite è **64 MiB** per file cifrato, con un margine interno per header/metadati; l'export rifiuta un archivio non reimportabile per dimensioni o validazione. Non comprime dati e non estrae file ZIP. Il reverse proxy ammette 65 MiB solo sul percorso import per l'overhead multipart.

Export e restore richiedono un replica set MongoDB con primary disponibile. L'export usa una transazione di lettura `snapshot` e commit `majority`; il restore sostituisce le dieci collection e registra l'evento audit nella **stessa transazione**, comprese le liste vuote. Un errore di validazione non avvia scritture; un errore durante le scritture annulla la transazione. In caso di perdita di connessione durante commit l'esito può essere sconosciuto al client: MongoDB mantiene atomicità, ma bisogna verificare l'ID operazione nel registro prima di ripetere.

Le transazioni richiedono un runtime compatibile: [MongoDB — transazioni e limiti](https://www.mongodb.com/docs/manual/core/transactions-production-consideration/). Il servizio usa i retry transazionali del driver, evitando effetti esterni nella callback: [Motor — with_transaction](https://motor.readthedocs.io/en/stable/api-asyncio/asyncio_motor_client_session.html).

Il Compose predispone un replica set **a un solo nodo**, `autify-rs`, con inizializzazione idempotente e attesa primary. Questo abilita le transazioni ma **non fornisce alta disponibilità o ridondanza**. Un replica set esistente con nome diverso non viene riconfigurato automaticamente. Non cambiare nome del progetto Compose o volume durante un aggiornamento di installazione.

## Chiavi da custodire fuori dal backup

| Variabile | Uso |
|---|---|
| `BACKUP_ENCRYPTION_KEY` | Chiave casuale dedicata, almeno32 caratteri, obbligatoria per nuovi export; distinta da JWT |
| `BACKUP_PREVIOUS_KEYS` | Array JSON di vecchie chiavi backup, per leggere archivi precedenti dopo rotazione |
| `LEGACY_BACKUP_JWT_SECRETS` | Array JSON di vecchi segreti JWT per file `.enc` legacy; viene provato anche il JWT corrente |
| `AI_SETTINGS_ENCRYPTION_KEY` | Per ripristinare provider/header cifrati deve consentire la decifratura delle impostazioni originali |
| `JWT_SECRET_KEY` | Sessioni; è anche il fallback storico della cifratura IA se non era configurata una chiave IA separata |
| `LICENSE_SERVER_URL` / `LICENSE_SHARED_SECRET` | Conservare la configurazione licenze originaria; non sono trasportati dal backup dati |

Generare la nuova chiave con un generatore crittografico e salvarla nel secret store dell'installazione. Non inserirla in Git, log o chat. Alla rotazione, aggiungere la vecchia chiave a `BACKUP_PREVIOUS_KEYS`, impostare la nuova e ricreare il backend. Verificare lettura del vecchio backup e round-trip del nuovo prima di eliminare vecchie chiavi. L'identificatore nell'header non è la chiave e non la sostituisce.

Se la cifratura IA usava il fallback JWT e si cambia JWT nella destinazione, conservare la chiave IA originale: il validatore rifiuta il restore se una credenziale cifrata non è decifrabile. Non eliminare o azzerare le credenziali per far passare la validazione. Per migrare esplicitamente il fallback a `AI_SETTINGS_ENCRYPTION_KEY`, usare la chiave Fernet originaria derivata da `SHA256("autify-ai-salt:" + JWT originale)`, codificata base64 URL-safe, custodendola come segreto; nessuna derivazione va stampata nei log.

## Aggiornamento di una precedente installazione standalone

Questa procedura è da eseguire sull'host Docker dell'installazione, in una finestra di manutenzione. Non è stata eseguita su dati cliente durante C1.

1. Identificare il progetto Compose e il volume realmente in uso; conservare configurazione/chiavi e immagine precedente. Arrestare frontend, backend e qualsiasi writer esterno, lasciando MongoDB disponibile.
2. Prima di aggiornare il Compose, eseguire un backup infrastrutturale tramite MongoDB Database Tools sul server originale fermo alle scritture. Esempio nel container DB: `mongodump --db autanalysis --archive=/tmp/autify-pre-c1.archive`. Copiare l'archivio fuori dal container e verificarne la leggibilità in un ambiente separato. Questo archivio è sensibile e non è cifrato dall'app: custodirlo adeguatamente.
3. Applicare il Compose4.0.3 mantenendo lo stesso progetto e volume. Il comando `mongod --replSet autify-rs` e l'healthcheck inizializzano il set senza cancellare i documenti esistenti. Attendere `healthy` e `db.hello().isWritablePrimary=true`; se non avviene, fermarsi e diagnosticare senza cancellare volumi.
4. Configurare la nuova chiave backup, conservando le vecchie chiavi per compatibilità; aggiornare il backend con l'URI `replicaSet=autify-rs`. Non abilitare più processi backend durante restore.
5. Eseguire un export v2 e verificarlo su un'istanza isolata prima di riaprire il servizio. Se dati legacy non superano la validazione, usare il messaggio collection/indice per una riparazione tracciata; non disabilitare i controlli e non perdere il dump infrastrutturale.

Non usare `docker compose down -v` sull'installazione. Il rollback dell'aggiornamento infrastrutturale richiede la configurazione precedente e il backup verificato: non improvvisare la rimozione del replica set dal volume attivo.

## Export ordinario

L'amministratore può esportare dalle Impostazioni senza manutenzione: la snapshot mantiene coerenti le collection durante scritture concorrenti. Le API `GET /api/admin/export-db` e `POST /api/admin/import-db` restano disponibili all'admin anche con licenza scaduta per consentire recupero dei dati; il CSV e le operazioni educative conservano il gate licenza precedente. Utenti anonimi e viewer non possono usare export/import completi. La navigazione frontend mantiene il blocco licenza esistente: se impedisce l'accesso alle Impostazioni, usare le API autenticate con strumenti amministrativi. Questo intervento non ridisegna la schermata licenze.

Un archivio con riferimenti utente/scala non validi, hash admin di formato non valido, date malformate o collection sconosciute viene rifiutato. La validazione non dimostra che l'operatore conosca la password originale. Non correggiamo silenziosamente dati sorgente. Per archivi oltre64MiB o transazioni che superano risorse/tempo MongoDB, utilizzare backup infrastrutturale e procedura di manutenzione dedicata; aumentare il limite HTTP da solo non risolve i limiti transazionali.

## Restore controllato

1. Conservare un backup recente dello stato di destinazione e le chiavi necessarie. Verificare sorgente, versione e identità dell'installazione.
2. Fermare **tutti** i backend/worker e writer esterni della stessa base dati. Impostare `BACKUP_MAINTENANCE_MODE=true`, poi avviare **un solo backend con un solo processo Uvicorn**. Il restart è necessario: cambiare variabile in un processo già attivo non sospende i suoi job. Il Compose fornito usa un processo; configurazioni personalizzate devono rispettare questo requisito.
3. Il middleware di manutenzione ammette solo login, lettura impostazioni/utenze/licenza/audit e backup; serializza queste richieste nel processo. Blocca nuovi job IA e tutte le operazioni di dominio. Non è un lock distribuito: non protegge da processi esterni lasciati attivi.
4. Accedere come admin, aprire Impostazioni/Database, scegliere `.enc` o `.json` e confermare. Il server valida l'intero documento prima delle scritture. Nessuna importazione parziale è supportata.
5. Al successo, l'audit contiene l'ID restore e le quantità ripristinate. Le sessioni vengono revocate e la UI torna al login: usare le credenziali contenute nel backup. I job `pending/running` diventano `failed` con spiegazione; potranno essere riavviati esplicitamente, evitando doppie richieste a pagamento. Queste trasformazioni intenzionali e l'evento audit sono le differenze rispetto a un round-trip byte-per-byte.
6. Se la richiesta scade o mostra “esito commit da verificare”, non reinviarla automaticamente. Accedere con le credenziali valide dopo il possibile ripristino e controllare l'evento `IMPORT_DATABASE`/ID riportato. Finché MongoDB è irraggiungibile non dedurre successo o rollback. Mantenere manutenzione durante la verifica.
7. Verificare conteggi, date, credenziali IA, licenza e un campione di valutazioni. Disabilitare manutenzione e ricreare il backend; solo dopo riaprire gli altri servizi.

Il file non può sovrascrivere una **licenza commerciale locale di un'altra istanza**. Su destinazione vuota/trial si può recuperare l'identità originaria per sostituire un'installazione non più in uso; non avviare entrambe le copie come installazioni licenziate indipendenti. Per trasferimenti o cambi di identità seguire `LICENSE_OPERATIONS.md`. Il backup non crea una nuova licenza né cambia il contratto del server centrale.

## Compatibilità legacy

Accettati JSON ed ENC del vecchio export completo con tutte le otto collection storiche. Le due collection allora assenti sono ripristinate **vuote**, non conservate dalla destinazione. Date note in stringa vengono convertite in datetime UTC. I campi BSON già persi dal vecchio `default=str` non possono essere ricostruiti arbitrariamente; gli `_id` assenti vengono rigenerati da MongoDB, mentre gli ID applicativi devono esserci ed essere unici. Backup parziali, duplicati, senza admin valido o con riferimenti incoerenti vengono rifiutati prima delle scritture. Non viene modificata la validazione dei punteggi educativi, oggetto di C3.

## Verifica riproducibile isolata

**Fase rinviata per richiesta utente del 29 ottobre 2026.** I comandi sotto sono istruzioni per la futura verifica, non prove eseguite sulla revisione finale. Se licenza/UI impediscono la lettura audit durante il recupero, un amministratore infrastrutturale deve consultare in sola lettura `autanalysis.audit_logs` cercando `azione=IMPORT_DATABASE` e `target_id` dell'operazione. In caso di timeout senza ID ricevuto, confrontare eventi, orario, operatore e dati ripristinati prima di ripetere.

La suite `tests/test_backup_integration.py` richiede `C1_TEST_MONGODB_URL` con host127.0.0.1 e crea soltanto database `autify_c1_test_<uuid>`, eliminandoli al termine. Non impostare questa variabile verso un database cliente. Da `backend`, con replica set usa-e-getta disponibile:

```powershell
$env:C1_TEST_MONGODB_URL='mongodb://127.0.0.1:27091/?directConnection=true'
uv run --python 3.11 --with-requirements requirements.txt --with-requirements requirements-test.txt python -m pytest tests test_sis.py -q
```

In assenza della variabile le prove Mongo reali sono esplicitamente saltate; unit test ed endpoint restano eseguibili. Non confondere skip o mock con prova d'integrazione. Stato aggiornato e risultati effettivi in `file.md`.
